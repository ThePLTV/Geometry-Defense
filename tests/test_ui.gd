extends SceneTree

var failures: Array=[]
var count:=0
func check(value: bool, message: String) -> void:
	count+=1
	if not value:
		failures.append(message); printerr("FAIL: ",message)
func find_button(node: Node, prefix: String) -> Button:
	if node is Button and node.text.begins_with(prefix): return node
	for child in node.get_children():
		var result:=find_button(child,prefix)
		if result!=null: return result
	return null
func _init() -> void:
	call_deferred("run")
func run() -> void:
	SaveStore.directory="user://ui_revision_"+str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(SaveStore.directory)
	var game=load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	game.set_process(false)
	check(find_button(game,"Новая игра")!=null,"Menu starts")
	check(game.music.stream!=null,"Background track loaded")
	check(game.music.stream.loop,"Background music loops")
	game.new_game(1)
	await process_frame; await process_frame
	game.board.layout_board()
	var input:=InputEventMouseButton.new()
	input.button_index=MOUSE_BUTTON_LEFT; input.pressed=true
	input.position=game.board.center(Vector2i(-1,2))
	game.board._gui_input(input)
	await process_frame; await process_frame
	check(game.overlay==null,"Build choice is non-modal")
	for kind in Balance.KINDS:
		var card:=find_button(game,Balance.tower(kind).name+" ·")
		check(card!=null and card.is_visible_in_tree(),"Four visible build cards "+kind)
		check(card.get_global_rect().end.y<game.size.y,"Build card fits viewport")
	find_button(game,"Миниган ·").pressed.emit()
	check(game.sim.towers.size()==1 and game.sim.credits==35,"One affordable purchase")
	game.select_cell(Vector2i(-1,2))
	await process_frame; await process_frame
	check(game.overlay==null and find_button(game,"Продать")!=null,"Tower selects lower actions")
	var sell:=find_button(game,"Продать")
	var upgrade:=find_button(game,"Улучшить")
	check(sell.global_position.x<upgrade.global_position.x,"Sale left, upgrade right")
	game.board._gui_input(input)
	game.board._process(.41)
	check(game.details!=null,"Hold reveals detailed stats")
	input.pressed=false; game.board._input(input)
	check(game.details==null,"Release hides stats")
	game.paused=true
	upgrade.pressed.emit()
	var t: Dictionary=game.sim.towers[0]
	var remaining: float=t.job_left
	game._process(.25)
	check(t.level==1 and t.job_left==remaining,"Upgrade can be ordered on pause, timer frozen")
	game.paused=false
	for i in 120: game._process(.025)
	check(t.level==2,"UI processes jobs between waves")
	for speed in [1,2,3,5]:
		game.speed=speed
		var before: float=game.sim.time
		game._process(.2)
		check(absf(game.sim.time-before-.2*speed)<.00001,"Unified speed "+str(speed))
	game.start_wave()
	check(game.sim.active,"Wave begins")
	game.save_session()
	var checkpoint:=SaveStore.load_slot(1)
	check(not checkpoint.active and checkpoint.next_wave==1,"Active session never overwrites successful checkpoint")
	check(SaveStore.load_session(1).active,"Active session is separate")
	game.sim.base_hp=0; game.sim.active=false; game.sim.defeated=true
	game._process(.025)
	find_button(game,"Восстановить чекпоинт").pressed.emit()
	check(game.sim.base_hp==10 and not game.sim.defeated and game.sim.next_wave==1,"Defeat restores last good checkpoint")
	check(game.sim.towers.is_empty(),"Defeat restores checkpoint towers, not failed session")
	# Fixed layouts on narrow/tall and shorter phones; all active cells remain inside field.
	for dims in [Vector2i(720,1600),Vector2i(720,1280),Vector2i(720,1920)]:
		root.size=dims
		await process_frame; await process_frame
		game.select_cell(Vector2i(-1,4))
		await process_frame; await process_frame
		game.board.layout_board()
		for cell in game.sim.map.cells:
			var p: Vector2=game.board.center(cell)
			check(p.x>=0 and p.y>=0 and p.x<=game.board.size.x and p.y<=game.board.size.y,"Map cell fits aspect "+str(dims))
		for kind in Balance.KINDS:
			var card:=find_button(game,Balance.tower(kind).name+" ·")
			check(card.get_global_rect().end.y<game.size.y,"Build fits aspect "+str(dims))
		check(game.board.get_global_rect().end.y<=game.footer.global_position.y+.01,"Footer reserves space outside map")
	game.show_game_menu()
	check(find_button(game,"Статистика")!=null,"Statistics preserved")
	game.close_sheet(); game.show_settings()
	check(find_button(game,"Назад")!=null,"Settings accessible")
	var report:={"checks":count,"failures":failures}
	var file:=FileAccess.open("res://tests/revision-ui-results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  ")); file.close()
	print("REVISION UI: ",count," checks; ",failures.size()," failures")
	game.music.stop()
	game.music.stream=null
	await create_timer(.15).timeout
	root.remove_child(game)
	game.free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
