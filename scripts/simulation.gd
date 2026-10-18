class_name Simulation
extends RefCounted

var map := HexMap.new()
var towers: Array = []
var enemies: Array = []
var projectiles: Array = []
var effects: Array = []
var merges: Array = []
var history: Array = []
var tower_history: Dictionary = {}
var rng := RandomNumberGenerator.new()
var credits := 50
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
var spawn_interval := 1.15
var visuals := true
var wave_stats: Dictionary = {}
var total_earned := 0
var total_spent := 0
var total_kills := 0
var total_damage := 0.0
var migration_note := ""
var diagnostics: CombatDiagnostics
var wave_config: Dictionary={}
var wave_reward_paid:=false
var rules: Dictionary={"pressure":1.0,"hp":1.0,"money":1.0}
var wave_rules: Dictionary=rules.duplicate()

static func clean_rules(raw) -> Dictionary:
	var result: Dictionary={"pressure":1.0,"hp":1.0,"money":1.0}
	if raw is Dictionary:
		for key in result:
			if raw.get(key) is float or raw.get(key) is int:
				result[key]=clampf(float(raw[key]),.7 if key=="hp" else .75 if key=="pressure" else .25,2.0 if key=="hp" else 1.5 if key=="pressure" else 3.0)
	return result

func _init(seed_value: int = 1) -> void:
	Balance.load_config()
	rng.seed = seed_value
	credits = int(Balance.cfg.starting_credits)
	diagnostics=CombatDiagnostics.new(seed_value)

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

func owner(id: int) -> Dictionary:
	return tower_history.get(str(id),{})

func build(cell: Vector2i, kind: String) -> String:
	if not Balance.KINDS.has(kind):
		return "Неизвестный класс"
	var error := map.validate_build(cell,enemies)
	if not error.is_empty():
		return error
	var price := int(Balance.tower(kind).price)
	if credits < price:
		return "Недостаточно геокредитов"
	var t := {"id":next_id,"cell":cell,"kind":kind,"level":1,"ultimate":false,
		"mega":false,"invested":price,"cd":0.0,"parents":[],"damage":0.0,"kills":0,
		"ultimate_hits":0,"status":"active","job":"","job_left":0.0,"job_total":0.0,
		"angle":-PI/2,"previous_angle":-PI/2,"flash":0.0,"reverse_clock":100.0}
	next_id += 1
	towers.append(t)
	tower_history[str(t.id)] = t
	credits -= price
	total_spent += price
	map.occupied[cell] = t.id
	map.rebuild()
	ensure_tower_stats(t)
	t.built_at=time
	diagnostics.action("tower_build",time,diagnostics.tower_context(t).merged({"paid":price}))
	return ""

func begin_job(t: Dictionary, type: String, seconds: float) -> void:
	t.job = type
	t.job_left = seconds
	t.job_total = seconds
	t.cd = 0.0
	diagnostics.action(type+"_start",time,diagnostics.tower_context(t))
	for i in range(projectiles.size()-1,-1,-1):
		if projectiles[i].owner_id == t.id:
			projectiles.remove_at(i)

func upgrade(id: int, _legacy_branch: String = "") -> String:
	var t := find_tower(id)
	if t.is_empty():
		return "Башня не найдена"
	if not t.job.is_empty():
		return "Установка уже идёт"
	if t.mega or t.level >= 10:
		return "Достигнут максимум"
	var cost := Balance.upgrade_cost(t.kind,t.level+1)
	if credits < cost:
		return "Недостаточно геокредитов"
	credits -= cost
	t.invested += cost
	total_spent += cost
	begin_job(t,"upgrade",Balance.cfg.upgrade_seconds)
	return ""

func buy_ultimate(id: int) -> String:
	var t := find_tower(id)
	if t.is_empty():
		return "Башня не найдена"
	if not t.job.is_empty():
		return "Установка уже идёт"
	if t.ultimate:
		return "Ульта уже установлена"
	if t.level < 10:
		return "Нужен уровень 10"
	var cost := Balance.ultimate_cost(t.kind)
	if credits < cost:
		return "Недостаточно геокредитов"
	credits -= cost
	t.invested += cost
	total_spent += cost
	begin_job(t,"ultimate",Balance.cfg.upgrade_seconds)
	return ""

