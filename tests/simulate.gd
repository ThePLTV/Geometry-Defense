extends SceneTree

var strategy := "mixed"
var seeds := 30
var maximum_wave := 200
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

func buy(s: Simulation) -> void:
	# Deterministic, deliberately modest policy. No money is added in campaigns.
	var sequence := order()
	var target_count: int = mini(18,3 + int(s.next_wave/3.0))
	var attempts := 0
	while attempts < 120:
		attempts += 1
		var choice: Dictionary = {}
		var best_value := 0.0
		# Compare upgrade efficiency to adding coverage; ultimates get a fixed bonus.
		for t in s.towers:
			if t.mega:
				continue
			for branch in ["d","s"]:
				if t[branch] >= 10:
					continue
				var cost := Balance.upgrade_cost(t.kind,int(t[branch])+1)
				var value: float = Balance.damage(t)*Balance.rate(t)*(Balance.cfg.damage_growth-1.0 if branch == "d" else Balance.cfg.rate_growth-1.0)/cost
				if t.kind in ["Rocket","Shockwave"]:
					value *= 1.7
				if cost <= s.credits and value > best_value:
					best_value = value
					choice = {"action":branch,"tower":t,"cost":cost}
			if not t.ultimate and t.d >= 5 and t.s >= 5:
				var cost := Balance.ultimate_cost(t.kind)
				var value: float = Balance.damage(t)*Balance.rate(t)*0.8/cost
				if cost <= s.credits and value > best_value:
					best_value = value
					choice = {"action":"ultimate","tower":t,"cost":cost}
		var kind: String = sequence[s.towers.size()%sequence.size()]
		var price := int(Balance.tower(kind).price)
		if s.towers.size() < target_count and price <= s.credits:
			var value: float = Balance.tower(kind).damage * Balance.tower(kind).rate / price
			if kind in ["Rocket","Shockwave"]:
				value *= 1.7
			# The first towers provide essential coverage; late towers get base DPS.
			if s.towers.size() < 3:
				value *= 1.8
			if value >= best_value:
				var cell := choose_cell(s,kind)
				if cell.x != 999:
					choice = {"action":"build","cell":cell,"kind":kind}
		if choice.is_empty():
			break
		match choice.action:
			"build": s.build(choice.cell,choice.kind)
			"ultimate": s.buy_ultimate(choice.tower.id)
			_: s.upgrade(choice.tower.id,choice.action)
	# Merge when possible, but only after creating substantial coverage.
	if s.towers.size() >= 12:
		for a in s.towers.duplicate():
			for b in s.towers.duplicate():
				if s.can_merge(a,b):
					s.merge(a.id,b.id)
					return

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
			var wave := s.next_wave
			s.start_wave()
			var ticks := 0
			while s.active and ticks < 20000:
				s.step(.05)
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
