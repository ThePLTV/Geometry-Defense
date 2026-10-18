extends SceneTree

var checks:=0
var failures: Array=[]
func expect(ok: bool, message: String) -> void:
	checks+=1
	if not ok:failures.append(message);printerr("FAIL ",message)
func _init() -> void:call_deferred("run")
func fixture(kind: String) -> Simulation:
	var s:=Simulation.new(77)
	s.credits=100000;s.visuals=false;s.diagnostics.enabled=false
	s.build(Vector2i(-1,2),kind)
	return s
func target(s: Simulation, pos: Vector2) -> Dictionary:
	var e:=s.spawn_enemy("normal");e.pos=pos;e.previous_pos=pos;e.hp=10000000;e.max_hp=e.hp;e.speed=0
	return e
func run() -> void:
	Balance.load_config()
	var table: Array=JSON.parse_string(FileAccess.get_file_as_string("res://data/waves_1_100.json"))
	for wave in range(1,101):
		var generated: Dictionary=JSON.parse_string(JSON.stringify(WaveCatalog.generate(wave)))
		for key in ["groups","hp","reward","completion_bonus"]:
			expect(generated[key]==table[wave-1][key],"Wave formula/table "+str(wave)+"/"+key)
		var queue:=WaveCatalog.queue(generated)
		expect(queue.count("boss")== (1 if wave%5==0 else 0),"One boss every five waves")
		if wave%20==19:
			expect(queue.count("normal")==10 and queue.count("fast")==10 and queue.count("split")==10,"Exactly 30 mixed entries")
		if wave%5==0:expect(queue.back()=="boss","Boss after ordinary enemies")
		for kind in queue:expect(kind in ["normal","fast","split","boss"],"Approved generator type")
	expect(Balance.cfg.enemies.keys().size()==4,"Exactly three parents and child form")
	for kind in Balance.KINDS:
		var s:=fixture(kind)
		var t: Dictionary=s.towers[0]
		for level in range(1,11):
			t.level=level
			if kind=="Minigun":expect(absf(Balance.reach(t)-(1.25+(level-1)*1.75/9))<.000001,"Exact minigun radius")
			elif kind=="Rocket":expect(absf(Balance.reach(t)-(1.75+(level-1)*2.25/9))<.000001,"Exact rocket radius")
			elif kind=="Laser":expect(Balance.reach(t)==2.5,"Laser fixed radius")
		# Every class must attack a target inside/at the border at its scheduled cadence.
		for distance in [.7,Balance.reach(t)-.00001,Balance.reach(t)]:
			s=fixture(kind);t=s.towers[0];t.level=10
			var e:=target(s,HexMap.point(t.cell)+Vector2(distance,0))
			var duration:=maxf(3.0/Balance.rate(t),1.0)
			for i in int(ceil(duration/.025)):
				s.time+=.025;Combat.step(s,.025)
			expect(t.shots>=3,"No unexplained idle at range "+kind)
			expect(t.hits>0,"Attacks inflict damage "+kind)
		# Target death between acquisition and next tick must not freeze the gun.
		s=fixture(kind);t=s.towers[0]
		var dead:=target(s,HexMap.point(t.cell)+Vector2(.7,0))
		var alive:=target(s,HexMap.point(t.cell)+Vector2(.8,0))
		dead.dead=true
		Combat.step(s,.025)
		expect(t.target_id==alive.id and t.shots==1,"Target death reacquired "+kind)
		# Installation skips combat entirely.
		s.upgrade(t.id);var shots: float=t.shots
		Combat.step(s,1)
		expect(t.shots==shots,"No firing while upgrading")
	# Overkill, rewards, split children and exactly once completion bonus.
	var s:=fixture("Minigun");var t: Dictionary=s.towers[0]
	var e:=s.spawn_enemy("normal");var before:=s.credits
	s.hit(e,100,t)
	expect(e.hp==0 and t.damage==28 and t.overkill==72 and t.attempted==100,"Effective damage clamped, overkill separate")
	s.kill(e,t)
	expect(s.credits==before+int(WaveCatalog.generate(1).reward.normal),"Death rewarded once")
	s=fixture("Minigun");t=s.towers[0];s.next_wave=24
	e=s.spawn_enemy("split");before=s.credits
	s.hit(e,100000,t)
	var children: Array=[]
	for child in s.enemies:
		if child.kind=="child":children.append(child)
	expect(children.size()==2,"Exactly two circular children")
	for child in children:
		expect(child.color==Balance.cfg.enemies.split.color and child.speed>e.speed,"Small purple faster child")
		s.hit(child,100000,t)
	var cfg:=WaveCatalog.generate(24)
	expect(s.credits-before==cfg.reward.split+2*cfg.reward.child,"Parent and children rewards match B1")
	s=fixture("Minigun");s.start_wave();before=s.credits;s.complete_wave();var after:=s.credits;s.complete_wave()
	expect(after-before==WaveCatalog.generate(1).completion_bonus and s.credits==after and s.next_wave==2,"Completion bonus exactly once")
	# Real telemetry files and exportable archive; no save files included.
	s=fixture("Minigun");s.diagnostics.enabled=true
	var dir:="user://patch03_diag_"+str(Time.get_ticks_usec())
	s.diagnostics.attach(dir)
	s.diagnostics.action("tower_select",s.time,{"tower_id":s.towers[0].id})
	for i in 220:s.diagnostics.emit("fixture",float(i),{"id":i},true)
	expect(s.diagnostics.ring.size()==CombatDiagnostics.MAX_RING,"Event ring bounded")
	for i in 1100:s.diagnostics.emit("rotation_fixture",float(i),{"payload":"x".repeat(512)},true)
	expect(FileAccess.file_exists(dir.path_join("events.jsonl.1")),"Event log rotation creates bounded prior generation")
	expect(FileAccess.get_file_as_bytes(dir.path_join("events.jsonl")).size()<CombatDiagnostics.MAX_BYTES+2048,"Current event file bounded")
	s.diagnostics.issue("FIXTURE_ERROR",s.time,{"tower_id":s.towers[0].id},get_stack())
	var path:=s.diagnostics.export_zip(s)
	var restored:=Simulation.new(999)
	expect(restored.restore(s.snapshot(true)),"Diagnostic session saves and restores")
	expect(restored.diagnostics.metadata.seed=="77" and restored.diagnostics.metadata.match_id==s.diagnostics.metadata.match_id,"Loaded report preserves true seed and match ID")
	expect(restored.diagnostics.actions.size()>=s.diagnostics.actions.size(),"Action timeline survives app restart")
	expect(FileAccess.file_exists(path),"Diagnostic ZIP created")
	var zip:=ZIPReader.new();expect(zip.open(path)==OK,"Diagnostic ZIP opens")
	for name in ["events.jsonl","errors.jsonl","match_summary.json","balance_report.json","balance_report.csv"]:
		expect(zip.get_files().has(name),"Archive contains "+name)
	var summary: Dictionary=JSON.parse_string(zip.read_file("match_summary.json").get_string_from_utf8())
	expect(summary.metadata.seed=="77" and summary.metadata.version=="0.4.0","Reproduction metadata")
	for line in zip.read_file("events.jsonl").get_string_from_utf8().strip_edges().split("\n"):
		expect(JSON.parse_string(line) is Dictionary,"Valid JSONL record")
	zip.close();s.diagnostics.close()
	var logger:=EngineErrorLogger.new();logger.directory=dir
	OS.add_logger(logger)
	push_warning("PATCH03_LOGGER_FIXTURE")
	OS.remove_logger(logger)
	var engine_errors:=logger.drain()
	expect(not engine_errors.is_empty(),"Real engine warning captured through Logger")
	expect(FileAccess.file_exists(dir.path_join("engine_errors.jsonl")),"Engine error persisted before next frame")
	# A real game UI must retain identical board geometry in every selection state.
	SaveStore.directory="user://patch03_ui_"+str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(SaveStore.directory)
	var game=load("res://main.tscn").instantiate();root.add_child(game)
	await process_frame;game.set_process(false);game.new_game(1)
	for dims in [Vector2i(720,1280),Vector2i(720,1600),Vector2i(720,1920)]:
		root.size=dims;await process_frame;await process_frame
		game.board.layout_board()
		var rect: Rect2=game.board.get_global_rect()
		var scale: float=game.board.draw_scale
		for cell in [Vector2i(-1,2),Vector2i(-1,4),Vector2i(999,999)]:
			game.select_cell(cell);await process_frame;await process_frame;game.board.layout_board()
			expect(game.board.get_global_rect()==rect and game.board.draw_scale==scale,"Board stable across selection "+str(dims))
		game.sim.credits=10000
		if game.sim.towers.is_empty():game.sim.build(Vector2i(-1,2),"Minigun")
		game.select_cell(Vector2i(-1,2));await process_frame;await process_frame;game.board.layout_board()
		expect(game.board.get_global_rect()==rect and game.board.draw_scale==scale,"Board stable with tower actions")
		game.show_details(game.sim.towers[0].id);await process_frame
		expect(game.board.get_global_rect()==rect,"Board stable while holding")
		game.hide_details();game.show_game_menu();await process_frame
		expect(game.board.get_global_rect()==rect,"Board stable beneath settings")
		game.close_sheet()
	game.music.stop();game.music.stream=null;await create_timer(.15).timeout
	root.remove_child(game);game.free();await process_frame
	var file:=FileAccess.open("res://tests/patch03-tests.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures},"  "));file.close()
	print("PATCH03 CHECKS ",checks," failures ",failures.size())
	quit(0 if failures.is_empty() else 1)
