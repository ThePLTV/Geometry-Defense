extends SceneTree

var checks:=0
var failures: Array=[]
var taps:=0
func check(ok: bool, text: String) -> void:
	checks+=1
	if not ok:failures.append(text);printerr("FAIL ",text)
func _init() -> void:call_deferred("run")
func touch(pos: Vector2, pressed: bool, index: int = 0) -> void:
	var e:=InputEventScreenTouch.new();e.position=pos;e.pressed=pressed;e.index=index
	root.push_input(e,true)
func drag(pos: Vector2, relative: Vector2, index: int = 0) -> void:
	var e:=InputEventScreenDrag.new();e.position=pos;e.relative=relative;e.index=index
	root.push_input(e,true)
func mouse(pos: Vector2, pressed: bool) -> void:
	var e:=InputEventMouseButton.new();e.position=pos;e.button_index=MOUSE_BUTTON_LEFT;e.pressed=pressed
	root.push_input(e,true)
func motion(pos: Vector2, held: bool) -> void:
	var e:=InputEventMouseMotion.new();e.position=pos;e.button_mask=MOUSE_BUTTON_MASK_LEFT if held else 0
	root.push_input(e,true)
func find(node: Node, wanted: String) -> Node:
	if node.name==wanted:return node
	for child in node.get_children():
		var result:=find(child,wanted)
		if result!=null:return result
	return null
func run() -> void:
	SaveStore.directory="user://ui04_"+str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(SaveStore.directory)
	var game=load("res://main.tscn").instantiate();root.add_child(game)
	await process_frame;await process_frame
	game.set_process(false)
	for index in 3:
		game.select_music(index)
		check(game.music.stream!=null and game.music.stream.loop,"Track loops "+str(index))
	game.music_volume=.37;game.apply_audio();game.save_preferences()
	game.music_index=0;game.music_volume=0;game.load_preferences()
	check(game.music_index==2 and is_equal_approx(game.music_volume,.37),"Song and volume preferences persist")
	game.show_settings();game.show_settings_page("difficulty")
	await process_frame;await process_frame
	var hp=find(game,"Setting_hp")
	var pressure=find(game,"Setting_pressure")
	check(hp!=null and pressure!=null,"Separate difficulty and HP sliders")
	hp.value=-30;pressure.value=150
	check(is_equal_approx(game.preferred_rules.hp,.7) and is_equal_approx(game.preferred_rules.pressure,1.5),"Slider minimum and pressure")
	hp.value=100
	check(is_equal_approx(game.preferred_rules.hp,2.0),"HP +100 percent is double standard")
	game.show_settings_page("economy");await process_frame;await process_frame
	find(game,"Setting_money").value=250
	game.new_game(1)
	await process_frame;await process_frame
	check(is_equal_approx(game.sim.rules.money,2.5) and is_equal_approx(game.sim.rules.hp,2.0),"New game takes preferred modifiers")
	game.show_settings_hub(true);game.show_settings_page("difficulty")
	await process_frame;await process_frame
	find(game,"Setting_hp").value=0
	check(game.sim.rules.hp==1.0 and game.preferred_rules.hp==2.0,"Slot settings independent from new games")
	game.save_session();game.load_game(1)
	await process_frame;await process_frame
	check(game.sim.rules.hp==1.0 and is_equal_approx(game.sim.rules.money,2.5),"Slot modifiers reload")
	# Five REAL seconds at every supported speed, pause/menu freeze countdown.
	for speed in [1,2,3,5]:
		for mode in [1,2]:
			game.new_game(5);game.set_process(false);game.speed=speed;game.wave_mode=mode
			for tick in 19:game._process(.25)
			check(not game.sim.active and is_equal_approx(game.timer_remaining,.25),"Wait full five seconds "+str(speed)+"/"+str(mode))
			game.paused=true;game._process(1)
			check(not game.sim.active and is_equal_approx(game.timer_remaining,.25),"Pause freezes countdown")
			game.paused=false;game.show_game_menu();game._process(1)
			check(not game.sim.active and is_equal_approx(game.timer_remaining,.25),"Menu freezes countdown")
			game.close_sheet();game._process(.25)
			check(game.sim.active,"Next wave starts at five seconds")
	game.new_game(5);game.set_process(false)
	# Scroll starts ON an actual button: drag cancels tap; release must not fire.
	var box: VBoxContainer=game.open_sheet(500)
	var buttons: Array=[]
	for i in 14:
		var b: Button=game.button("Button "+str(i),func() -> void:taps+=1,false,90)
		box.add_child(b);buttons.append(b)
	await process_frame;await process_frame
	var scroll: GestureScroll=box.get_parent()
	var pos: Vector2=buttons[2].get_global_rect().get_center()
	touch(pos,true);await process_frame
	check(buttons[2].is_pressed(),"Real touch presses button before scroll threshold")
	drag(pos-Vector2(0,160),Vector2(0,-160));await process_frame
	touch(pos-Vector2(0,160),false);await process_frame
	check(scroll.scroll_vertical>=150 and taps==0,"Drag from button scrolls and never activates it")
	# A regular tap still works after cancellation.
	pos=buttons[3].get_global_rect().get_center()
	touch(pos,true);touch(pos,false);await process_frame
	check(taps==1,"Tap still activates once after a drag")
	var slider:=HSlider.new();slider.custom_minimum_size.y=70;slider.value=50
	box.add_child(slider);box.move_child(slider,0);scroll.scroll_vertical=0
	var releases: Array=[0]
	slider.drag_ended.connect(func(_changed: bool) -> void:releases[0]+=1)
	await process_frame;await process_frame
	pos=slider.get_global_rect().get_center()
	motion(pos,false);mouse(pos,true);motion(pos-Vector2(0,90),true);mouse(pos-Vector2(0,90),false)
	await process_frame
	check(releases[0]==1,"Slider receives release after vertical scrolling")
	check(scroll.scroll_vertical>=80,"Vertical swipe can start on a slider")
	scroll.scroll_vertical=0
	await process_frame;await process_frame
	pos=slider.get_global_rect().get_center()
	motion(pos,false);mouse(pos,true);motion(pos+Vector2(150,0),true);mouse(pos+Vector2(150,0),false)
	await process_frame
	check(slider.value>50 and scroll.scroll_vertical==0,"Horizontal slider drag stays horizontal")
	check(releases[0]==2,"Slider ends the following drag normally")
	# OptionButton is a release action and is cancellable by the same gesture.
	game.show_settings_page("audio");await process_frame;await process_frame
	var tracks: OptionButton=find(game,"MusicTracks")
	check(tracks.action_mode==BaseButton.ACTION_MODE_BUTTON_RELEASE,"Song picker waits for release")
	pos=tracks.get_global_rect().get_center()
	touch(pos,true);drag(pos-Vector2(0,80),Vector2(0,-80));touch(pos-Vector2(0,80),false)
	await process_frame
	check(not tracks.get_popup().visible,"Dragging song picker does not open popup")
	game.close_sheet()
	game.show_game();game.wave_mode=1;game.timer_remaining=3;game.update_hud()
	check(game.countdown.visible and game.countdown.remaining==3,"Countdown ring reflects remaining time")
	var file:=FileAccess.open("res://tests/patch04-ui.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures},"  "));file.close()
	print("UI04: ",checks," checks; ",failures.size()," failures")
	game.music.stop();game.music.stream=null
	await create_timer(.15).timeout
	root.remove_child(game);game.free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
