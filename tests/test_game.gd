extends SceneTree

var failures: Array = []
var checks := 0

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("FAIL: ",message)

func fresh() -> Simulation:
	var s := Simulation.new(1234)
	s.visuals = false
	s.credits = 1000000
	return s

func advance(s: Simulation, seconds: float) -> void:
	for i in int(round(seconds/.025)):
		s.step(.025)

func tower(s: Simulation, kind: String, cell := Vector2i(-1,2)) -> Dictionary:
	expect(s.build(cell,kind).is_empty(),"Build "+kind)
	return s.tower_at(cell)

func enemy(s: Simulation, pos: Vector2, hp: float = 10000) -> Dictionary:
	var e := s.spawn_enemy("normal")
	e.pos = pos
	e.previous_pos = pos
	e.hp = hp
	e.max_hp = hp
	e.speed = 0
	return e

func _init() -> void:
	call_deferred("run")

func equivalent(a, b) -> bool:
	if (a is float or a is int) and (b is float or b is int):
		return absf(float(a)-float(b)) < .0000001
	if a is Array and b is Array:
		if a.size()!=b.size(): return false
		for i in a.size():
			if not equivalent(a[i],b[i]): return false
		return true
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size(): return false
		for k in a:
			if not b.has(k) or not equivalent(a[k],b[k]): return false
		return true
	return a==b

