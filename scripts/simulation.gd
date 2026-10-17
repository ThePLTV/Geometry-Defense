class_name Simulation
extends RefCounted

var map := HexMap.new()
var towers: Array = []
var enemies: Array = []
var projectiles: Array = []
var effects: Array = []
var history: Array = []
var tower_history: Dictionary = {}
var rng := RandomNumberGenerator.new()
var credits := 360
var base_hp := 10
var next_wave := 1
var active := false
var defeated := false
var finished_event := false
var time := 0.0
var wave_time := 0.0
var next_id := 1
var spawn_queue: Array = []
var spawn_timer := 0.0
var spawn_interval := 0.85
var visuals := true
var wave_stats: Dictionary = {}
var total_earned := 0
var total_spent := 0
var total_kills := 0
var total_damage := 0.0

func _init(seed_value: int = 1) -> void:
	Balance.load_config()
	rng.seed = seed_value
	credits = int(Balance.cfg.starting_credits)
	base_hp = int(Balance.cfg.base_hp)

func tower_at(cell: Vector2i) -> Dictionary:
	for t in towers:
		if t.cell == cell:
			return t
	return {}

func find_tower(id: int) -> Dictionary:
	for t in towers:
		if t.id == id:
			return t
	return {}

func build(cell: Vector2i, kind: String) -> String:
	if not Balance.KINDS.has(kind):
		return "Неизвестный класс"
	var error := map.validate_build(cell, enemies)
	if not error.is_empty():
		return error
	var price := int(Balance.tower(kind).price)
	if credits < price:
		return "Недостаточно геокредитов"
	var t := {"id":next_id,"cell":cell,"kind":kind,"d":0,"s":0,"ultimate":false,
		"mega":false,"invested":price,"cd":0.0,"streak":0.0,"idle":0.0,"parents":[],
		"damage":0.0,"kills":0,"ultimate_hits":0,"status":"active"}
	next_id += 1
	towers.append(t)
	tower_history[str(t.id)] = t
	credits -= price
	total_spent += price
	map.occupied[cell] = t.id
	map.rebuild()
	return ""

func upgrade(id: int, branch: String) -> String:
	var t := find_tower(id)
	if t.is_empty() or not ["d","s"].has(branch):
		return "Башня не найдена"
	if t.mega or int(t[branch]) >= 10:
		return "Достигнут максимум"
	var cost := Balance.upgrade_cost(t.kind, int(t[branch]) + 1)
	if credits < cost:
		return "Недостаточно геокредитов"
	credits -= cost
	t.invested += cost
	total_spent += cost
	t[branch] += 1
	return ""

func buy_ultimate(id: int) -> String:
	var t := find_tower(id)
	if t.is_empty() or t.ultimate:
		return "Ультимейт уже открыт"
	if t.d < 5 or t.s < 5:
		return "Нужны обе ветки 5/10"
	var cost := Balance.ultimate_cost(t.kind)
	if credits < cost:
		return "Недостаточно геокредитов"
	credits -= cost
	t.invested += cost
	total_spent += cost
	t.ultimate = true
	return ""

func sell(id: int) -> int:
	var t := find_tower(id)
	if t.is_empty():
		return 0
	var refund: int = int(floor(float(t.invested) * Balance.cfg.sell_ratio))
	credits += refund
	t.status = "sold"
	towers.erase(t)
	map.occupied.erase(t.cell)
	map.rebuild()
	return refund

func can_merge(a: Dictionary, b: Dictionary) -> bool:
	return not a.is_empty() and not b.is_empty() and a.id != b.id and a.kind == b.kind and \
		not a.mega and not b.mega and a.d == 10 and a.s == 10 and b.d == 10 and b.s == 10 and \
		a.ultimate and b.ultimate and HexMap.DIRS.has(b.cell - a.cell)