func cancel_merge(id: int) -> void:
	for i in range(merges.size()-1,-1,-1):
		var operation: Dictionary = merges[i]
		if operation.a == id or operation.b == id:
			for tower_id in [operation.a,operation.b]:
				var t := find_tower(tower_id)
				if not t.is_empty():
					t.job = ""
					t.job_left = 0.0
					t.job_total = 0.0
			merges.remove_at(i)

func sell(id: int) -> int:
	var t := find_tower(id)
	if t.is_empty():
		return 0
	cancel_merge(id)
	var refund := int(floor(t.invested*Balance.cfg.sell_ratio))
	credits += refund
	t.status = "sold"
	t.job = "sold"
	for p in projectiles.duplicate():
		if p.owner_id == id:
			projectiles.erase(p)
	towers.erase(t)
	map.occupied.erase(t.cell)
	map.rebuild()
	diagnostics.action("sell",time,{"tower_id":id,"refund":refund})
	return refund

func can_merge(a: Dictionary, b: Dictionary) -> bool:
	return not a.is_empty() and not b.is_empty() and a.id != b.id and a.kind == b.kind and \
		not a.mega and not b.mega and a.level == 10 and b.level == 10 and \
		a.ultimate and b.ultimate and a.job.is_empty() and b.job.is_empty() and HexMap.DIRS.has(b.cell-a.cell)

func merge(first_id: int, second_id: int) -> String:
	var a := find_tower(first_id)
	var b := find_tower(second_id)
	if not can_merge(a,b):
		return "Нужны соседние башни одного класса: уровень 10, установленные ульты"
	begin_job(a,"merge",Balance.cfg.merge_seconds)
	begin_job(b,"merge",Balance.cfg.merge_seconds)
	merges.append({"a":a.id,"b":b.id,"left":float(Balance.cfg.merge_seconds),"total":float(Balance.cfg.merge_seconds)})
	diagnostics.action("fusion_start",time,{"a":a.id,"b":b.id})
	return ""

func finish_merge(a: Dictionary, b: Dictionary) -> void:
	var result: Dictionary = a.duplicate(true)
	result.id = next_id
	next_id += 1
	result.parents = [a.id,b.id]
	result.mega = true
	result.invested = a.invested+b.invested
	result.damage = 0.0
	result.kills = 0
	result.ultimate_hits = 0
	result.cd = 0.0
	result.job = ""
	result.job_left = 0.0
	result.job_total = 0.0
	a.status = "merged"
	b.status = "merged"
	a.job = ""
	b.job = ""
	towers.erase(a)
	towers.erase(b)
	towers.append(result)
	tower_history[str(result.id)] = result
	map.occupied.erase(b.cell)
	map.occupied[a.cell] = result.id
	for key in ["shots","hits","misses","attempted","overkill","boss_damage","expected_attacks"]: result[key]=0
	result.idle_seconds={}
	diagnostics.action("fusion_finish",time,{"a":a.id,"b":b.id,"tower_id":result.id})
	map.rebuild()

func update_jobs(delta: float) -> void:
	for t in towers:
		t.flash = maxf(0,t.flash-delta)
		t.reverse_clock += delta
		if t.job.is_empty() or t.job == "merge":
			continue
		t.job_left = maxf(0,t.job_left-delta)
		if t.job_left <= .000001:
			diagnostics.action(t.job+"_finish",time,diagnostics.tower_context(t))
			if t.job == "upgrade":
				t.level += 1
			elif t.job == "ultimate":
				t.ultimate = true
			t.job = ""
			t.cd = 0.0
	for i in range(merges.size()-1,-1,-1):
		var operation: Dictionary = merges[i]
		operation.left = maxf(0,operation.left-delta)
		var a := find_tower(operation.a)
		var b := find_tower(operation.b)
		if a.is_empty() or b.is_empty():
			cancel_merge(operation.a)
			continue
		a.job_left = operation.left
		b.job_left = operation.left
		if operation.left <= .000001:
			finish_merge(a,b)
			merges.remove_at(i)