func run() -> void:
	Balance.load_config()
	var s := fresh()
	expect(s.map.cells.size() == 70,"Map has 70 approved cells")
	expect(s.map.route(s.map.spawn).size() == 33,"Map baseline path 32 edges")
	var credits := s.credits
	expect(not s.build(Vector2i(0,1),"Minigun").is_empty(),"Last corridor cannot close")
	expect(s.credits == credits,"Failed build is free")
	var t := tower(s,"Minigun")
	expect(t.level == 1,"New tower level 1")
	for level in range(2,11):
		var before: int = s.credits
		expect(s.upgrade(t.id).is_empty(),"Upgrade accepted "+str(level))
		expect(t.level == level-1 and t.job == "upgrade","No instant model/stat change")
		expect(not s.upgrade(t.id).is_empty(),"Double upgrade rejected")
		expect(s.credits == before-Balance.upgrade_cost(t.kind,level),"Exactly one payment")
		advance(s,2.975)
		expect(t.level == level-1,"Upgrade remains pending before 3 seconds")
		advance(s,.025)
		expect(t.level == level and t.job.is_empty(),"Upgrade ends exactly 3 seconds between waves")
	expect(not s.upgrade(t.id).is_empty(),"Cannot exceed level 10")
	expect(s.buy_ultimate(t.id).is_empty(),"Level 10 ultimate purchase")
	expect(not t.ultimate,"Ultimate not instant")
	advance(s,3)
	expect(t.ultimate,"Ultimate installed after 3 seconds")
	for kind in Balance.KINDS:
		for level in range(3,11):
			expect(Balance.upgrade_cost(kind,level)>Balance.upgrade_cost(kind,level-1),"Increasing upgrade cost")
		var a := {"kind":kind,"level":1,"ultimate":false,"mega":false}
		var b := a.duplicate(); b.level = 10
		expect(Balance.damage(b)>Balance.damage(a),"Level damage growth "+kind)
		if kind != "Minigun":
			expect(is_equal_approx(Balance.rate(a),Balance.rate(b)),"Fixed frequency "+kind)
		if kind == "Laser":
			expect(is_equal_approx(Balance.reach(a),Balance.reach(b)),"Laser ordinary range fixed")
			b.ultimate = true
			expect(is_equal_approx(Balance.reach(b),2*Balance.reach(a)),"Laser ultimate exactly doubles range")
		if kind == "Rocket":
			expect(Balance.volley(a)==1 and Balance.volley(b)==10,"Rocket volley 1 to 10")
	# Merge timing, cancellation, money and round trip in progress.
	s = fresh()
	var a := tower(s,"Minigun",Vector2i(-1,10))
	var partner := Vector2i(999,999)
	for direction in HexMap.DIRS:
		if s.map.validate_build(a.cell+direction,[]).is_empty():
			partner=a.cell+direction
			break
	var b := tower(s,"Minigun",partner)
	for current in [a,b]:
		current.level = 10; current.ultimate = true; current.invested = 250
	var base_dps := Balance.damage(a)*Balance.rate(a)
	expect(s.merge(a.id,b.id).is_empty(),"Adjacent max towers start merge")
	advance(s,2)
	var restored := fresh()
	expect(restored.restore(JSON.parse_string(JSON.stringify(s.snapshot(true)))),"Pending merge survives JSON save")
	expect(restored.towers.size()==2 and restored.merges.size()==1,"No early merge/duplicate on load")
	advance(restored,2.975)
	expect(restored.towers.size()==2,"Merge pending at 4.975 seconds")
	advance(restored,.025)
	expect(restored.towers.size()==1 and restored.towers[0].mega,"Mega created exactly at 5 seconds")
	var mega: Dictionary = restored.towers[0]
	expect(is_equal_approx(Balance.damage(mega)*Balance.rate(mega),base_dps*2),"Mega base DPS is sum of two towers")
	expect(mega.cell==a.cell and not restored.map.occupied.has(b.cell),"First cell retained, second free")
	expect(mega.invested==500 and restored.sell(mega.id)==350,"Mega refunds 70 percent of both investments")
	s.cancel_merge(a.id)
	expect(s.merges.is_empty() and a.job.is_empty() and b.job.is_empty(),"Cancel resumes both towers")
	s.merge(a.id,b.id)
	var before := s.credits
	expect(s.sell(a.id)==175 and s.credits==before+175,"Sale during merge single refund")
	expect(s.towers.size()==1 and s.merges.is_empty() and b.job.is_empty(),"Sale cancels peer merge")
	advance(s,6)
	expect(s.towers.size()==1 and not b.mega,"Cancelled merge cannot finish later")
	# Laser hits every intersected enemy, including beyond detection, but not off-line.
	s = fresh(); t = tower(s,"Laser")
	var origin := HexMap.point(t.cell)
	var e1 := enemy(s,origin+Vector2(1,0))
	var e2 := enemy(s,origin+Vector2(5,0))
	var off := enemy(s,origin+Vector2(2,1))
	Combat.laser(s,t,e1)
	expect(e1.hp==10000-Balance.damage(t) and e2.hp==10000-Balance.damage(t),"Laser pierces to edge beyond detection")
	expect(off.hp==10000,"Laser does not hit off-line enemy")
	expect(Combat.ray_end(origin,Vector2.RIGHT).x>e2.pos.x,"Beam endpoint reaches edge")
	# Ricochet exactly one extra target at 70 percent, no cascade.
	s = fresh(); t = tower(s,"Minigun"); t.level=10; t.ultimate=true
	origin = HexMap.point(t.cell)
	e1=enemy(s,origin+Vector2(.5,0)); e2=enemy(s,origin+Vector2(1,0)); off=enemy(s,origin+Vector2(2,0))
	Combat.bullet(s,t,origin,e1,100,false)
	for i in 80:
		for p in s.projectiles.duplicate():
			if not Combat.update_projectile(s,p,.025): s.projectiles.erase(p)
	expect(is_equal_approx(e1.hp,9900) and is_equal_approx(e2.hp,9930),"Ricochet primary 100, one secondary 70")
	expect(off.hp==10000 and s.projectiles.is_empty(),"Ricochet no third target")
	# Ordinary classes have no class resistance; boss has exactly one immunity.
	for kind in Balance.KINDS:
		s=fresh(); t=tower(s,kind)
		for type in Balance.cfg.enemies:
			var e:=s.spawn_enemy(type)
			e.hp=10000
			expect(s.hit(e,10,t) and e.hp==9990,"Ordinary full damage "+kind+"/"+type)
	for wave in [5,10,15,20,25]:
		for kind in Balance.KINDS:
			s=fresh(); t=tower(s,kind)
			var boss:=s.spawn_enemy("boss",wave)
			boss.hp=10000
			var hit:=s.hit(boss,10,t)
			expect(hit==(kind!=Balance.boss(wave).immune),"Boss immunity cycle")
	# Wavefront timing, exact maximum, one hit; immunity blocks reverse push too.
	s=fresh(); t=tower(s,"Shockwave")
	origin=HexMap.point(t.cell)
	e1=enemy(s,origin+Vector2(.9,0)); e2=enemy(s,origin+Vector2(Balance.reach(t)+.001,0))
	Combat.shoot(s,t,e1)
	var wave: Dictionary=s.projectiles[0]
	Combat.update_projectile(s,wave,.1)
	expect(e1.hp==10000,"Wave does not damage before front arrives")
	Combat.update_projectile(s,wave,.15)
	expect(e1.hp==10000-Balance.damage(t),"Wave damage when front reaches enemy")
	Combat.update_projectile(s,wave,.2)
	expect(e1.hp==10000-Balance.damage(t) and e2.hp==10000,"Wave hits once, never outside max radius")
	s=fresh(); t=tower(s,"Shockwave"); t.level=10; t.ultimate=true
	e1=s.spawn_enemy("normal"); var immune:=s.spawn_enemy("boss",20)
	for current in [e1,immune]:
		current.cell=Vector2i(0,2); current.next=Vector2i(0,3); current.progress=.5
		current.pos=HexMap.point(current.cell).lerp(HexMap.point(current.next),.5)
		current.previous_pos=current.pos; current.trail=[Vector2i(0,0),Vector2i(0,1),Vector2i(0,2)]
		current.hp=10000; current.speed=1
	Combat.shoot(s,t,e1)
	var reverse: Dictionary=s.projectiles[-1]
	Combat.update_projectile(s,reverse,.35)
	expect(e1.progress<.5 and immune.progress==.5 and immune.hp==10000,"Reverse pushes ordinary target, boss immunity blocks damage and push")
	expect(e1.progress>=.5-float(Balance.cfg.shock_push)-.000001,"Reverse push distance bounded")
	Combat.shoot(s,t,e1)
	expect(not s.projectiles[-1].reverse,"Reverse does not fire on every shockwave")
	# Rocket genuinely curves, retargets dead target, expires without enemies.
	s=fresh(); t=tower(s,"Rocket")
	origin=HexMap.point(t.cell)
	e1=enemy(s,origin+Vector2(2,0)); e2=enemy(s,origin+Vector2(3,0))
	Combat.rocket(s,t,origin,e1,10,false,.9)
	var rocket: Dictionary=s.projectiles[0]
	Combat.update_projectile(s,rocket,.025)
	expect(absf(rocket.pos.y-origin.y)>.01,"Rocket curved initial departure")
	e1.dead=true
	Combat.update_projectile(s,rocket,.025)
	expect(rocket.target==e2.id,"Rocket retargets nearest live enemy")
	e2.dead=true
	expect(not Combat.update_projectile(s,rocket,.025),"Rocket ends safely without target")
	s=fresh(); t=tower(s,"Rocket"); t.level=10; t.ultimate=true
	origin=HexMap.point(t.cell); e1=enemy(s,origin+Vector2(1,0))
	Combat.explode(s,e1.pos,t,10,false)
	expect(s.projectiles.size()==Balance.cfg.mini_count,"Cluster creates configured mini rockets")
	var count:=s.projectiles.size()
	Combat.explode(s,e1.pos,t,2,true)
	expect(s.projectiles.size()==count,"Mini rockets do not recursively split")
	# Installation blocks all owned attacks/projectiles; separate jobs run concurrently.
	s=fresh(); t=tower(s,"Minigun"); b=tower(s,"Laser",Vector2i(4,-1))
	e1=enemy(s,HexMap.point(t.cell)+Vector2(1,0))
	Combat.shoot(s,t,e1)
	s.upgrade(t.id); s.upgrade(b.id)
	expect(s.projectiles.is_empty() and not s.hit(e1,100,t),"Installing tower cannot inflict damage")
	advance(s,3)
	expect(t.level==2 and b.level==2,"Independent simultaneous upgrades")
	# HP visibility uses last hit and game time.
	var board:=GameBoard.new(); board.sim=s
	expect(not board.hp_visible(e1),"HP hidden before first hit")
	s.hit(e1,1,t)
	expect(board.hp_visible(e1),"HP visible immediately after hit")
	advance(s,.75); s.hit(e1,1,t); advance(s,.75)
	expect(board.hp_visible(e1),"Second hit restarts HP timer")
	advance(s,.275)
	expect(not board.hp_visible(e1),"HP hides one game second after last hit")
	board.free()
	# Homogeneous waves and periodic mixed waves.
	for number in range(1,61):
		s=fresh(); s.next_wave=number; s.start_wave()
		var types: Dictionary={}
		for kind in s.spawn_queue:
			if kind!="boss": types[kind]=true
		expect(types.size()>1 if number%20==19 else types.size()==1,"Wave composition "+str(number))
		expect(s.spawn_queue.has("boss")== (number%5==0),"Boss every five waves")
	s=fresh(); s.start_wave()
	var times: Array=[]
	while times.size()<5:
		s.step(.025)
		for e in s.enemies:
			if not times.has(e.spawned_at): times.append(e.spawned_at)
	for i in range(1,times.size()):
		expect(absf(times[i]-times[i-1]-Balance.cfg.spawn_interval)<.025001,"Uniform spawn cadence")
	# Active session round trip, job state, legacy migration, checkpoint backup.
	s=fresh(); t=tower(s,"Minigun"); s.upgrade(t.id); s.start_wave(); advance(s,1)
	var raw: Dictionary=JSON.parse_string(JSON.stringify(s.snapshot(true)))
	restored=fresh()
	expect(restored.restore(raw),"Active wave session restores")
	expect(restored.active and restored.enemies.size()==s.enemies.size() and restored.spawn_queue==s.spawn_queue,"Wave progress retained")
	expect(is_equal_approx(restored.towers[0].job_left,t.job_left),"Remaining install duration retained")
	advance(s,1); advance(restored,1)
	var original_after: Dictionary = JSON.parse_string(JSON.stringify(s.snapshot(true)))
	var restored_after: Dictionary = JSON.parse_string(JSON.stringify(restored.snapshot(true)))
	expect(equivalent(original_after,restored_after),"Restored simulation continues deterministically within float precision")
	var old:=s.snapshot(); old.schema=2
	old.towers=[{"id":1,"cell":[-1,2],"kind":"Minigun","d":5,"s":5,"ultimate":false,"mega":false,"invested":123,"damage":5.0,"kills":1}]
	old.tower_history=[]; old.next_id=2; old.credits=789
	expect(restored.restore(old) and restored.credits==789 and restored.towers[0].invested==123,"Legacy save retains money/investment")
	expect(restored.towers[0].level==6,"Legacy branches migrate to single level")
	var malformed:=checkpoint_copy(old)
	malformed.towers[0].cell=[1]
	expect(not restored.restore(malformed),"Malformed legacy coordinates rejected without crash")
	malformed=checkpoint_copy(raw); malformed.towers[0].cell={"$i":[1]}
	expect(not restored.restore(malformed),"Malformed vector payload rejected without crash")
	SaveStore.directory="user://revision_tests_"+str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(SaveStore.directory)
	expect(not SaveStore.save_slot(1,raw).is_empty(),"Partial wave rejected as successful checkpoint")
	var checkpoint:=restored.snapshot()
	expect(SaveStore.save_slot(1,checkpoint).is_empty(),"Checkpoint saves with checksum")
	SaveStore.save_slot(1,checkpoint)
	var file:=FileAccess.open(SaveStore.path(1),FileAccess.WRITE); file.store_string("broken"); file.close()
	expect(not SaveStore.load_slot(1).is_empty(),"Corrupt primary falls back to valid backup")
	expect(SaveStore.save_session(1,raw).is_empty() and not SaveStore.load_session(1).is_empty(),"Separate active session file")
	SaveStore.clear_session(1)
	expect(SaveStore.load_session(1).is_empty() and not SaveStore.load_slot(1).is_empty(),"Defeat clears session, keeps successful checkpoint")
	var report:={"checks":checks,"failures":failures}
	var output:=FileAccess.open("res://tests/revision-unit-results.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"  ")); output.close()
	print("REVISION UNIT: ",checks," checks; ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)

func checkpoint_copy(value: Dictionary) -> Dictionary:
	return value.duplicate(true)