func merge(first_id: int, second_id: int) -> String:
	var a := find_tower(first_id)
	var b := find_tower(second_id)
	if not can_merge(a,b):
		return "Нужны соседние башни одного класса: 10/10 и ультимейты"
	# Archive both source identities. The resulting entity has its own ID.
	var result: Dictionary = a.duplicate(true)
	result.id = next_id
	next_id += 1
	result.parents = [a.id,b.id]
	result.mega = true
	result.invested = a.invested + b.invested
	result.damage = 0.0
	result.kills = 0
	result.ultimate_hits = 0
	result.cd = 0.0
	result.streak = 0.0
	a.status = "merged"
	b.status = "merged"
	towers.erase(a)
	towers.erase(b)
	towers.append(result)
	tower_history[str(result.id)] = result
	map.occupied.erase(b.cell)
	map.occupied[a.cell] = result.id
	map.rebuild()
	return ""

func start_wave() -> bool:
	if active or defeated:
		return false
	finished_event = false
	active = true
	wave_time = 0.0
	spawn_timer = 0.0
	var w := next_wave
	wave_stats = {"wave":w,"spawned":0,"killed":0,"leaked":0,"earned":0,
		"damage":0.0,"hp_start":base_hp,"spent_start":total_spent,"enemy_hp":0.0,"composition":{}}
	var count: int = mini(int(Balance.cfg.wave_count_start + Balance.cfg.wave_count_step * (w-1)), int(Balance.cfg.wave_count_max))
	spawn_interval = maxf(Balance.cfg.spawn_min, Balance.cfg.spawn_start - Balance.cfg.spawn_decrease * (w-1))
	spawn_queue.clear()
	for i in range(count):
		var kind := "normal"
		var roll := rng.randf()
		var cumulative := 0.0
		for candidate in Balance.cfg.enemy_mix:
			if candidate != "normal" and w < int(Balance.cfg.enemy_introduction[candidate]):
				continue
			cumulative += float(Balance.cfg.enemy_mix[candidate])
			if roll <= cumulative:
				kind = candidate
				break
		spawn_queue.append(kind)
	if w % 5 == 0:
		spawn_queue.insert(int(count / 2.0), "boss")
	return true

func spawn_enemy(kind: String, wave: int = -1) -> Dictionary:
	var w: int = next_wave if wave < 0 else wave
	var boss_data := Balance.boss(w) if kind == "boss" else {}
	var data: Dictionary = Balance.cfg.enemies.normal if kind == "boss" else Balance.cfg.enemies[kind]
	var hp: float = Balance.cfg.enemy_base_hp * Balance.hp_multiplier(w) * (Balance.cfg.boss_hp if kind == "boss" else data.hp)
	var reward: int = int(round(Balance.cfg.enemy_base_reward * (Balance.cfg.boss_reward if kind == "boss" else data.reward) * Balance.reward_growth(w)))
	var e := {"id":next_id,"kind":kind,"hp":hp,"max_hp":hp,
		"speed":float(Balance.cfg.boss_speed if kind == "boss" else data.speed),"reward":reward,
		"cell":map.spawn,"next":map.next_cell(map.spawn),"progress":0.0,"trail":[map.spawn],
		"pos":HexMap.point(map.spawn),"dead":false,"immune":boss_data.get("immune",""),
		"resist":Balance.KINDS[rng.randi_range(0,3)] if kind == "resistant" else "",
		"color":boss_data.get("color",data.color),"pushes":[]}
	next_id += 1
	enemies.append(e)
	if not wave_stats.is_empty():
		wave_stats.spawned += 1
		wave_stats.enemy_hp += hp
		wave_stats.composition[kind] = int(wave_stats.composition.get(kind,0)) + 1
	return e

func nearest(position: Vector2, radius: float, excluded: Array = []) -> Dictionary:
	var best: Dictionary = {}
	var distance := radius * radius + 0.000001
	for e in enemies:
		if e.dead or excluded.has(e.id):
			continue
		var candidate: float = position.distance_squared_to(e.pos)
		if candidate < distance - 0.0000001 or (absf(candidate-distance) < 0.0000001 and (best.is_empty() or e.id < best.id)):
			distance = candidate
			best = e
	return best

func enemy_by_id(id: int) -> Dictionary:
	for e in enemies:
		if e.id == id and not e.dead:
			return e
	return {}

