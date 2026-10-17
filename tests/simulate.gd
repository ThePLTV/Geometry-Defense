extends SceneTree

var strategy := "mixed"
var seeds := 30
var maximum_wave := 20
var first_wave := 1
var report_path := ""

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--strategy="):
			strategy = arg.get_slice("=",1)
		elif arg.begins_with("--seeds="):
			seeds = int(arg.get_slice("=",1))
		elif arg.begins_with("--max-wave="):
			maximum_wave = int(arg.get_slice("=",1))
		elif arg.begins_with("--first-wave="):
			first_wave = int(arg.get_slice("=",1))
		elif arg.begins_with("--report="):
			report_path = arg.trim_prefix("--report=")
	call_deferred("run")

func order() -> Array:
	match strategy:
		"minigun": return ["Minigun","Minigun","Minigun","Rocket","Laser","Shockwave"]
		"area": return ["Minigun","Rocket","Shockwave","Rocket","Shockwave","Laser"]
		"laser": return ["Minigun","Laser","Laser","Rocket","Laser","Shockwave"]
	return ["Minigun","Laser","Rocket","Shockwave"]

func choose_cell(s: Simulation, kind: String) -> Vector2i:
	var best := Vector2i(999,999)
	var best_score := -1.0
	var route := s.map.route(s.map.spawn)
	for cell in s.map.cells:
		if s.map.validate_build(cell,[]) != "":
			continue
		var score := 0.0
		var point := HexMap.point(cell)
		var radius: float = Balance.tower(kind).range
		for path_cell in route:
			var distance := point.distance_to(HexMap.point(path_cell))
			if distance <= radius:
				score += 1.0 + (radius-distance)*.2
		# Let the AI diversify coverage instead of clustering every tower.
		for t in s.towers:
			if point.distance_to(HexMap.point(t.cell)) < 1.5:
				score *= .84
		if score > best_score:
			best_score = score
			best = cell
	return best

func dps(t: Dictionary) -> float:
	return Balance.damage(t)*Balance.rate(t)*Balance.volley(t)*(1.8 if t.kind in ["Laser","Rocket","Shockwave"] else 1.0)

func buy(s: Simulation) -> void:
	var sequence := order()
	for attempt in 60:
		var choice: Dictionary = {}
		var best := 0.0
		for t in s.towers:
			if not t.job.is_empty() or t.mega or t.level>=10:
				continue
			var cost := Balance.upgrade_cost(t.kind,t.level+1)
			var next: Dictionary = t.duplicate(); next.level += 1
			var value := (dps(next)-dps(t))/cost
			if cost<=s.credits and value>best:
				best=value; choice={"type":"upgrade","id":t.id}
		var kind: String = sequence[s.towers.size()%sequence.size()]
		var price := int(Balance.tower(kind).price)
		var base := {"kind":kind,"level":1,"ultimate":false,"mega":false}
		var value := dps(base)/price*(1.4 if s.towers.size()<3 else .75)
		if s.towers.size()<14 and price<=s.credits and value>=best:
			var cell := choose_cell(s,kind)
			if cell.x!=999:
				choice={"type":"build","cell":cell,"kind":kind}
		if choice.is_empty(): break
		if choice.type=="build": s.build(choice.cell,choice.kind)
		else: s.upgrade(choice.id)

func run() -> void:
	var started := Time.get_ticks_msec()
	var rows: Array = []
	for seed_index in range(seeds):
		var s := Simulation.new(seed_index+1)
		s.visuals = false
		if first_wave > 1:
			# Isolated late-band stress scenario, explicitly separate from campaigns.
			# Budget is derived from preceding wave bonuses and a conservative
			# fraction of preceding enemy rewards, not asserted to be player history.
			s.next_wave = first_wave
			s.credits += int(first_wave*first_wave*8.0 + first_wave*300)
		var last_completed := first_wave-1
		var timed_out := false
		var band_rows: Array = []
		while s.next_wave <= maximum_wave and not s.defeated:
			buy(s)
			for tick in 120:
				s.step(.025)
			var wave := s.next_wave
			s.start_wave()
			var ticks := 0
			while s.active and ticks < 20000:
				s.step(.025)
				ticks += 1
			if s.active:
				timed_out = true
				break
			if not s.defeated:
				last_completed = wave
			if wave in [5,10,15,20,25,30,50,100,150,200] or s.defeated:
				band_rows.append({"wave":wave,"hp":s.base_hp,"credits":s.credits,"towers":s.towers.size(),"damage":s.total_damage,"seconds":s.wave_time})
		var path_sum := 0.0
		var enemy_hp_sum := 0.0
		for wave_row in s.history:
			path_sum += wave_row.path_length
			enemy_hp_sum += wave_row.enemy_hp
		rows.append({"seed":seed_index+1,"last_completed":last_completed,"defeated":s.defeated,
			"timeout":timed_out,"hp":s.base_hp,"credits_earned":s.total_earned,"credits_spent":s.total_spent,
			"damage_dealt":s.total_damage,"enemy_hp_total":enemy_hp_sum,"towers":s.towers.size(),
			"mean_path":path_sum/maxi(1,s.history.size()),"milestones":band_rows})
		print("SIM_PROGRESS ",strategy," ",first_wave," seed ",seed_index+1," last ",last_completed)
	var minimum := maximum_wave
	var maximum := 0
	var sum_completed := 0
	var passed20 := 0
	var timeouts := 0
	for row in rows:
		minimum = mini(minimum,row.last_completed)
		maximum = maxi(maximum,row.last_completed)
		sum_completed += row.last_completed
		if row.last_completed >= 20:
			passed20 += 1
		if row.timeout:
			timeouts += 1
	var report := {"strategy":strategy,"seeds":seeds,"first_wave":first_wave,"max_wave":maximum_wave,
		"scenario":"campaign" if first_wave == 1 else "funded_band_stress",
		"minimum_completed":minimum,"maximum_completed":maximum,"mean_completed":float(sum_completed)/seeds,
		"passed_20":passed20,"timeouts":timeouts,"wall_seconds":(Time.get_ticks_msec()-started)/1000.0,"rows":rows}
	if report_path.is_empty():
		report_path = "res://../simulation_%s_%d.json" % [strategy,first_wave]
	var file := FileAccess.open(report_path,FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	report.erase("rows")
	print("SIM_RESULT ",JSON.stringify(report))
	quit(0 if timeouts == 0 else 1)
