extends SceneTree

func _init() -> void:call_deferred("run")
func run() -> void:
	var rows: Array=[]
	for wave in [30,60,90]:
		for classes in [["Laser"],["Rocket"],["Laser","Rocket"],["Rocket","Rocket"],["Minigun","Minigun"]]:
			for mega in [false,true]:
				var s:=Simulation.new(1);s.visuals=false;s.diagnostics.enabled=false;s.credits=100000
				for i in classes.size():
					var cell: Vector2i=[Vector2i(3,0),Vector2i(-1,2)][i]
					if not s.build(cell,classes[i]).is_empty():printerr("Invalid cheese fixture ",cell);quit(1);return
					var t: Dictionary=s.towers[-1];t.level=10;t.ultimate=true;t.mega=mega
				s.next_wave=wave;s.start_wave()
				# Many leaks are expected in this deliberately insufficient defense.
				for tick in 12000:
					s.step(.025)
					if not s.active:break
				var stats: Dictionary=s.wave_stats
				var early:=int(stats.get("early_ordinary_killed",0))
				var normal_count:=0
				for kind in stats.composition:
					if kind!="boss":normal_count+=int(stats.composition[kind])
				rows.append({"wave":wave,"classes":classes,"mega":mega,"hp":WaveCatalog.generate(wave).hp.normal,"ordinary_spawned":normal_count,"early_kills":early,"early_fraction":early/maxf(1,normal_count),"killed":stats.killed,"leaked":stats.leaked,"base_hp":s.base_hp})
	var file:=FileAccess.open("res://tests/patch04-anti-spawn.json",FileAccess.WRITE);file.store_string(JSON.stringify(rows,"  "));file.close()
	print("ANTI SPAWN: ",rows.size()," scenarios")
	quit()