func start_wave() -> bool:
	if active or defeated: return false
	finished_event=false
	active=true
	wave_reward_paid=false
	wave_time=0
	spawn_timer=0
	wave_rules=rules.duplicate()
	wave_config=WaveCatalog.generate(next_wave)
	wave_stats={"wave":next_wave,"spawned":0,"killed":0,"leaked":0,"earned":0,"damage":0.0,"hp_start":base_hp,"credits_start":credits,
		"spent_start":total_spent,"enemy_hp":0.0,"composition":{},"damage_by_tower_class":{},"damage_by_enemy_type":{},"death_fractions":[],
		"bosses":[],"boss_exit_hp":0.0,"ttk_sum":0.0,"spawned_children":0}
	spawn_interval=Balance.cfg.spawn_interval/wave_rules.pressure
	spawn_queue=WaveCatalog.queue(wave_config)
	diagnostics.emit("wave_start",time,{"wave":next_wave,"config":wave_config,"credits":credits},true)
	return true

func spawn_enemy(kind: String, wave: int = -1) -> Dictionary:
	var w:=next_wave if wave<0 else wave
	var config:=WaveCatalog.generate(w)
	var boss_data:=Balance.boss(w) if kind=="boss" else {}
	var data: Dictionary=Balance.cfg.enemies.normal if kind=="boss" else Balance.cfg.enemies[kind]
	var modifiers: Dictionary=wave_rules if active else rules
	var hp: float=maxf(1,WaveCatalog.rounded(config.hp[kind]*modifiers.hp))
	var e:={"id":next_id,"kind":kind,"wave":w,"hp":hp,"max_hp":hp,"speed":float(Balance.cfg.boss_speed if kind=="boss" else data.speed)*Balance.cfg.base_enemy_speed,
		"hp_scale":modifiers.hp,"money_scale":modifiers.money,"reward":maxi(1,WaveCatalog.rounded(config.reward[kind]*modifiers.money)),"cell":map.spawn,"next":map.next_cell(map.spawn),"progress":0.0,"trail":[map.spawn],
		"pos":HexMap.point(map.spawn),"previous_pos":HexMap.point(map.spawn),"dead":false,"immune":boss_data.get("immune",""),"color":boss_data.get("color",data.color),
		"pushes":[],"last_hit":-100.0,"spawned_at":time,"damage_sources":{},"hits":0,"parent_id":-1,"reward_paid":false}
	next_id+=1
	enemies.append(e)
	add_effect("spawn",e.pos,e.pos,Color(e.color),.24,.22)
	register_spawn(e)
	return e

func hit(e: Dictionary, amount: float, t: Dictionary, ultimate_effect: bool = false) -> bool:
	if e.dead: return false
	ensure_tower_stats(t)
	t.attempted+=amount
	if not t.job.is_empty():
		diagnostics.issue("DAMAGE_DURING_INSTALL",time,{"tower_id":t.id,"enemy_id":e.id,"job":t.job})
		return false
	if e.immune==t.kind:
		diagnostics.emit("immune_block",time,{"tower_id":t.id,"enemy_id":e.id,"attempted":amount})
		return false
	var actual:=minf(amount,e.hp)
	var excess:=maxf(0,amount-e.hp)
	e.hp=maxf(0,e.hp-amount)
	e.last_hit=time
	e.hits=int(e.get("hits",0))+1
	if not e.has("damage_sources"): e.damage_sources={}
	e.damage_sources[t.kind]=float(e.damage_sources.get(t.kind,0))+actual
	t.damage+=actual; t.overkill+=excess; t.hits+=1
	if e.kind=="boss": t.boss_damage+=actual
	total_damage+=actual
	if not wave_stats.is_empty():
		wave_stats.damage+=actual
		for pair in [["damage_by_tower_class",t.kind],["damage_by_enemy_type",e.kind]]:
			if not wave_stats.has(pair[0]):wave_stats[pair[0]]={}
			wave_stats[pair[0]][pair[1]]=float(wave_stats[pair[0]].get(pair[1],0))+actual
	if ultimate_effect:t.ultimate_hits+=1
	diagnostics.emit("damage_applied",time,{"tower_id":t.id,"enemy_id":e.id,"type":e.kind,"attempted":amount,"effective":actual,"overkill":excess,"hp":e.hp})
	add_effect("hit",e.pos,e.pos,Color(e.color),.13,.10)
	if e.hp<=0: kill(e,t)
	return true

