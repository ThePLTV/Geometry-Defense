extends SceneTree

var failures: Array = []
var count := 0

func check(value: bool, message: String) -> void:
	count += 1
	if not value:
		failures.append(message)
		printerr("FAIL: ",message)

func find_button(node: Node, prefix: String) -> Button:
	if node is Button and node.text.begins_with(prefix):
		return node
	for child in node.get_children():
		var result := find_button(child,prefix)
		if result != null:
			return result
	return null

func _init() -> void:
	call_deferred("run")

func run() -> void:
	SaveStore.directory = "user://ui_tests_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(SaveStore.directory)
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	check(find_button(game,"Новая игра") != null,"Main menu available")
	find_button(game,"Новая игра").pressed.emit()
	check(find_button(game,"Слот 5") != null,"All five save slots selectable")
	find_button(game,"Слот 1").pressed.emit()
	await process_frame
	await process_frame
	check(game.sim != null and game.game_visible,"New slot starts real game")
	var input := InputEventMouseButton.new()
	input.button_index = MOUSE_BUTTON_LEFT
	input.pressed = true
	input.position = game.board.center(Vector2i(-1,2))
	game.board._gui_input(input)
	check(game.overlay != null,"Board click opens construction sheet")
	var build := find_button(game,"Миниган")
	check(build != null and not build.disabled,"Build card is actionable")
	build.pressed.emit()
	check(game.sim.towers.size() == 1 and game.sim.credits == 270,"Build UI commits one purchase")
	game.select_cell(Vector2i(-1,2))
	var damage := find_button(game,"Урон  0/10")
	check(damage != null,"Selected tower exposes damage branch")
	damage.pressed.emit()
	check(game.sim.towers[0].d == 1,"Upgrade button changes tower")
	find_button(game,"Закрыть").pressed.emit()
	game.start_wave()
	check(game.sim.active,"Start button begins wave")
	game.toggle_pause()
	var before: float = game.sim.time
	game._process(.5)
	check(game.sim.time == before,"Pause stops simulation")
	game.select_cell(Vector2i(-1,4))
	build = find_button(game,"Миниган")
	build.pressed.emit()
	check(game.sim.towers.size() == 2,"Building is available while paused")
	game.show_game_menu()
	check(find_button(game,"Сохранить чекпоинт").disabled,"Manual saving disabled within wave")
	game.close_sheet()
	for expected_speed in [2,3,5,1]:
		game.cycle_speed()
		check(game.speed == expected_speed,"Speed selector cycle")
	var state := SaveStore.load_slot(1)
	check(int(state.next_wave) == 1 and state.towers.is_empty(),"Initial checkpoint remains until wave completion")
	game.sim.base_hp = 0
	game.sim.active = false
	game.sim.defeated = true
	game._process(.05)
	check(find_button(game,"Восстановить чекпоинт") != null,"Defeat offers checkpoint recovery")
	find_button(game,"Восстановить чекпоинт").pressed.emit()
	check(not game.sim.defeated and game.sim.base_hp == 10,"Recovery restores successful checkpoint")
	game.show_help()
	check(find_button(game,"Назад") != null,"Help can return to menu")
	game.new_game(2)
	game.sim.build(Vector2i(-1,2),"Minigun")
	game.sim.build(Vector2i(-1,4),"Minigun")
	game.start_wave()
	for i in range(3000):
		if not game.sim.active:
			break
		game.sim.step(.05)
	game._process(0)
	check(not game.sim.defeated and game.sim.next_wave == 2,"First wave completes with a reasonable purchase")
	state = SaveStore.load_slot(2)
	check(int(state.next_wave) == 2 and state.history.size() == 1,"Actual wave completion autosaves rewards and history")
	var reference := ""
	for tested_speed in [1,5]:
		for frame_delta in [.01,.05,.1,.25]:
			game.new_game(3)
			game.sim.rng.seed = 999
			game.sim.build(Vector2i(-1,2),"Minigun")
			game.speed = tested_speed
			game.start_wave()
			for i in range(int(5.0/(frame_delta*tested_speed))):
				game._process(frame_delta)
			var fingerprint := "%d:%d:%.3f:%d:%.3f" % [game.sim.base_hp,game.sim.credits,game.sim.total_damage,game.sim.enemies.size(),game.sim.time]
			for e in game.sim.enemies:
				fingerprint += "/%d:%s:%.4f" % [e.id,str(e.cell),e.progress]
			if reference.is_empty():
				reference = fingerprint
			if fingerprint != reference:
				print("FRAME_MISMATCH speed=",tested_speed," delta=",frame_delta," actual=",fingerprint," expected=",reference)
			check(fingerprint == reference,"Fixed-step positions/damage are independent of frame rate and speed")
	game.show_settings()
	var options: Array = []
	for child in game.body.get_children():
		if child is OptionButton:
			options.append(child)
	check(options.size() == 2,"Settings expose meaningful game defaults")
	options[0].item_selected.emit(2)
	options[1].item_selected.emit(2)
	var preferences := ConfigFile.new()
	check(preferences.load(SaveStore.directory.path_join("preferences.cfg")) == OK,"Preferences persist locally")
	check(int(preferences.get_value("game","speed")) == 3,"Default speed persists")
	check(int(preferences.get_value("game","wave_mode")) == 2,"Default wave mode persists")
	game.new_game(4)
	check(game.speed == 3 and game.wave_mode == 2,"New slot uses chosen defaults")
	check(game.timer_remaining == 5.0,"New timer mode starts from five seconds")
	var result := {"checks":count,"failures":failures,"passed":failures.is_empty()}
	var file := FileAccess.open("res://../ui-tests.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t"))
	file.close()
	print("UI_TESTS ",JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
