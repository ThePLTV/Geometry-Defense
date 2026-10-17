extends SceneTree
func _init() -> void:
	Balance.load_config()
	var waves: Array=[]
	var budget:=int(Balance.cfg.starting_credits)
	for wave in range(1,101):
		var config:=WaveCatalog.generate(wave)
		var income:=int(config.completion_bonus)
		for kind in config.groups:
			income+=int(config.groups[kind])*(int(config.reward[kind])+(2*int(config.reward.child) if kind=="split" else 0))
		budget+=income;config.max_income=income;config.theoretical_budget=budget
		waves.append(config)
	var file:=FileAccess.open("res://data/waves_1_100.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(waves,"  "));file.close()
	DirAccess.make_dir_recursive_absolute("res://docs/test-results/v0.3.0")
	var csv:=FileAccess.open("res://docs/test-results/v0.3.0/tower_levels.csv",FileAccess.WRITE)
	csv.store_csv_line(PackedStringArray(["class","level","damage","attacks_per_second","volley","raw_dps","range_R","upgrade_price","ultimate_price","splash_radius","projectile_speed","targeting"]))
	for kind in Balance.KINDS:
		for level in range(1,11):
			var t:={"kind":kind,"level":level,"ultimate":false,"mega":false}
			csv.store_csv_line(PackedStringArray([kind,str(level),str(Balance.damage(t)),str(Balance.rate(t)),str(Balance.volley(t)),str(Balance.damage(t)*Balance.rate(t)*Balance.volley(t)),str(Balance.reach(t)),str(Balance.upgrade_cost(kind,level+1) if level<10 else 0),str(Balance.ultimate_cost(kind)),str(Balance.cfg.rocket_radius if kind=="Rocket" else Balance.reach(t) if kind=="Shockwave" else 0),str(Balance.cfg.bullet_speed if kind=="Minigun" else Balance.cfg.rocket_speed if kind=="Rocket" else Balance.cfg.wave_speed if kind=="Shockwave" else 0),"nearest_geometric"]))
	csv.close();print("BUDGET_100 ",budget);quit()
