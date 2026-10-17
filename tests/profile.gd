extends SceneTree

func _init() -> void:
	call_deferred("run")

func run() -> void:
	SaveStore.directory="user://profile_revision"
	DirAccess.make_dir_recursive_absolute(SaveStore.directory)
	var game=load("res://main.tscn").instantiate()
	root.add_child(game)
	game.new_game(5)
	game.set_process(false)
	var s: Simulation=game.sim
	s.credits=1000000
	var placements:=0
	for cell in s.map.cells:
		if placements>=20: break
		var kind: String=Balance.KINDS[placements%4]
		if s.build(cell,kind).is_empty():
			var t: Dictionary=s.towers[-1]
			t.level=10; t.ultimate=true
			placements+=1
	s.next_wave=59
	s.start_wave()
	s.spawn_queue=[]
	var route:=s.map.route(s.map.spawn)
	for i in 50:
		var e:=s.spawn_enemy("normal")
		e.cell=route[1+i%(route.size()-3)]
		e.next=s.map.next_cell(e.cell)
		e.progress=float(i%5)*.15
		e.pos=HexMap.point(e.cell).lerp(HexMap.point(e.next),e.progress)
		e.previous_pos=e.pos
		e.hp=1000000; e.max_hp=e.hp; e.speed=.05
	var maximum_projectiles:=0
	var maximum_effects:=0
	var update_us:=0
	var maximum_us:=0
	var started:=Time.get_ticks_usec()
	for frame in 180:
		var start:=Time.get_ticks_usec()
		for tick in 4: s.step(.025)
		var duration:=Time.get_ticks_usec()-start
		update_us+=duration; maximum_us=maxi(maximum_us,duration)
		maximum_projectiles=maxi(maximum_projectiles,s.projectiles.size())
		maximum_effects=maxi(maximum_effects,s.effects.size())
		game.board.queue_redraw()
		game.update_hud()
		await process_frame
	var seconds:=(Time.get_ticks_usec()-started)/1000000.0
	var report:={"platform":OS.get_name(),"renderer":"GL Compatibility desktop","frames":180,
		"towers":placements,"enemies":50,"game_seconds":s.time,"wall_seconds":seconds,
		"mean_sim_update_ms":update_us/180000.0,"max_sim_update_ms":maximum_us/1000.0,
		"peak_projectiles":maximum_projectiles,"peak_effects":maximum_effects,
		"limits_respected":maximum_projectiles<=Balance.cfg.max_projectiles and maximum_effects<=Balance.cfg.max_effects,
		"note":"Desktop synthetic stress: four 25ms ticks per rendered frame, equivalent to x5 at 50 FPS. Not Android device FPS."}
	var file:=FileAccess.open("res://tests/revision-profile.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  ")); file.close()
	print("PROFILE ",JSON.stringify(report))
	game.music.stop(); game.music.stream=null
	await create_timer(.15).timeout
	quit(0 if report.limits_respected else 1)