func hit(e: Dictionary, amount: float, t: Dictionary, ultimate_effect: bool = false) -> bool:
	if e.dead or e.immune == t.kind:
		return false
	var value := amount
	if e.kind == "armored":
		value *= 1.0 - Balance.cfg.armor_reduction
	if e.resist == t.kind:
		value *= 1.0 - Balance.cfg.resistance_reduction
	var actual: float = minf(value,e.hp)
	e.hp -= value
	t.damage += actual
	total_damage += actual
	if not wave_stats.is_empty():
		wave_stats.damage += actual
	if ultimate_effect:
		t.ultimate_hits += 1
	if e.hp <= 0:
		kill(e,t)
	return true

func kill(e: Dictionary, t: Dictionary) -> void:
	if e.dead:
		return
	e.dead = true
	t.kills += 1
	total_kills += 1
	if not wave_stats.is_empty():
		wave_stats.killed += 1
	var reward: int = int(e.reward)
	if e.kind == "split":
		var parent_reward: int = int(floor(reward * 0.25))
		var remaining := reward - parent_reward
		for i in range(int(Balance.cfg.split_children)):
			var child: Dictionary = e.duplicate(true)
			child.id = next_id
			next_id += 1
			child.kind = "child"
			child.dead = false
			child.max_hp = e.max_hp * Balance.cfg.split_hp
			child.hp = child.max_hp
			child.speed = 1.15
			child.reward = int(remaining / 2.0) if i == 0 else remaining - int(remaining / 2.0)
			child.pushes = []
			enemies.append(child)
			if not wave_stats.is_empty():
				wave_stats.spawned += 1
				wave_stats.enemy_hp += child.hp
		reward = parent_reward
	credits += reward
	total_earned += reward
	if not wave_stats.is_empty():
		wave_stats.earned += reward

func add_effect(type: String, a: Vector2, b: Vector2, color: Color, radius: float = 0.0) -> void:
	if visuals:
		if effects.size() >= 256:
			effects.pop_front()
		effects.append({"type":type,"a":a,"b":b,"color":color,"radius":radius,"life":0.25,"duration":0.25})

func push_back(e: Dictionary, t: Dictionary, amount: float) -> float:
	if e.dead or e.immune == t.kind:
		return 0.0
	var recent: Array = []
	var used := 0.0
	for entry in e.pushes:
		if time - float(entry[0]) < 1.0:
			recent.append(entry)
			used += float(entry[1])
	var cap: float = minf(Balance.cfg.push_limit_per_second, e.speed * Balance.cfg.push_max_speed_fraction)
	var allowed := minf(amount * (Balance.cfg.boss_push_factor if e.kind == "boss" else 1.0), maxf(0.0,cap-used))
	var left := allowed
	while left > 0.000001:
		if e.progress > 0:
			var step: float = minf(left,e.progress)
			e.progress -= step
			left -= step
		elif e.trail.size() > 1:
			var previous: Vector2i = e.trail[e.trail.size()-2]
			if map.occupied.has(previous):
				break
			e.next = e.cell
			e.trail.pop_back()
			e.cell = previous
			e.progress = 1.0
		else:
			break
	e.pos = HexMap.point(e.cell).lerp(HexMap.point(e.next), e.progress)
	var actual := allowed - left
	recent.append([time,actual])
	e.pushes = recent
	return actual

func shoot(t: Dictionary, target: Dictionary) -> void:
	var from := HexMap.point(t.cell)
	var amount := Balance.damage(t)
	var color := Color(Balance.tower(t.kind).color)
	match t.kind:
		"Minigun":
			hit(target,amount,t,t.ultimate and t.streak >= (Balance.cfg.mega_minigun_warmup if t.mega else Balance.cfg.minigun_warmup))
			add_effect("bullet",from,target.pos,color)
		"Laser":
			var current := target
			var previous := from
			var seen: Array = []
			var count: int = 1 + (int(Balance.cfg.mega_laser_bounces if t.mega else Balance.cfg.laser_bounces) if t.ultimate else 0)
			for index in range(count):
				if current.is_empty():
					break
				seen.append(current.id)
				add_effect("laser",previous,current.pos,color)
				if not hit(current,amount,t,index > 0):
					break
				previous = current.pos
				amount *= Balance.cfg.laser_decay
				current = nearest(previous,Balance.cfg.laser_bounce_range,seen)
		"Rocket":
			projectile(from,target,t,amount,false)
		"Shockwave":
			var reach := Balance.reach(t)
			add_effect("ring",from,from,color,reach)
			for e in enemies.duplicate():
				if not e.dead and from.distance_squared_to(e.pos) <= reach*reach:
					if hit(e,amount,t,t.ultimate) and t.ultimate:
						push_back(e,t,Balance.cfg.mega_shock_push if t.mega else Balance.cfg.shock_push)

