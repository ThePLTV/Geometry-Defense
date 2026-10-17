extends SceneTree

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var view:="gameplay"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--view="): view=arg.get_slice("=",1)
	SaveStore.directory="user://capture_revision"
	DirAccess.make_dir_recursive_absolute(SaveStore.directory)
	Balance.load_config()
	var game=null
	if view=="models":
		root.content_scale_size=Vector2i(1440,720)
		root.size=Vector2i(1440,720)
		var canvas:=Control.new()
		canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		root.add_child(canvas)
		canvas.draw.connect(func() -> void:
			canvas.draw_rect(Rect2(0,0,1440,720),Color("1b2025"))
			for row in 4:
				var kind: String=Balance.KINDS[row]
				for col in 12:
					var p:=Vector2(60+col*120,70+row*170)
					TowerVisuals.draw(canvas,p,kind,34,mini(col+1,10),col>=10,col==11)
					var caption:=str(col+1) if col<10 else "ULT" if col==10 else "MEGA"
					canvas.draw_string(ThemeDB.fallback_font,p+Vector2(-28,70),caption,HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("cbd8df"))
				canvas.draw_string(ThemeDB.fallback_font,Vector2(12,24+row*170),Balance.tower(kind).name,HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color(Balance.tower(kind).color))
		)
	else:
		game=load("res://main.tscn").instantiate()
		root.add_child(game)
		await process_frame
		game.set_process(false)
		if view=="settings": game.show_settings()
		elif view!="menu":
			game.new_game(5)
			game.sim.credits=800
			var placements:=[[Vector2i(-1,2),"Minigun"],[Vector2i(4,-1),"Laser"],[Vector2i(7,0),"Rocket"],[Vector2i(7,2),"Shockwave"]]
			for i in placements.size():
				game.sim.build(placements[i][0],placements[i][1])
				game.sim.towers[-1].level=[5,6,4,7][i]
			game.sim.next_wave=19
			game.sim.start_wave()
			for i in 600: game.sim.step(.025)
			if view=="build": game.select_cell(Vector2i(-1,4))
			elif view=="tower":
				game.select_cell(Vector2i(4,-1))
				game.show_details(game.sim.tower_at(Vector2i(4,-1)).id)
			elif view=="debug": game.board.show_route=true; game.board.debug_grid=true
			game.paused=true
			game.update_hud()
	await create_timer(.25).timeout
	await RenderingServer.frame_post_draw
	var picture:=root.get_texture().get_image()
	var path:="res://../GeometryDefense-v0.2.0-%s.png"%view
	var error:=picture.save_png(path)
	print("CAPTURE ",view," ",picture.get_size()," ",error)
	if game!=null:
		game.music.stop(); game.music.stream=null
		await create_timer(.1).timeout
	quit(0 if error==OK else 1)
