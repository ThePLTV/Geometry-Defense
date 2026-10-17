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

func full(s: Simulation, cell: Vector2i, kind: String) -> Dictionary:
	expect(s.build(cell,kind) == "","Build full tower")
	var t := s.tower_at(cell)
	for i in range(10):
		expect(s.upgrade(t.id,"d") == "","Upgrade damage")
		expect(s.upgrade(t.id,"s") == "","Upgrade rate")
	expect(s.buy_ultimate(t.id) == "","Buy ultimate")
	return t

func stationary(s: Simulation, cell: Vector2i, hp: float = 100000.0) -> Dictionary:
	var e := s.spawn_enemy("normal")
	e.cell = cell
	e.next = s.map.next_cell(cell)
	e.progress = 0.0
	e.pos = HexMap.point(cell)
	e.trail = [s.map.spawn,cell] if cell != s.map.spawn else [cell]
	e.hp = hp
	e.max_hp = hp
	e.speed = 0.0
	return e

func _init() -> void:
	call_deferred("run")

func run() -> void:
	Balance.load_config()
	var s := fresh()
	expect(s.map.cells.size() == 70,"Exact digitized traversable count")
	var route := s.map.route(s.map.spawn)
	expect(route.size() == 33,"Baseline shortest route is 32 edges")
	for i in range(route.size()-1):
		expect(HexMap.DIRS.has(route[i+1]-route[i]),"Route uses one of six neighbours")
	var before := s.credits
	expect(s.build(Vector2i(0,1),"Minigun") == "Нельзя перекрыть путь","Last corridor denied")
	expect(s.credits == before and s.towers.is_empty(),"Denied placement is free")
	for cell in [Vector2i(2,0),s.map.spawn,s.map.goal]:
		expect(not s.build(cell,"Minigun").is_empty(),"Blocked/spawn/goal cannot build")
	var lengthened := false
	for cell in s.map.cells:
		var f := s.map.field(cell)
		if f.has(s.map.spawn) and int(f[s.map.spawn]) > route.size()-1:
			expect(s.build(cell,"Minigun") == "","Path detour accepted")
			expect(s.map.route(s.map.spawn).size() > route.size(),"BFS reroutes around tower")
			s.sell(s.towers[0].id)
			expect(s.map.route(s.map.spawn).size() == route.size(),"Sale immediately restores route")
			lengthened = true
			break
	expect(lengthened,"Map contains a valid alternative path")
	var enemy := s.spawn_enemy("normal")
	enemy.cell = Vector2i(0,2)
	enemy.next = Vector2i(0,3)
	enemy.progress = 0.3
	expect(s.build(enemy.cell,"Minigun") == "Клетка занята врагом","Current segment cell protected")
	expect(s.build(enemy.next,"Minigun") == "Клетка занята врагом","Next segment cell protected")
	enemy.cell = Vector2i(8,-4)
	enemy.next = Vector2i(8,-3)
	enemy.progress = 0.0
	expect(s.build(Vector2i(8,-3),"Minigun") == "Нельзя отрезать врагов","Already spawned enemy cannot be isolated")
	enemy.cell = s.map.spawn
	enemy.next = s.map.next_cell(enemy.cell)
	enemy.progress = .5
	enemy.pos = HexMap.point(enemy.cell).lerp(HexMap.point(enemy.next),.5)
	var position: Vector2 = enemy.pos
	expect(s.build(Vector2i(-1,2),"Minigun") == "","Build during segment")
	s.move_enemy(enemy,.05)
	expect(position.distance_to(enemy.pos) <= .050001,"No teleport after reroute")

	for wave in [5,10,15,20,25,30]:
		var boss_data := Balance.boss(wave)
		var expected: String = ["Laser","Minigun","Rocket","Shockwave"][(int(wave/5.0)-1)%4]
		expect(boss_data.immune == expected,"Boss cycle at wave %d"%wave)
		for kind in Balance.KINDS:
			var combat := fresh()
			combat.build(Vector2i(-1,2),kind)
			var tower: Dictionary = combat.towers[0]
			tower.ultimate = true
			tower.mega = true
			var boss := combat.spawn_enemy("boss",wave)
			var original_hp: float = boss.hp
			var did_hit := combat.hit(boss,10,tower,true)
			expect(did_hit == (kind != expected),"Immune class, including mega ultimate")
			expect(is_equal_approx(original_hp-boss.hp,0.0 if kind == expected else 10.0),"Boss damage value")
			if kind == expected:
				expect(combat.push_back(boss,tower,.42) == 0,"Immune control is zero")

	var economy := fresh()
	var a := full(economy,Vector2i(-1,10),"Minigun")
	var b := full(economy,Vector2i(-1,11),"Minigun")
	var original_cell: Vector2i = a.cell
	var other_cell: Vector2i = b.cell
	var investment: int = a.invested+b.invested
	var original_dps := Balance.damage(a)*Balance.rate(a)
	var old_revision := economy.map.revision
	expect(economy.merge(a.id,b.id) == "","Same-class adjacent 10/10 towers merge")
	var mega: Dictionary = economy.towers[0]
	expect(mega.cell == original_cell and not economy.map.occupied.has(other_cell),"Mega stays on first cell and frees second")
	expect(mega.d == 10 and mega.s == 10 and mega.mega and mega.ultimate,"Mega levels and ultimate")
	expect(is_equal_approx(Balance.damage(mega)*Balance.rate(mega),original_dps*2),"Mega sums DPS, never multiplies it by four")
	expect(mega.invested == investment,"Mega investment sum")
	expect(economy.tower_history.size() == 3,"Source identities retained")
	expect(economy.map.revision > old_revision,"Merge rebuilds reachability")
	expect(economy.sell(mega.id) == int(floor(investment*.7)),"Mega sale returns 70% of both investments")
	var upgraded := fresh()
	upgraded.build(Vector2i(-1,2),"Minigun")
	var tower: Dictionary = upgraded.towers[0]
	old_revision = upgraded.map.revision
	upgraded.upgrade(tower.id,"d")
	expect(upgraded.map.revision == old_revision,"Upgrades do not rebuild path")
	expect(not upgraded.buy_ultimate(tower.id).is_empty(),"Ultimate requires both branches >=5")

	var laser := fresh()
	laser.build(Vector2i(-1,2),"Laser")
	tower = laser.towers[0]
	tower.ultimate = true
	var e1 := stationary(laser,Vector2i(0,0),1000)
	var e2 := stationary(laser,Vector2i(0,1),1000)
	var e3 := stationary(laser,Vector2i(0,2),1000)
	laser.shoot(tower,e1)
	expect(is_equal_approx(1000-e1.hp,45),"Laser primary damage")
	expect(is_equal_approx(1000-e2.hp,45*.65),"First sequential bounce")
	expect(is_equal_approx(1000-e3.hp,45*.65*.65),"Second sequential bounce")
	var hp2: float = e2.hp
	e1.immune = "Laser"
	laser.shoot(tower,e1)
	expect(is_equal_approx(e2.hp,hp2),"Immune laser target stops ricochets")
	expect(laser.nearest(e1.pos,1).id == e1.id,"Nearest selection is geometric")
	e1.dead = true
	expect(laser.nearest(e2.pos,2).id == e2.id,"Dead target retargets nearest")

	var rocket := fresh()
	rocket.build(Vector2i(-1,2),"Rocket")
	tower = rocket.towers[0]
	tower.ultimate = true
	e1 = stationary(rocket,Vector2i(0,0))
	rocket.explode(e1.pos,tower,68,false)
	expect(rocket.projectiles.size() == 3,"Each normal rocket creates three mini missiles")
	tower.mega = true
	rocket.projectiles.clear()
	rocket.explode(e1.pos,tower,68,false)
	expect(rocket.projectiles.size() == 5,"Mega rocket creates five mini missiles")
	rocket.projectiles.clear()
	rocket.explode(e1.pos,tower,17,true)
	expect(rocket.projectiles.is_empty(),"Mini missiles do not recurse")
	e1.immune = "Rocket"
	var previous_hp: float = e1.hp
	rocket.explode(e1.pos,tower,999,true)
	expect(e1.hp == previous_hp,"Mini missile respects boss immunity")

	var splitter := fresh()
	splitter.build(Vector2i(-1,2),"Minigun")
	tower = splitter.towers[0]
	e1 = splitter.spawn_enemy("split",12)
	var reward: int = e1.reward
	before = splitter.credits
	splitter.hit(e1,1e9,tower)
	var children: Array = []
	for e in splitter.enemies:
		if e.kind == "child":
			children.append(e)
	expect(children.size() == 2,"Splitter creates exactly two children")
	for child in children:
		splitter.hit(child,1e9,tower)
	expect(splitter.credits-before == reward,"Split rewards do not duplicate")

	var minigun := fresh()
	minigun.build(Vector2i(-1,2),"Minigun")
	tower = minigun.towers[0]
	tower.ultimate = true
	e1 = stationary(minigun,minigun.map.spawn)
	minigun.active = true
	for i in range(130):
		minigun.step(.05)
	expect(tower.streak >= 5 and tower.ultimate_hits > 0,"Continuous fire enables Minigun overdrive")
	e1.pos = Vector2(100,100)
	e1.cell = minigun.map.goal
	e1.next = minigun.map.goal
	e1.dead = true
	minigun.spawn_queue = ["normal"]
	minigun.spawn_timer = 100
	for i in range(9):
		minigun.step(.05)
	expect(tower.streak == 0,"Target gap above .35 seconds resets overdrive")

	var shock := fresh()
	shock.build(Vector2i(-1,2),"Shockwave")
	tower = shock.towers[0]
	e1 = shock.spawn_enemy("heavy",6)
	e1.cell = Vector2i(0,2)
	e1.next = Vector2i(0,3)
	e1.progress = .8
	e1.trail = [Vector2i(0,0),Vector2i(0,1),Vector2i(0,2)]
	var total_push := 0.0
	for i in range(40):
		total_push += shock.push_back(e1,tower,.42)
	expect(total_push <= .9 and total_push <= e1.speed*.8+.000001,"Push cap also prevents indefinite heavy-enemy lock")
	var leaked := fresh()
	leaked.start_wave()
	leaked.spawn_queue.clear()
	e1 = leaked.spawn_enemy("boss",5)
	e1.cell = leaked.map.goal
	e1.next = leaked.map.goal
	leaked.step(.05)
	expect(leaked.base_hp == 9,"A boss leak costs exactly one HP")

	var save_dir := "user://test_saves_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(save_dir)
	SaveStore.directory = save_dir
	var saved := fresh()
	full(saved,Vector2i(-1,2),"Laser")
	saved.next_wave = 12
	var snapshot := saved.snapshot()
	for index in range(1,6):
		snapshot.credits = index*100
		expect(SaveStore.save_slot(index,snapshot) == "","Write independent slot %d"%index)
	for index in range(1,6):
		var loaded := SaveStore.load_slot(index)
		expect(int(loaded.credits) == index*100,"Slot independence")
	var loaded_sim := fresh()
	expect(loaded_sim.restore(SaveStore.load_slot(3)),"Load complete state")
	expect(loaded_sim.next_wave == 12 and loaded_sim.towers[0].ultimate,"Wave, upgrades, ultimate survive loading")
	expect(SaveStore.save_slot(3,snapshot) == "","Atomic replacement of an existing save")
	var corruption := FileAccess.open(SaveStore.path(3),FileAccess.WRITE)
	corruption.store_string("corrupt")
	corruption.close()
	expect(not SaveStore.load_slot(3).is_empty(),"Corrupt main file falls back to previous valid generation")
	snapshot.base_hp = 0
	expect(not SaveStore.save_slot(1,snapshot).is_empty(),"Defeat cannot overwrite checkpoint")
	expect(int(SaveStore.load_slot(1).base_hp) == 10,"Last successful checkpoint remains intact")
	SaveStore.directory = "user://"
	var monotonic := true
	for w in range(2,250):
		monotonic = monotonic and Balance.hp_multiplier(w) > Balance.hp_multiplier(w-1)
	expect(monotonic,"Enemy HP grows at all tier boundaries")
	expect(is_finite(Balance.hp_multiplier(1000000000)),"Late-wave overflow guard")
	test_live_replanning()
	var minigun_efficiency := 0.0
	var best_other_efficiency := 0.0
	for kind in Balance.KINDS:
		var investment_sum: int = int(Balance.tower(kind).price) + Balance.ultimate_cost(kind)
		for level in range(1,11):
			investment_sum += 2*Balance.upgrade_cost(kind,level)
		var specimen := {"kind":kind,"d":10,"s":10,"mega":false}
		var efficiency := Balance.damage(specimen)*Balance.rate(specimen)*(2.0 if kind == "Minigun" else 1.0)/investment_sum
		if kind == "Minigun":
			minigun_efficiency = efficiency
		else:
			best_other_efficiency = maxf(best_other_efficiency,efficiency)
	expect(minigun_efficiency > best_other_efficiency,"Late Minigun has useful single-target damage per credit")
	var undefended := Simulation.new(1)
	undefended.visuals = false
	while not undefended.defeated and undefended.next_wave <= 2:
		undefended.start_wave()
		for tick in range(3000):
			if not undefended.active:
				break
			undefended.step(.05)
	expect(undefended.defeated and undefended.next_wave == 2,"No-defense policy loses; survival is not unconditional")

	var report := {"checks":checks,"failures":failures,"passed":failures.is_empty()}
	var file := FileAccess.open("res://../game-tests.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("GAME_TESTS ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func test_live_replanning() -> void:
	var live := fresh()
	live.start_wave()
	live.spawn_queue.clear()
	var random := RandomNumberGenerator.new()
	random.seed = 879
	for i in range(12):
		var e := live.spawn_enemy("normal")
		e.hp = 100000.0
		e.max_hp = e.hp
	var candidates: Array = live.map.cells.keys()
	for tick in range(400):
		if tick%3 == 0:
			var cell: Vector2i = candidates[random.randi_range(0,candidates.size()-1)]
			var before: int = live.credits
			var result := live.build(cell,Balance.KINDS[random.randi_range(0,3)])
			if not result.is_empty():
				expect(live.credits == before,"Rejected live placement never charges")
		if tick%5 == 0 and live.towers.size() > 3:
			live.sell(live.towers[random.randi_range(0,live.towers.size()-1)].id)
		var previous: Dictionary = {}
		for e in live.enemies:
			previous[e.id] = e.pos
		live.step(.05)
		expect(live.map.distances.has(live.map.spawn),"Random live build/sale keeps spawn connected")
		for e in live.enemies:
			expect(not live.map.occupied.has(e.cell) and not live.map.occupied.has(e.next),"Live segments never enter occupied cells")
			expect(live.map.distances.has(e.next),"Every live enemy retains a path to the goal")
			expect(previous[e.id].distance_to(e.pos) <= e.speed*.05+.00001,"Repeated rerouting never teleports")