func projectile(from: Vector2, target: Dictionary, tower: Dictionary, damage_value: float, mini: bool) -> void:
	if projectiles.size() >= int(Balance.cfg.max_projectiles):
		# The cap is a fallback only; resolve the hit instead of dropping damage.
		explode(target.pos,tower,damage_value,mini)
		return
	projectiles.append({"pos":from,"target":target.id,"owner":tower,"damage":damage_value,"mini":mini,"life":8.0})

func explode(position: Vector2, t: Dictionary, amount: float, mini: bool) -> void:
	var radius: float = Balance.cfg.mini_radius if mini else Balance.cfg.rocket_radius
	add_effect("blast",position,position,Color(Balance.tower(t.kind).color),radius)
	for e in enemies.duplicate():
		if not e.dead and position.distance_squared_to(e.pos) <= radius*radius:
			hit(e,amount,t,mini)
	if not mini and t.ultimate:
		var count: int = int(Balance.cfg.mega_mini_count if t.mega else Balance.cfg.mini_count)
		var picked: Array = []
		for i in range(count):
			var target := nearest(position,Balance.cfg.mini_search,picked)
			if target.is_empty():
				target = nearest(position,Balance.cfg.mini_search)
			if target.is_empty():
				break
			picked.append(target.id)
			projectile(position,target,t,amount*Balance.cfg.mini_damage,true)

func move_enemy(e: Dictionary, delta: float) -> void:
	var travel: float = e.speed * delta
	while travel > 0.000001 and not e.dead:
		if e.cell == map.goal:
			e.dead = true
			base_hp -= 1
			if not wave_stats.is_empty():
				wave_stats.leaked += 1
			break
		if e.progress <= 0.000001:
			e.next = map.next_cell(e.cell)
		if e.next == e.cell:
			push_error("Path invariant failed at %s" % e.cell)
			break
		var step: float = minf(travel,1.0-e.progress)
		e.progress += step
		travel -= step
		if e.progress >= 0.999999:
			e.cell = e.next
			e.progress = 0.0
			e.trail.append(e.cell)
	e.pos = HexMap.point(e.cell).lerp(HexMap.point(e.next), e.progress)

func step(delta: float) -> void:
	if not active or defeated:
		return
	time += delta
	wave_time += delta
	spawn_timer -= delta
	while spawn_timer <= 0.0 and not spawn_queue.is_empty():
		spawn_enemy(spawn_queue.pop_front())
		spawn_timer += spawn_interval
	for e in enemies:
		if not e.dead:
			move_enemy(e,delta)
		if base_hp <= 0:
			base_hp = 0
			defeated = true
			active = false
			return
	for t in towers:
		t.cd -= delta
		var target := nearest(HexMap.point(t.cell),Balance.reach(t))
		if target.is_empty():
			t.idle += delta
			if t.idle > Balance.cfg.minigun_reset:
				t.streak = 0.0
			t.cd = maxf(t.cd,0.0)
			continue
		t.idle = 0.0
		t.streak += delta
		var rate := Balance.rate(t)
		if t.kind == "Minigun" and t.ultimate and t.streak >= (Balance.cfg.mega_minigun_warmup if t.mega else Balance.cfg.minigun_warmup):
			rate *= 2.0
		var safety := 0
		while t.cd <= 0.0 and not target.is_empty() and safety < 16:
			shoot(t,target)
			t.cd += 1.0/rate
			safety += 1
			target = nearest(HexMap.point(t.cell),Balance.reach(t))
	var flying := projectiles.duplicate()
	for p in flying:
		p.life -= delta
		var target := enemy_by_id(p.target)
		if target.is_empty() or p.life <= 0:
			projectiles.erase(p)
			explode(p.pos,p.owner,p.damage,p.mini)
			continue
		var speed: float = Balance.cfg.mini_speed if p.mini else Balance.cfg.rocket_speed
		if p.pos.distance_to(target.pos) <= speed * delta:
			projectiles.erase(p)
			explode(target.pos,p.owner,p.damage,p.mini)
		else:
			p.pos = p.pos.move_toward(target.pos,speed*delta)
	for i in range(enemies.size()-1,-1,-1):
		if enemies[i].dead:
			enemies.remove_at(i)
	for i in range(effects.size()-1,-1,-1):
		effects[i].life -= delta
		if effects[i].life <= 0:
			effects.remove_at(i)
	if spawn_queue.is_empty() and enemies.is_empty():
		complete_wave()

