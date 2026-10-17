extends SceneTree

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var view := "gameplay"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--view="):
			view = arg.get_slice("=",1)
	SaveStore.directory = "user://capture"
	DirAccess.make_dir_recursive_absolute(SaveStore.directory)
	var game = load("res://main.tscn").instantiate()
	root.add_child(game)
	await process_frame
	if view != "menu":
		game.new_game(5)
		game.sim.credits = 5000
		var placements := [[Vector2i(-1,2),"Minigun"],[Vector2i(4,-1),"Laser"],[Vector2i(7,0),"Rocket"],[Vector2i(7,2),"Shockwave"]]
		for placement in placements:
			game.sim.build(placement[0],placement[1])
		game.sim.next_wave = 5
		game.sim.start_wave()
		for i in range(240):
			game.sim.step(.05)
		if view == "debug":
			game.board.debug_grid = true
			game.board.show_route = true
		elif view == "build":
			game.select_cell(Vector2i(-1,4))
		elif view == "tower":
			game.select_cell(Vector2i(4,-1))
		game.paused = view in ["build","tower","debug"]
	await create_timer(.5).timeout
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var filename := "res://../GeometryDefense-%s.png" % view
	var error := image.save_png(filename)
	print("CAPTURE ",view," ",error)
	quit(0 if error == OK else 1)
