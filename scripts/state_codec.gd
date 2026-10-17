class_name StateCodec
extends RefCounted

static func encode(value):
	if value is Vector2i:
		return {"$i":[value.x,value.y]}
	if value is Vector2:
		return {"$v":[value.x,value.y]}
	if value is Array:
		var result: Array = []
		for item in value:
			result.append(encode(item))
		return result
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value:
			result[str(key)] = encode(value[key])
		return result
	return value

static func decode(value):
	if value is Dictionary:
		if value.has("$i"):
			return Vector2i(int(value["$i"][0]),int(value["$i"][1]))
		if value.has("$v"):
			return Vector2(float(value["$v"][0]),float(value["$v"][1]))
		var result: Dictionary = {}
		for key in value:
			result[key] = decode(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value:
			result.append(decode(item))
		return result
	return value

static func capture(s, include_wave: bool) -> Dictionary:
	return {"schema":3,"map_schema":2,"credits":s.credits,"base_hp":s.base_hp,"next_wave":s.next_wave,
		"next_id":s.next_id,"towers":encode(s.towers),"tower_history":encode(s.tower_history.values()),
		"history":encode(s.history),"merges":encode(s.merges),"rng_state":str(s.rng.state),"rng_seed":str(s.rng.seed),
		"total_earned":s.total_earned,"total_spent":s.total_spent,"total_kills":s.total_kills,"total_damage":s.total_damage,
		"time":s.time,"wave_time":s.wave_time,"active":s.active if include_wave else false,
		"enemies":encode(s.enemies) if include_wave else [],"projectiles":encode(s.projectiles) if include_wave else [],
		"spawn_queue":s.spawn_queue.duplicate() if include_wave else [],"spawn_timer":s.spawn_timer,
		"spawn_interval":s.spawn_interval,"wave_stats":encode(s.wave_stats)}

static func migrate_tower(raw: Dictionary) -> Dictionary:
	var t := raw.duplicate(true)
	if t.cell is Array:
		t.cell = HexMap.unpack(t.cell)
	if not t.has("level"):
		t.level = 10 if t.get("ultimate",false) or t.get("mega",false) else clampi(1+int(round((float(t.get("d",0))+float(t.get("s",0)))*9.0/20.0)),1,10)
	for key in ["d","s","streak","idle"]:
		t.erase(key)
	var defaults := {"job":"","job_left":0.0,"job_total":0.0,"angle":-PI/2,"previous_angle":-PI/2,
		"flash":0.0,"reverse_clock":100.0,"parents":[],"ultimate_hits":0,"status":"active","cd":0.0,
		"damage":0.0,"kills":0,"ultimate":false,"mega":false}
	for key in defaults:
		if not t.has(key):
			t[key] = defaults[key]
	return t

static func valid_tree(value, depth: int = 0) -> bool:
	if depth>30: return false
	if value is float and not is_finite(value): return false
	if value is Dictionary:
		for marker in ["$i","$v"]:
			if value.has(marker):
				var point=value[marker]
				return point is Array and point.size()==2 and (point[0] is float or point[0] is int) and (point[1] is float or point[1] is int)
		for key in value:
			if not valid_tree(value[key],depth+1): return false
	if value is Array:
		for item in value:
			if not valid_tree(item,depth+1): return false
	return true

static func has_keys(value, keys: Array) -> bool:
	if value is not Dictionary: return false
	for key in keys:
		if not value.has(key): return false
	return true

static func restore(s, raw: Dictionary) -> bool:
	if not valid_tree(raw): return false
	if not int(raw.get("schema",0)) in [2,3] or int(raw.get("map_schema",0)) != 2:
		return false
	for key in ["credits","base_hp","next_wave","next_id","towers","rng_seed","rng_state"]:
		if not raw.has(key):
			return false
	var data: Dictionary = decode(raw)
	for key in ["credits","base_hp","next_wave","next_id"]:
		if data[key] is not int and data[key] is not float: return false
	for key in ["towers","tower_history","history","merges","enemies","projectiles","spawn_queue"]:
		if data.get(key,[]) is not Array: return false
	var old := int(data.schema) == 2
	if int(data.base_hp) <= 0 or int(data.base_hp) > 10 or int(data.credits) < 0 or int(data.next_wave) < 1:
		return false
	var grid := HexMap.new()
	var loaded: Array = []
	var ids: Dictionary = {}
	for item in data.towers:
		if not has_keys(item,["cell","id","kind","invested"]):
			return false
		if item.cell is Array and item.cell.size()!=2: return false
		var t := migrate_tower(item)
		if t.cell is not Vector2i or not Balance.KINDS.has(t.get("kind","")) or grid.validate_build(t.cell,[]) != "" or ids.has(str(t.id)):
			return false
		if int(t.level) < 1 or int(t.level) > 10 or int(t.get("invested",-1)) < 0 or not ["","upgrade","ultimate","merge"].has(t.job):
			return false
		if t.job_left < 0 or t.job_left > 5.00001:
			return false
		grid.occupied[t.cell] = t.id
		loaded.append(t)
		ids[str(t.id)] = t
	grid.rebuild()
	if not grid.distances.has(grid.spawn):
		return false
	var operations: Array = data.get("merges",[])
	var merge_ids: Dictionary = {}
	for operation in operations:
		if not has_keys(operation,["a","b","left","total"]): return false
		if operation.left is not float and operation.left is not int: return false
		if operation.left<0 or operation.left>5.00001: return false
		var a: Dictionary = ids.get(str(operation.get("a",-1)),{})
		var b: Dictionary = ids.get(str(operation.get("b",-1)),{})
		if a.is_empty() or b.is_empty() or a.id == b.id or a.kind != b.kind or a.job != "merge" or b.job != "merge" or merge_ids.has(a.id) or merge_ids.has(b.id):
			return false
		if not HexMap.DIRS.has(b.cell-a.cell) or a.level != 10 or b.level != 10 or not a.ultimate or not b.ultimate:
			return false
		merge_ids[a.id] = true
		merge_ids[b.id] = true
	for t in loaded:
		if t.job == "merge" and not merge_ids.has(t.id):
			return false
	var live: Array = data.get("enemies",[])
	for e in live:
		if not has_keys(e,["id","kind","hp","max_hp","speed","reward","cell","next","progress","trail","pos","dead","immune","color","pushes","last_hit"]): return false
		if e.cell is not Vector2i or e.next is not Vector2i or not grid.distances.has(e.cell) or not grid.distances.has(e.next):
			return false
		if e.pos is not Vector2 or e.trail is not Array or e.pushes is not Array: return false
		if e.progress < 0 or e.progress > 1.00001:
			return false
	for projectile in data.get("projectiles",[]):
		if not has_keys(projectile,["type","pos","previous_pos","owner_id","damage","life"]): return false
		if projectile.type not in ["bullet","rocket","wave"] or projectile.pos is not Vector2: return false
		var extra: Array = {"bullet":["target","bounced"],"rocket":["target","mini","velocity"],"wave":["radius","previous_radius","maximum","hit","reverse"]}[projectile.type]
		if not has_keys(projectile,extra): return false
	if data.get("active",false):
		if not has_keys(data.get("wave_stats",{}),["wave","spawned","killed","leaked","earned","damage","hp_start","spent_start","enemy_hp","composition"]): return false
	for item in data.get("tower_history",[]):
		if not has_keys(item,["id","cell","kind","invested"]): return false
		if item.cell is Array and item.cell.size()!=2: return false
	s.map = grid
	s.towers = loaded
	s.tower_history.clear()
	for item in data.get("tower_history",[]):
		var t := migrate_tower(item)
		s.tower_history[str(t.id)] = t
	for t in loaded:
		s.tower_history[str(t.id)] = t
	s.credits = int(data.credits)
	s.base_hp = int(data.base_hp)
	s.next_wave = int(data.next_wave)
	s.next_id = int(data.next_id)
	s.rng.seed = int(data.rng_seed)
	s.rng.state = int(data.rng_state)
	s.history = data.get("history",[]).duplicate(true)
	s.merges = operations
	s.time = float(data.get("time",0))
	s.wave_time = float(data.get("wave_time",0))
	s.active = bool(data.get("active",false))
	s.enemies = live
	s.projectiles = data.get("projectiles",[])
	s.spawn_queue = data.get("spawn_queue",[])
	s.spawn_timer = float(data.get("spawn_timer",0))
	s.spawn_interval = float(data.get("spawn_interval",Balance.cfg.spawn_interval))
	s.wave_stats = data.get("wave_stats",{})
	s.total_earned = int(data.get("total_earned",0))
	s.total_spent = int(data.get("total_spent",0))
	s.total_kills = int(data.get("total_kills",0))
	s.total_damage = float(data.get("total_damage",0))
	s.defeated = false
	s.finished_event = false
	s.effects.clear()
	s.migration_note = "Сохранение 0.1 переведено на единые уровни; вложения и валюта сохранены." if old else ""
	return true