func complete_wave() -> void:
	var bonus: int = int(Balance.cfg.wave_bonus_base + Balance.cfg.wave_bonus_step*next_wave)
	if next_wave % 5 == 0:
		bonus += int(Balance.cfg.boss_bonus_base + Balance.cfg.boss_bonus_step*next_wave)
	credits += bonus
	total_earned += bonus
	wave_stats.earned += bonus
	wave_stats.seconds = wave_time
	wave_stats.hp_end = base_hp
	wave_stats.spent = total_spent - wave_stats.spent_start
	wave_stats.path_length = map.route(map.spawn).size()
	history.append(wave_stats.duplicate(true))
	next_wave += 1
	active = false
	finished_event = true
	projectiles.clear()
	for t in towers:
		t.cd = 0.0
		t.streak = 0.0
		t.idle = 0.0

func snapshot() -> Dictionary:
	var rows: Array = []
	for t in towers:
		var row: Dictionary = t.duplicate(true)
		row.cell = HexMap.pack(t.cell)
		row.cd = 0.0
		row.streak = 0.0
		row.idle = 0.0
		rows.append(row)
	var archive: Array = []
	for key in tower_history:
		var row: Dictionary = tower_history[key].duplicate(true)
		row.cell = HexMap.pack(row.cell)
		archive.append(row)
	return {"schema":2,"map_schema":2,"credits":credits,"base_hp":base_hp,"next_wave":next_wave,
		"next_id":next_id,"towers":rows,"tower_history":archive,"history":history.duplicate(true),
		"rng_state":str(rng.state),"rng_seed":str(rng.seed),"total_earned":total_earned,
		"total_spent":total_spent,"total_kills":total_kills,"total_damage":total_damage}

func restore(data: Dictionary) -> bool:
	if int(data.get("schema",0)) != 2 or int(data.get("map_schema",0)) != 2:
		return false
	var restored_map := HexMap.new()
	var loaded: Array = []
	var ids: Dictionary = {}
	for raw in data.get("towers",[]):
		var t: Dictionary = raw.duplicate(true)
		if not t.has("cell") or t.cell is not Array or t.cell.size() != 2:
			return false
		t.cell = HexMap.unpack(t.cell)
		if not Balance.KINDS.has(t.get("kind","")) or restored_map.validate_build(t.cell,[]) != "" or ids.has(str(t.get("id",-1))):
			return false
		if int(t.get("d",-1)) < 0 or int(t.d) > 10 or int(t.get("s",-1)) < 0 or int(t.s) > 10:
			return false
		restored_map.occupied[t.cell] = t.id
		ids[str(t.id)] = true
		loaded.append(t)
	restored_map.rebuild()
	if not restored_map.distances.has(restored_map.spawn) or int(data.get("base_hp",0)) <= 0 or int(data.base_hp) > 10:
		return false
	map = restored_map
	towers = loaded
	tower_history.clear()
	for raw in data.get("tower_history",[]):
		var row: Dictionary = raw.duplicate(true)
		row.cell = HexMap.unpack(row.cell)
		tower_history[str(row.id)] = row
	for t in towers:
		tower_history[str(t.id)] = t
	credits = int(data.credits)
	base_hp = int(data.base_hp)
	next_wave = int(data.next_wave)
	next_id = int(data.next_id)
	rng.seed = int(data.rng_seed)
	rng.state = int(data.rng_state)
	history = data.get("history",[]).duplicate(true)
	total_earned = int(data.get("total_earned",0))
	total_spent = int(data.get("total_spent",0))
	total_kills = int(data.get("total_kills",0))
	total_damage = float(data.get("total_damage",0))
	active = false
	defeated = false
	finished_event = false
	enemies.clear()
	projectiles.clear()
	effects.clear()
	return true