func kill(e: Dictionary, t: Dictionary) -> void:
	if e.dead: return
	e.dead=true
	t.kills+=1; total_kills+=1
	var fraction:=path_fraction(e)
	if e.kind!="boss" and not wave_stats.is_empty():
		wave_stats.ordinary_killed=int(wave_stats.get("ordinary_killed",0))+1
		if fraction<.15:wave_stats.early_ordinary_killed=int(wave_stats.get("early_ordinary_killed",0))+1
	if not wave_stats.is_empty():
		wave_stats.killed+=1
		if not wave_stats.has("death_fractions"):wave_stats.death_fractions=[]
		wave_stats.death_fractions.append(fraction)
		wave_stats.ttk_sum=float(wave_stats.get("ttk_sum",0))+time-float(e.spawned_at)
	if e.kind=="boss": register_boss(e,false)
	diagnostics.emit("enemy_death",time,{"id":e.id,"tower_id":t.id,"type":e.kind,"wave":e.get("wave",next_wave),"path_fraction":fraction,"ttk":time-e.spawned_at,"pos":e.pos,"damage_sources":e.get("damage_sources",{})},e.kind=="boss")
	add_effect("death",e.pos,e.pos,Color(e.color),.42,.35)
	if e.get("reward_paid",false): diagnostics.issue("DOUBLE_DEATH_REWARD",time,{"enemy_id":e.id})
	else:
		e.reward_paid=true; credits+=e.reward; total_earned+=e.reward
		if not wave_stats.is_empty():wave_stats.earned+=e.reward
	if e.kind=="split":
		var config:=WaveCatalog.generate(int(e.get("wave",next_wave)))
		var children: Array=[]
		for i in 2:
			var child: Dictionary=e.duplicate(true)
			child.id=next_id; next_id+=1
			child.kind="child"; child.dead=false; child.reward_paid=false
			child.max_hp=maxf(1,WaveCatalog.rounded(config.hp.child*float(e.get("hp_scale",1.0)))); child.hp=child.max_hp; child.reward=maxi(1,WaveCatalog.rounded(config.reward.child*float(e.get("money_scale",1.0))))
			child.speed=Balance.cfg.enemies.child.speed*Balance.cfg.base_enemy_speed
			child.pushes=[];child.last_hit=-100.0;child.spawned_at=time;child.damage_sources={};child.hits=0;child.parent_id=e.id
			child.progress=maxf(0,e.progress-i*.09)
			child.pos=HexMap.point(child.cell).lerp(HexMap.point(child.next),child.progress);child.previous_pos=child.pos
			enemies.append(child);children.append(child.id);register_spawn(child)
			if not wave_stats.is_empty():wave_stats.spawned_children=int(wave_stats.get("spawned_children",0))+1
		diagnostics.emit("enemy_split",time,{"parent_id":e.id,"children":children},true)

func add_effect(type: String, a: Vector2, b: Vector2, color: Color, radius: float = 0, duration: float = .2) -> void:
	if visuals:
		if effects.size() >= int(Balance.cfg.max_effects):
			effects.pop_front()
		effects.append({"type":type,"a":a,"b":b,"color":color,"radius":radius,"life":duration,"duration":duration})

func step(delta: float) -> void:
	if defeated:
		return
	time += delta
	diagnostics.tick(self,delta)
	update_jobs(delta)
	for i in range(effects.size()-1,-1,-1):
		effects[i].life -= delta
		if effects[i].life <= 0:
			effects.remove_at(i)
	if not active:
		return
	wave_time += delta
	spawn_timer -= delta
	if spawn_timer <= .000001 and not spawn_queue.is_empty():
		var clear := true
		for e in enemies:
			if not e.dead and e.pos.distance_to(HexMap.point(map.spawn)) < Balance.cfg.spawn_clearance:
				clear = false
				break
		if clear:
			spawn_enemy(spawn_queue.pop_front())
			spawn_timer = spawn_interval
	for e in enemies:
		if not e.dead:
			if e.kind=="boss":
				var eligible:=0.0
				for t in towers:
					if t.job.is_empty() and t.kind!=e.immune and HexMap.point(t.cell).distance_to(e.pos)<=Balance.reach(t):
						eligible+=Balance.damage(t)*Balance.rate(t)*Balance.volley(t)
				if eligible>0:
					e.eligible_seconds=float(e.get("eligible_seconds",0))+delta
					e.eligible_damage_integral=float(e.get("eligible_damage_integral",0))+eligible*delta
			move_enemy(e,delta)
		if base_hp <= 0:
			base_hp = 0
			defeated = true
			active = false
			diagnostics.emit("match_end",time,{"wave":next_wave,"defeated":true},true)
			diagnostics.write_summary(self)
			return
	Combat.step(self,delta)
	for i in range(enemies.size()-1,-1,-1):
		if enemies[i].dead:
			enemies.remove_at(i)
	if spawn_queue.is_empty() and enemies.is_empty():
		complete_wave()

func snapshot(include_wave: bool = false) -> Dictionary:
	return StateCodec.capture(self,include_wave)

func restore(data: Dictionary) -> bool:
	return StateCodec.restore(self,data)

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

func push_back(e: Dictionary, t: Dictionary, amount: float) -> float:
	if e.dead or e.immune == t.kind or not t.job.is_empty():
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

func move_enemy(e: Dictionary, delta: float) -> void:
	e.previous_pos = e.pos
	var travel: float = e.speed * delta
	while travel > 0.000001 and not e.dead:
		if e.cell == map.goal:
			e.dead = true
			base_hp -= 1
			diagnostics.emit("enemy_leak",time,{"id":e.id,"type":e.kind,"wave":e.get("wave",next_wave),"remaining_hp":e.hp,"max_hp":e.max_hp,"damage_sources":e.get("damage_sources",{})},true)
			if e.kind=="boss":register_boss(e,true)
			if not wave_stats.is_empty():
				wave_stats.leaked += 1
			break
		if e.progress <= 0.000001:
			e.next = map.next_cell(e.cell)
		if e.next == e.cell:
			diagnostics.issue("PATH_INVARIANT",time,{"enemy_id":e.id,"cell":e.cell},get_stack())
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

func complete_wave() -> void:
	if not active or wave_reward_paid or defeated:return
	wave_reward_paid=true
	var bonus:=int(WaveCatalog.generate(next_wave).completion_bonus)
	credits+=bonus;total_earned+=bonus;wave_stats.earned+=bonus
	wave_stats.seconds=wave_time;wave_stats.hp_end=base_hp;wave_stats.credits_end=credits
	wave_stats.spent=total_spent-wave_stats.spent_start
	wave_stats.path_length=map.route(map.spawn).size()
	var fractions: Array=wave_stats.get("death_fractions",[])
	fractions.sort()
	wave_stats.median_death_fraction=fractions[fractions.size()/2] if not fractions.is_empty() else 0
	wave_stats.average_ttk=float(wave_stats.get("ttk_sum",0))/maxi(1,wave_stats.killed)
	wave_stats.effective_dps=wave_stats.damage/maxf(.001,wave_time)
	wave_stats.mean_fps=diagnostics.fps_sum/maxi(1,diagnostics.frames)
	audit_wave()
	wave_stats.erase("death_fractions")
	history.append(wave_stats.duplicate(true))
	diagnostics.emit("wave_end",time,wave_stats,true)
	next_wave+=1;active=false;finished_event=true;projectiles.clear()
	for t in towers:t.cd=0
	diagnostics.write_summary(self)


func ensure_tower_stats(t: Dictionary) -> void:
	for key in ["shots","hits","misses","attempted","overkill","boss_damage","expected_attacks","ready_idle"]:
		if not t.has(key):t[key]=0.0
	if not t.has("last_shot"):t.last_shot=-100.0
	if not t.has("idle_seconds"):t.idle_seconds={}

func register_spawn(e: Dictionary) -> void:
	if not wave_stats.is_empty():
		wave_stats.spawned+=1;wave_stats.enemy_hp+=e.hp
		wave_stats.composition[e.kind]=int(wave_stats.composition.get(e.kind,0))+1
	diagnostics.emit("enemy_spawn",time,{"id":e.id,"type":e.kind,"wave":e.get("wave",next_wave),"hp":e.hp,"speed":e.speed,"reward":e.reward,"immune":e.immune,"pos":e.pos,"parent_id":e.get("parent_id",-1)},e.kind=="boss")

func path_fraction(e: Dictionary) -> float:
	var traveled:=maxf(0,e.trail.size()-1+float(e.progress))
	var remaining:=maxf(0,float(map.distances.get(e.cell,0))-float(e.progress))
	return clampf(traveled/maxf(1,traveled+remaining),0,1)

func register_boss(e: Dictionary, leaked: bool) -> void:
	if wave_stats.is_empty():return
	if not wave_stats.has("bosses"):wave_stats.bosses=[]
	var record:={"id":e.id,"hp_start":e.max_hp,"remaining_hp":e.hp,"immune":e.immune,"leaked":leaked,"time_alive":time-e.spawned_at,"time_under_attack":e.get("eligible_seconds",0),"mean_eligible_raw_dps":float(e.get("eligible_damage_integral",0))/maxf(.001,float(e.get("eligible_seconds",0))),
		"path_fraction":path_fraction(e),"remaining_cells":map.distances.get(e.cell,0),"damage_sources":e.get("damage_sources",{})}
	wave_stats.bosses.append(record)
	if leaked:wave_stats.boss_exit_hp=float(wave_stats.get("boss_exit_hp",0))+e.hp

func audit_wave() -> void:
	wave_stats.early_death_fraction=float(wave_stats.get("early_ordinary_killed",0))/maxi(1,int(wave_stats.get("ordinary_killed",0)))
	wave_stats.warnings=[]
	var early_streak:=1 if wave_stats.early_death_fraction>.8 else 0
	for index in range(history.size()-1,maxi(-1,history.size()-5),-1):
		if float(history[index].get("early_death_fraction",0))>.8:early_streak+=1
		else:break
	if early_streak>=5:
		wave_stats.warnings.append("EARLY_KILLS_5_WAVES")
		diagnostics.issue("EARLY_KILLS_5_WAVES",time,{"wave":next_wave,"fraction":wave_stats.early_death_fraction})
	if next_wave%5==0:
		var records: Array=wave_stats.get("bosses",[]).duplicate()
		for index in range(history.size()-1,-1,-1):
			if int(history[index].wave)%5==0:
				records.append_array(history[index].get("bosses",[]))
				if records.size()>=3:break
		if records.size()>=3:
			var large_leaks:=true
			for record in records.slice(0,3):
				if not record.leaked or float(record.remaining_hp)/maxf(1,record.hp_start)<=.2:large_leaks=false
			if large_leaks:
				wave_stats.warnings.append("BOSS_LEAK_3_TIMES")
				diagnostics.issue("BOSS_LEAK_3_TIMES",time,{"wave":next_wave})
