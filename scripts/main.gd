extends Control

var debug_enabled:=true
var error_logger: EngineErrorLogger
var music: AudioStreamPlayer
var music_volume := .55
var music_index := 0
const TRACKS = [
 {"id":"jazz_noir","title":"Just One More Drink — Jazz Noir","path":"res://assets/audio/jazz_noir.ogg"},
 {"id":"drums","title":"Барабанщики","path":"res://assets/audio/background.ogg"},
 {"id":"adidas","title":"Н ворд все в адидасах","path":"res://assets/audio/adidas.ogg"},
 {"id":"decided","title":"Всё решено","path":"res://assets/audio/decided.ogg"}
]
var preferred_rules: Dictionary={"pressure":1.0,"hp":1.0,"money":1.0}
var countdown: WaveCountdown
var settings_in_game := false
var settings_page := ""
var screen_name := ""
var screen_back := Callable()
var sheet_back := Callable()
var sheet_page := ""
var exit_deadline_msec := 0
var exit_hint: Label
const EXIT_WINDOW_MSEC := 2000
var footer: VBoxContainer
var action_signature := ""
var details: PanelContainer
var session_timer := 0.0
var sim: Simulation
var board: GameBoard
var body: VBoxContainer
var overlay: Control
var sheet: PanelContainer
var hud_hp: Label
var hud_wave: Label
var hud_credits: Label
var status_label: Label
var toast_label: Label
var start_button: Button
var pause_button: Button
var speed_button: Button
var slot := 1
var speed := 1
var paused := false
var wave_mode := 0
var timer_remaining := 5.0
var accumulator := 0.0
var ui_timer := 0.0
var toast_timer := 0.0
var game_visible := false
var selected := Vector2i(999,999)
var selected_id := -1
var merge_source := -1
var speed_values := [1,2,3,5]
var checkpoint_error := ""
var shown_defeat := false
var sound_enabled := true
var menu_font: Font
var preferred_speed := 1
var preferred_wave_mode := 0

func _ready() -> void:
	Balance.load_config()
	error_logger=EngineErrorLogger.new()
	OS.add_logger(error_logger)
	load_preferences()
	get_tree().auto_accept_quit = false
	get_tree().quit_on_go_back = false
	RenderingServer.set_default_clear_color(Color("1b2025"))
	theme = make_theme()
	setup_music()
	show_menu()

func load_preferences() -> void:
	var preferences := ConfigFile.new()
	if preferences.load(SaveStore.directory.path_join("preferences.cfg")) == OK:
		preferred_speed = int(preferences.get_value("game","speed",1))
		if not speed_values.has(preferred_speed):
			preferred_speed = 1
		preferred_wave_mode = clampi(int(preferences.get_value("game","wave_mode",0)),0,2)
		debug_enabled=bool(preferences.get_value("diagnostics","enabled",true))
		sound_enabled = bool(preferences.get_value("audio","enabled",true))
		music_volume = clampf(float(preferences.get_value("audio","volume",.55)),0,1)
		slot = clampi(int(preferences.get_value("game","last_slot",1)),1,5)
		# A legacy numeric selection has no stable ID. On the first 0.4.1
		# launch use the requested new title track; later explicit choices persist.
		music_index=0
		var track_id: String=str(preferences.get_value("audio","track_id","jazz_noir"))
		for i in TRACKS.size():
			if TRACKS[i].id==track_id:music_index=i
		var stored: Dictionary={}
		for key in preferred_rules:stored[key]=preferences.get_value("balance",key,1.0)
		preferred_rules=Simulation.clean_rules(stored)

func save_preferences() -> void:
	var preferences := ConfigFile.new()
	preferences.set_value("game","speed",preferred_speed)
	preferences.set_value("game","wave_mode",preferred_wave_mode)
	preferences.set_value("game","last_slot",slot)
	preferences.set_value("audio","enabled",sound_enabled)
	preferences.set_value("audio","volume",music_volume)
	preferences.set_value("audio","track",music_index)
	preferences.set_value("audio","track_id",TRACKS[music_index].id)
	for key in preferred_rules:preferences.set_value("balance",key,preferred_rules[key])
	preferences.set_value("diagnostics","enabled",debug_enabled)
	preferences.save(SaveStore.directory.path_join("preferences.cfg"))

func make_theme() -> Theme:
	var result := Theme.new()
	result.default_font_size = 24
	for type in ["Button","OptionButton"]:
		result.set_stylebox("normal",type,style("2b333c",14))
		result.set_stylebox("hover",type,style("364451",14,"77abc8"))
		result.set_stylebox("pressed",type,style("52788e",14,"a7d4e9"))
		result.set_stylebox("disabled",type,style("242a30",14))
		result.set_color("font_color",type,Color("e7edf2"))
		result.set_color("font_disabled_color",type,Color("66717b"))
		result.set_constant("outline_size",type,0)
	result.set_stylebox("panel","PanelContainer",style("252c33",22,"3b464f"))
	result.set_color("font_color","Label",Color("e3e9ee"))
	var thumb: Texture2D=load("res://assets/slider_thumb.svg")
	result.set_icon("grabber","HSlider",thumb)
	result.set_icon("grabber_highlight","HSlider",thumb)
	return result

func style(color: String, radius: int, border: String = "") -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = Color(color)
	result.set_corner_radius_all(radius)
	result.content_margin_left = 18
	result.content_margin_right = 18
	result.content_margin_top = 12
	result.content_margin_bottom = 12
	if not border.is_empty():
		result.border_color = Color(border)
		result.set_border_width_all(2)
	return result

func clear_screen() -> void:
	screen_name="other"
	screen_back=Callable()
	sheet_back=Callable()
	sheet_page=""
	exit_deadline_msec=0
	exit_hint=null
	hide_details()
	for child in get_children():
		if child == music:
			continue
		remove_child(child)
		child.queue_free()
	overlay = null
	sheet = null
	board = null
	game_visible = false
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var safe := DisplayServer.get_display_safe_area()
	var screen := DisplayServer.screen_get_size()
	var scale_y := size.y/maxf(1,float(screen.y))
	margin.add_theme_constant_override("margin_left",20)
	margin.add_theme_constant_override("margin_right",20)
	margin.add_theme_constant_override("margin_top",maxi(22,int(safe.position.y*scale_y)+12))
	margin.add_theme_constant_override("margin_bottom",maxi(22,int((screen.y-safe.end.y)*scale_y)+12))
	add_child(margin)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation",10)
	margin.add_child(body)

func label(text: String, font_size: int = 24, color: String = "e3e9ee") -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size",font_size)
	result.add_theme_color_override("font_color",Color(color))
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return result

func button(text: String, action: Callable, primary: bool = false, height: float = 76) -> Button:
	var result := Button.new()
	result.text = text
	result.custom_minimum_size.y = height
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result.pressed.connect(action)
	if primary:
		result.add_theme_stylebox_override("normal",style("73a6c3",14))
		result.add_theme_color_override("font_color",Color("10222f"))
	return result

func spacer(parent: Control, height: float = 0, expand: bool = false) -> void:
	var space := Control.new()
	space.custom_minimum_size.y = height
	if expand:
		space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(space)

func show_menu() -> void:
	clear_screen()
	screen_name="menu"
	spacer(body,30,true)
	var badge := Control.new()
	badge.custom_minimum_size.y = 190
	badge.draw.connect(func() -> void:
		GameBoard.tower_shape(badge,Vector2(130,110),"Minigun",48,10,true)
		GameBoard.tower_shape(badge,Vector2(335,85),"Laser",68,20,true,true)
		GameBoard.tower_shape(badge,Vector2(545,110),"Rocket",48,10,true)
	)
	body.add_child(badge)
	var title := label("GEOMETRY\nDEFENSE",62,"9ec4d9")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(title)
	var subtitle := label("Один путь. Тысячи решений.",24,"9daab5")
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(subtitle)
	spacer(body,24)
	var checkpoint := SaveStore.load_session(slot)
	if checkpoint.is_empty():
		checkpoint = SaveStore.load_slot(slot)
	var can_resume := sim != null and not sim.defeated
	var resume := button("Продолжить · слот %d" % slot,func() -> void:
		if can_resume:
			show_game()
		else:
			load_game(slot)
	,true,90)
	resume.disabled = not can_resume and checkpoint.is_empty()
	body.add_child(resume)
	body.add_child(button("Новая игра",func() -> void: show_slots(true)))
	body.add_child(button("Слоты сохранений",func() -> void: show_slots(false)))
	body.add_child(button("Как играть",show_help))
	body.add_child(button("Настройки",show_settings))
	spacer(body,24,true)
	exit_hint=label("Назад дважды — выйти",19,"7d8b96")
	exit_hint.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	exit_hint.custom_minimum_size.y=48
	body.add_child(exit_hint)
	var version := label("v0.4.1  ·  Android 16  ·  офлайн",19,"7d8b96")
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(version)

func show_slots(new_slot: bool) -> void:
	clear_screen()
	screen_back=show_menu
	body.add_child(label("НОВАЯ ИГРА" if new_slot else "СОХРАНЕНИЯ",36))
	body.add_child(label("Выберите один из пяти независимых слотов.",23,"a4b1bd"))
	for i in range(1,6):
		var state := SaveStore.load_slot(i)
		var caption := "Слот %d · пусто" % i if state.is_empty() else "Слот %d · волна %d\n♥ %d/10     ◆ %d" % [i,int(state.next_wave),int(state.base_hp),int(state.credits)]
		var existing := FileAccess.file_exists(SaveStore.path(i)) or FileAccess.file_exists(SaveStore.path(i)+".bak")
		if state.is_empty() and existing:
			caption = "Слот %d · повреждён или несовместим" % i
		var current_slot := i
		var entry := button(caption,func() -> void:
			if new_slot and existing:
				confirm_new_slot(current_slot)
			elif new_slot:
				new_game(current_slot)
			else:
				load_game(current_slot)
		,false,128)
		entry.disabled = not new_slot and state.is_empty() and not existing
		body.add_child(entry)
	spacer(body,0,true)
	body.add_child(button("Назад",show_menu))

func confirm_new_slot(index: int) -> void:
	var box := open_sheet(420)
	box.add_child(label("Заменить слот %d?" % index,32))
	box.add_child(label("Сохранение этого слота будет заменено новой игрой. Остальные слоты сохранятся.",24,"aab6c1"))
	box.add_child(button("Создать новую игру",func() -> void: new_game(index),true))
	box.add_child(button("Отмена",close_sheet))

func new_game(index: int) -> void:
	slot = index
	if sim!=null:sim.diagnostics.close()
	sim = Simulation.new(int(Time.get_unix_time_from_system())+index)
	sim.rules=preferred_rules.duplicate()
	setup_diagnostics()
	speed = preferred_speed
	wave_mode = preferred_wave_mode
	timer_remaining = 5.0
	paused = false
	accumulator = 0.0
	selected_id = -1
	selected = Vector2i(999,999)
	merge_source = -1
	shown_defeat = false
	SaveStore.clear_session(slot)
	show_game()
	save_preferences()
	checkpoint()
	save_session()

func checkpoint() -> void:
	if sim == null or sim.active or sim.defeated:
		return
	var state := sim.snapshot()
	state.slot = slot
	state.speed = speed
	state.wave_mode = wave_mode
	state.sound_enabled = sound_enabled
	checkpoint_error = SaveStore.save_slot(slot,state)
	if not checkpoint_error.is_empty():
		toast(checkpoint_error)

func load_game(index: int, checkpoint_only: bool = false) -> void:
	var state := {} if checkpoint_only else SaveStore.load_session(index)
	if state.is_empty():
		state = SaveStore.load_slot(index)
	var candidate := Simulation.new()
	if state.is_empty() or not candidate.restore(state):
		var box := open_sheet(420)
		box.add_child(label("Слот не удалось загрузить",30))
		box.add_child(label("Сохранение повреждено или несовместимо с текущей версией карты. Другие слоты доступны.",23))
		box.add_child(button("Закрыть",close_sheet))
		return
	slot = index
	if sim!=null:sim.diagnostics.close()
	sim = candidate
	setup_diagnostics()
	speed = int(state.get("speed",1))
	if not speed_values.has(speed):
		speed = 1
	wave_mode = clampi(int(state.get("wave_mode",0)),0,2)
	paused = bool(state.get("paused",false))
	accumulator = 0.0
	timer_remaining = float(state.get("timer_remaining",5.0))
	selected_id = -1
	selected = Vector2i(999,999)
	merge_source = -1
	shown_defeat = false
	show_game()
	save_preferences()

func show_game() -> void:
	clear_screen()
	game_visible = true
	var top := HBoxContainer.new()
	top.custom_minimum_size.y=44
	body.add_child(top)
	hud_hp = label("",26,"a8c8b4")
	hud_wave = label("",28)
	hud_credits = label("",26,"aacde0")
	for item in [hud_hp,hud_wave,hud_credits]:
		item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(item)
	hud_wave.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud_credits.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status_label = label("",19,"9dabb6")
	status_label.custom_minimum_size.y=42
	body.add_child(status_label)
	board = GameBoard.new()
	board.sim = sim
	board.selected = selected
	board.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board.cell_selected.connect(select_cell)
	board.tower_hold_started.connect(show_details)
	board.tower_hold_ended.connect(hide_details)
	body.add_child(board)
	var footer_slot:=Control.new()
	footer_slot.custom_minimum_size.y=200
	body.add_child(footer_slot)
	footer = VBoxContainer.new()
	footer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	footer.add_theme_constant_override("separation",6)
	footer_slot.add_child(footer)
	action_signature = ""
	refresh_actions(true)
	toast_label = label("Тап — выбор · удержание — характеристики",19,"afc0cd")
	toast_label.custom_minimum_size.y = 46
	body.add_child(toast_label)
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation",8)
	body.add_child(controls)
	pause_button = button("Ⅱ",toggle_pause,false,68)
	pause_button.custom_minimum_size.x = 68
	controls.add_child(pause_button)
	speed_button = button("×%d" % speed,cycle_speed,false,68)
	speed_button.custom_minimum_size.x = 76
	controls.add_child(speed_button)
	start_button = button("",start_wave,true,68)
	start_button.size_flags_stretch_ratio = 2.5
	controls.add_child(start_button)
	countdown=WaveCountdown.new()
	controls.add_child(countdown)
	controls.add_child(button("⚙",show_game_menu,false,68))
	update_hud()

func update_hud() -> void:
	if not game_visible or sim == null:
		return
	hud_hp.text = "♥ %d/10" % sim.base_hp
	hud_wave.text = "Волна %d" % sim.next_wave
	hud_credits.text = "◆ %s" % format_number(sim.credits)
	pause_button.text = "▶" if paused else "Ⅱ"
	speed_button.text = "×%d" % speed
	start_button.text = "Волна идёт" if sim.active else "Начать %d" % sim.next_wave
	start_button.disabled = sim.active or sim.defeated
	if is_instance_valid(countdown):
		countdown.visible=not sim.active and not sim.defeated and wave_mode>0
		countdown.remaining=timer_remaining
		countdown.queue_redraw()
	var mode: String = ["вручную","авто","таймер"][wave_mode]
	if sim.next_wave % 5 == 0:
		var boss := Balance.boss(sim.next_wave)
		status_label.text = "%s босс · иммунитет: %s" % [boss.name,Balance.tower(boss.immune).name]
	else:
		status_label.text = "Врагов: %d  ·  запуск: %s%s" % [sim.enemies.size()+sim.spawn_queue.size(),mode,"  ·  ПАУЗА" if paused else ""]
	if not sim.active and wave_mode > 0:
		status_label.text += "  ·  %.1f с" % maxf(0,timer_remaining)

func format_number(value: int) -> String:
	return "%.1fM" % (value/1000000.0) if value >= 1000000 else "%.1fK" % (value/1000.0) if value >= 10000 else str(value)

func _process(delta: float) -> void:
	if exit_deadline_msec>0 and Time.get_ticks_msec()>exit_deadline_msec:
		exit_deadline_msec=0
		if is_instance_valid(exit_hint):exit_hint.text="Назад дважды — выйти"
	if sim!=null:
		for error in error_logger.drain():sim.diagnostics.issue("ENGINE_ERROR",sim.time,error,error.get("stack",[]))
	if not game_visible or sim == null:
		return
	sim.diagnostics.frame(speed)
	if paused:
		for t in sim.towers:sim.diagnostics.idle(t,"PAUSED",delta,sim.time)
	if not paused and not sim.defeated:
		accumulator += minf(delta,.25)*speed
		var steps := 0
		while accumulator + .000000001 >= float(Balance.cfg.fixed_step) and steps < 120:
			sim.step(Balance.cfg.fixed_step)
			accumulator = maxf(0,accumulator-float(Balance.cfg.fixed_step))
			steps += 1
	var completed_now := sim.finished_event
	if completed_now:
		sim.finished_event = false
		checkpoint()
		timer_remaining = 5.0
		save_session()
		toast("Волна завершена · сохранено" if checkpoint_error.is_empty() else checkpoint_error)
	if not completed_now and not sim.active and not sim.defeated and not paused and wave_mode > 0 and overlay == null:
		timer_remaining -= delta
		if timer_remaining <= 0:
			start_wave()
	if sim.defeated and not shown_defeat:
		shown_defeat = true
		SaveStore.clear_session(slot)
		show_defeat()
	toast_timer -= delta
	if toast_timer <= 0 and is_instance_valid(toast_label):
		toast_label.text = "Тап — выбор · удержание — характеристики"
	ui_timer += delta
	session_timer += delta
	if ui_timer >= .1:
		ui_timer = 0
		update_hud()
		refresh_actions()
	if session_timer >= 3:
		session_timer = 0
		save_session()
	if is_instance_valid(board):
		board.interpolation = 1.0 if paused else clampf(accumulator/float(Balance.cfg.fixed_step),0,1)
		board.queue_redraw()

func toast(text: String) -> void:
	if toast_label != null and is_instance_valid(toast_label):
		toast_label.text = text
	toast_timer = 4.0

func start_wave() -> void:
	close_sheet()
	if sim.start_wave():
		toast("Волна %d началась" % sim.next_wave)
	update_hud()

func toggle_pause() -> void:
	paused = not paused
	sim.diagnostics.action("pause" if paused else "resume",sim.time,{"speed":speed})
	save_session()
	update_hud()

func cycle_speed() -> void:
	speed = speed_values[(speed_values.find(speed)+1)%speed_values.size()]
	sim.diagnostics.action("speed",sim.time,{"speed":speed})
	update_hud()

func open_sheet(height: float) -> VBoxContainer:
	close_sheet()
	sheet_back=close_sheet
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	var shade := ColorRect.new()
	shade.color = Color(0,0,0,0.48)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	shade.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			close_sheet()
	)
	overlay.add_child(shade)
	sheet = PanelContainer.new()
	sheet.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	sheet.offset_top = -minf(height,size.y-60)
	sheet.offset_left = 12
	sheet.offset_right = -12
	sheet.offset_bottom = -16
	overlay.add_child(sheet)
	var scroll := GestureScroll.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sheet.add_child(scroll)
	var box := VBoxContainer.new()
	box.mouse_filter=Control.MOUSE_FILTER_STOP
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation",14)
	scroll.add_child(box)
	return box

func close_sheet() -> void:
	sheet_back=Callable()
	sheet_page=""
	if overlay != null and is_instance_valid(overlay):
		remove_child(overlay)
		overlay.queue_free()
	overlay = null
	sheet = null

func select_cell(cell: Vector2i) -> void:
	if sim.defeated:
		return
	selected = cell
	board.selected = cell
	sim.diagnostics.action("tower_select",sim.time,{"cell":cell,"tower_id":sim.tower_at(cell).get("id",-1)})
	var t := sim.tower_at(cell)
	if merge_source >= 0:
		if not t.is_empty() and t.id != merge_source:
			var result := sim.merge(merge_source,t.id)
			toast("Слияние: 5 игровых секунд" if result.is_empty() else result)
		merge_source = -1
		board.merge_source = -1
	selected_id = -1 if t.is_empty() else int(t.id)
	refresh_actions(true)
	update_hud()
	save_session()

func show_build(cell: Vector2i) -> void:
	selected = cell
	selected_id = -1
	refresh_actions(true)

func show_tower(id: int) -> void:
	selected_id = id
	refresh_actions(true)

func show_game_menu() -> void:
	var box := open_sheet(980)
	sheet_page="game_menu"
	box.add_child(label("Управление игрой",33))
	box.add_child(label("Слот %d · сохранение после каждой волны" % slot,21,"a3b3be"))
	box.add_child(button("Пауза / продолжить",func() -> void: toggle_pause(); close_sheet()))
	var save := button("Сохранить чекпоинт",func() -> void:
		checkpoint()
		toast("Сохранено" if checkpoint_error.is_empty() else checkpoint_error)
		close_sheet()
	)
	save.disabled = sim.active or sim.defeated
	box.add_child(save)
	var mode := OptionButton.new()
	mode.action_mode=BaseButton.ACTION_MODE_BUTTON_RELEASE
	mode.custom_minimum_size.y = 76
	for text in ["Волны: вручную","Волны: автоматически","Волны: таймер 5 секунд"]:
		mode.add_item(text)
	mode.select(wave_mode)
	mode.item_selected.connect(func(index: int) -> void:
		wave_mode = index
		timer_remaining = 5.0
		update_hud()
	)
	box.add_child(mode)
	box.add_child(button("Маршрут: %s" % ("показан" if board.show_route else "скрыт"),func() -> void: board.show_route = not board.show_route; close_sheet()))
	box.add_child(button("Координаты клеток / отладка",func() -> void: board.debug_grid = not board.debug_grid; close_sheet()))
	box.add_child(button("Настройки: игра, баланс, музыка",func() -> void: show_settings_hub(true)))
	box.add_child(button("Диагностика",show_diagnostics))
	box.add_child(button("Каталог башен",show_catalog))
	box.add_child(button("Статистика",show_statistics))
	box.add_child(button("Отменить выбор слияния",func() -> void:
		merge_source = -1
		board.merge_source = -1
		close_sheet()
	))
	box.add_child(button("Главное меню",func() -> void:
		save_session()
		show_menu()
	))
	box.add_child(button("Закрыть",close_sheet))

func show_statistics() -> void:
	var box := open_sheet(size.y-70)
	sheet_back=show_game_menu
	box.add_child(label("Статистика",34))
	box.add_child(label("Убито: %d   ·   урон: %s\nПолучено: ◆ %s   ·   потрачено: ◆ %s" % [sim.total_kills,format_number(int(sim.total_damage)),format_number(sim.total_earned),format_number(sim.total_spent)],24))
	box.add_child(label("Башни",29,"93bcd3"))
	for id in sim.tower_history:
		var t: Dictionary = sim.tower_history[id]
		var efficiency: float = t.damage/maxf(1,t.invested)
		box.add_child(label("№%s %s%s · %s\nУрон %s · убийств %d · ◆ %d · урон/◆ %.2f\nЭффекты ультимейта: %d%s" % [id,Balance.tower(t.kind).name," MEGA" if t.mega else "",{"active":"на поле","sold":"продана","merged":"слита"}.get(t.status,t.status),format_number(int(t.damage)),t.kills,t.invested,efficiency,t.ultimate_hits,"\nИсточники: %s" % str(t.parents) if not t.parents.is_empty() else ""],21,"b2c0ca"))
	box.add_child(label("История волн",29,"93bcd3"))
	for i in range(sim.history.size()-1,-1,-1):
		var row: Dictionary = sim.history[i]
		box.add_child(label("Волна %d · убито %d · прошли %d · ♥ %d\n◆ +%d / −%d · %.1f с · урон %s\n%s" % [row.wave,row.killed,row.leaked,row.hp_end,row.earned,row.spent,row.seconds,format_number(int(row.damage)),format_composition(row.composition)],21,"aab9c4"))
	box.add_child(button("Закрыть",close_sheet))

func format_composition(composition: Dictionary) -> String:
	var names := {"normal":"обычные","fast":"быстрые","split":"делящиеся","child":"малые круги","boss":"босс"}
	var parts: PackedStringArray = []
	for kind in composition:
		parts.append("%s: %d" % [names.get(kind,kind),composition[kind]])
	return ", ".join(parts)

func show_defeat() -> void:
	var box := open_sheet(650)
	sheet_back=show_menu
	box.add_child(label("База потеряна",42,"dda3a3"))
	box.add_child(label("Волна %d · убито %d врагов.\nПоследний успешный чекпоинт сохранён." % [sim.next_wave,sim.total_kills],26))
	var resume := button("Восстановить чекпоинт",func() -> void: load_game(slot,true),true,90)
	resume.disabled = SaveStore.load_slot(slot).is_empty()
	box.add_child(resume)
	box.add_child(button("Посмотреть статистику",show_statistics))
	box.add_child(button("Главное меню",show_menu))
	box.add_child(button("Новая игра",func() -> void: confirm_new_slot(slot)))

func show_help() -> void:
	clear_screen()
	screen_back=show_menu
	body.add_child(label("Как играть",38))
	var scroll := GestureScroll.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	var text := label("Враги идут от красного входа к фиолетовой базе по кратчайшему открытому пути.\n\nСтройте на чёрных клетках. Башня перекрывает свою клетку: маршрут перестроится. Полностью закрыть проход или замуровать врага нельзя.\n\nМиниган — быстрый одиночный огонь.\nЛазер — пробивающий луч через всех на линии.\nРакета — взрыв по площади.\nУдарная волна — импульс вокруг башни.\n\nТап по башне: действия снизу. Удержание: характеристики. Единый уровень 1–10. Улучшение и установка ульты занимают 3 игровые секунды. Ульта покупается отдельно на 10-м уровне. Слияние двух соседних башен одного класса с установленными ультами занимает 5 секунд. Пока идёт установка, башня не стреляет.\n\nБашни сами выбирают ближайшего к ним врага. У каждого пятого босса иммунитет к одному классу:\n5 — белый, Миниган;\n10 — зелёный, Лазер;\n15 — красный, Ракета;\n20 — синий, Ударная волна.\nЗатем цикл повторяется.\n\nБаза: 10 HP. Каждый прошедший враг снимает 1 HP. Продажа возвращает 70% вложений.\n\nНа паузе можно строить, улучшать, продавать и сливать. Скорости: ×1, ×2, ×3, ×5.\n\nПосле каждой волны игра автоматически сохраняется в выбранный слот. При поражении можно вернуться к чекпоинту. Ручное сохранение — между волнами.\n\nВся игра работает офлайн. Баланс C1: 100 волн, 3 типа врагов и 4 босса. Диагностика и экспорт отчёта доступны в игровом меню.",24,"bdc9d3")
	text.custom_minimum_size.x = 630
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(text)
	body.add_child(button("Назад",show_menu))

func show_settings() -> void:
	show_settings_hub(false)

func settings_box(title: String) -> VBoxContainer:
	var box: VBoxContainer
	if settings_in_game:
		box=open_sheet(size.y-100)
	else:
		clear_screen()
		var scroll:=GestureScroll.new()
		scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
		scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
		body.add_child(scroll)
		box=VBoxContainer.new()
		box.mouse_filter=Control.MOUSE_FILTER_STOP
		box.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		box.add_theme_constant_override("separation",16)
		scroll.add_child(box)
	box.add_child(label(title,36))
	return box

func show_settings_hub(in_game: bool = false) -> void:
	settings_in_game=in_game
	settings_page="hub"
	var box:=settings_box("Настройки")
	if in_game:sheet_back=show_game_menu
	else:screen_back=show_menu
	box.add_child(label("Для текущего слота" if in_game else "Для новых игр",23,"a6b8c8"))
	box.add_child(button("Игра · скорость и волны",func() -> void: show_settings_page("game")))
	box.add_child(button("Сложность · плотность и HP",func() -> void: show_settings_page("difficulty")))
	box.add_child(button("Экономика · деньги за врагов",func() -> void: show_settings_page("economy")))
	box.add_child(button("Музыка · трек и громкость",func() -> void: show_settings_page("audio")))
	box.add_child(button("Назад",show_game_menu if in_game else show_menu))

func settings_rules() -> Dictionary:
	return sim.rules if settings_in_game and sim!=null else preferred_rules

func change_rule(key: String, value: float) -> void:
	settings_rules()[key]=value
	if settings_in_game:
		sim.diagnostics.action("balance_setting",sim.time,{"key":key,"value":value,"applies":"next_wave"})
		# Session autosave and lifecycle saves persist this without writing a full
		# match JSON at every pixel of a slider drag.
	else:save_preferences()

func percentage_slider(parent: Control, caption: String, key: String, low: float, high: float, step_value: float, offset: bool = false) -> void:
	var current: float=settings_rules()[key]*100-(100 if offset else 0)
	var text:=label("",25,"a6c8da")
	var describe:=func(value: float) -> void:
		text.text="%s: %s%d%%"%[caption,"+" if offset and value>0 else "",roundi(value)]
	describe.call(current)
	parent.add_child(text)
	var slider:=HSlider.new()
	slider.name="Setting_"+key
	slider.min_value=low;slider.max_value=high;slider.step=step_value;slider.value=current
	slider.custom_minimum_size.y=64
	slider.value_changed.connect(func(value: float) -> void:
		describe.call(value)
		change_rule(key,(value+(100 if offset else 0))/100.0)
	)
	parent.add_child(slider)
	var limits:=HBoxContainer.new()
	var low_label:=label("%d%%"%int(low),19,"8b9dab")
	low_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	limits.add_child(low_label)
	var high_label:=label("%s%d%%"%["+" if offset else "",int(high)],19,"8b9dab")
	high_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	high_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	limits.add_child(high_label)
	parent.add_child(limits)

func show_settings_page(page: String) -> void:
	settings_page=page
	var names: Dictionary={"game":"Игра","difficulty":"Сложность","economy":"Экономика","audio":"Музыка"}
	var box:=settings_box(names[page])
	var back_to_hub:=func() -> void:show_settings_hub(settings_in_game)
	if settings_in_game:sheet_back=back_to_hub
	else:screen_back=back_to_hub
	if page=="game":
		box.add_child(label("Скорость боя",25,"a6c8da"))
		var speed_choice:=OptionButton.new()
		speed_choice.action_mode=BaseButton.ACTION_MODE_BUTTON_RELEASE
		speed_choice.custom_minimum_size.y=80
		for value in speed_values:speed_choice.add_item("×%d"%value)
		speed_choice.select(speed_values.find(speed if settings_in_game else preferred_speed))
		speed_choice.item_selected.connect(func(index: int) -> void:
			if settings_in_game:speed=speed_values[index];save_session();update_hud()
			else:preferred_speed=speed_values[index];save_preferences()
		)
		box.add_child(speed_choice)
		box.add_child(label("Запуск волн",25,"a6c8da"))
		var mode:=OptionButton.new()
		mode.action_mode=BaseButton.ACTION_MODE_BUTTON_RELEASE
		mode.custom_minimum_size.y=80
		for text in ["Вручную","Авто · пауза 5 секунд","Таймер · пауза 5 секунд"]:mode.add_item(text)
		mode.select(wave_mode if settings_in_game else preferred_wave_mode)
		mode.item_selected.connect(func(index: int) -> void:
			if settings_in_game:wave_mode=index;timer_remaining=5.0;save_session();update_hud()
			else:preferred_wave_mode=index;save_preferences()
		)
		box.add_child(mode)
		box.add_child(label("Между автоволнами — 5 обычных секунд при любой скорости боя. Пауза и открытое меню останавливают отсчёт.",23,"a8b9c6"))
	elif page=="difficulty":
		box.add_child(label("Базовый баланс C1 · 100 волн",24,"a8b9c6"))
		percentage_slider(box,"Сложность · плотность потока","pressure",75,150,5)
		box.add_child(label("100% — стандарт. Выше — враги выходят чаще; их число, скорость и награда за волну сохраняются.",22,"a8b9c6"))
		percentage_slider(box,"HP врагов от нового стандарта","hp",-30,100,1,true)
		box.add_child(label("0% — новое стандартное HP. −30% = ×0,70; +100% = ×2,00. Боссы и дочерние круги учитывают настройку.",22,"a8b9c6"))
		box.add_child(button("Стандартная сложность",func() -> void:
			change_rule("pressure",1.0);change_rule("hp",1.0);show_settings_page("difficulty")
		))
	elif page=="economy":
		percentage_slider(box,"Деньги за побеждённого врага","money",25,300,5)
		box.add_child(label("100% — стандартная награда. Учитываются обычные враги, боссы и дочерние круги. Округление до целого, минимум 1 кредит за врага. Бонус за завершение волны остаётся прежним.",23,"a8b9c6"))
		box.add_child(button("Стандартная экономика",func() -> void:
			change_rule("money",1.0);show_settings_page("economy")
		))
	elif page=="audio":
		add_audio_controls(box)
	if page in ["difficulty","economy"]:
		box.add_child(label("Изменения применяются со следующей волны и сохраняются в этом слоте." if settings_in_game else "Эти значения будут использованы в новых играх. Текущие слоты настраиваются через игровое меню.",22,"8fa8bb"))
	box.add_child(button("Назад к разделам",func() -> void: show_settings_hub(settings_in_game)))

# Returns true only for a confirmed exit from the main menu. Separating the
# decision from quit() also lets tests exercise both gestures without exiting.
func request_back(now_msec: int = -1) -> bool:
	var now:=Time.get_ticks_msec() if now_msec<0 else now_msec
	if overlay!=null and is_instance_valid(overlay):
		var action:=sheet_back
		if action.is_valid():action.call()
		else:close_sheet()
		return false
	if screen_back.is_valid():
		var action:=screen_back
		action.call()
		return false
	if game_visible:
		paused=true
		save_session()
		show_menu()
		return false
	if screen_name!="menu":
		show_menu()
		return false
	if exit_deadline_msec>0 and now<=exit_deadline_msec:
		exit_deadline_msec=0
		save_session()
		return true
	exit_deadline_msec=now+EXIT_WINDOW_MSEC
	if is_instance_valid(exit_hint):
		exit_hint.text="Ещё раз «Назад» в течение 2 секунд — выйти"
	return false

func _notification(what: int) -> void:
	if what==NOTIFICATION_WM_GO_BACK_REQUEST:
		if request_back():get_tree().quit()
	elif what==NOTIFICATION_WM_CLOSE_REQUEST:
		save_session()
		get_tree().quit()
	elif what==NOTIFICATION_APPLICATION_PAUSED or what==NOTIFICATION_APPLICATION_FOCUS_OUT:
		exit_deadline_msec=0
		if is_instance_valid(music):music.stream_paused=true
		if game_visible:paused=true
		save_session()
	elif what==NOTIFICATION_APPLICATION_RESUMED or what==NOTIFICATION_APPLICATION_FOCUS_IN:
		if is_instance_valid(music):music.stream_paused=false


func refresh_actions(force: bool = false) -> void:
	if not is_instance_valid(footer):
		return
	var t := sim.tower_at(selected)
	if not t.is_empty():
		selected_id = t.id
	var signature := str(selected)+str(sim.credits)+str(merge_source)
	if not t.is_empty():
		signature += str(t.id)+str(t.level)+str(t.ultimate)+str(t.mega)+str(t.job)+str(ceili(t.job_left))
	if not force and signature == action_signature:
		return
	action_signature = signature
	for child in footer.get_children():
		footer.remove_child(child)
		child.queue_free()
	if not t.is_empty():
		var caption := "%s · ур. %d%s" % [Balance.tower(t.kind).name,t.level," · MEGA" if t.mega else " · ульта" if t.ultimate else ""]
		if not t.job.is_empty():
			caption += " · %s %.0f с" % [{"upgrade":"улучшение","ultimate":"установка ульты","merge":"слияние"}[t.job],ceil(t.job_left)]
		footer.add_child(label(caption,21,Balance.tower(t.kind).color))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation",10)
		footer.add_child(row)
		var id: int = t.id
		row.add_child(button("Продать +%d" % int(floor(t.invested*Balance.cfg.sell_ratio)),func() -> void:
			sim.sell(id)
			selected_id = -1
			refresh_actions(true)
			update_hud()
			save_session()
		,false,64))
		var cost := Balance.upgrade_cost(t.kind,t.level+1) if t.level < 10 else Balance.ultimate_cost(t.kind)
		var action := "Улучшить · %d" % cost if t.level < 10 else "Ульта · %d" % cost
		if t.ultimate:
			action = "Слить" if not t.mega else "MEGA"
		if not t.job.is_empty():
			action = "Установка…"
		var entry := button(action,func() -> void:
			var error := ""
			if t.level < 10:
				error = sim.upgrade(id)
			elif not t.ultimate:
				error = sim.buy_ultimate(id)
			else:
				merge_source = id
				board.merge_source = id
				toast("Выберите соседнюю башню того же класса с ультой")
			if not error.is_empty():
				toast(error)
			refresh_actions(true)
			update_hud()
			save_session()
		,true,64)
		entry.disabled = not t.job.is_empty() or t.mega or (not t.ultimate and sim.credits < cost)
		row.add_child(entry)
		if t.job == "merge":
			footer.add_child(button("Отменить слияние",func() -> void:
				sim.cancel_merge(id)
				refresh_actions(true)
				save_session()
			,false,50))
	elif sim.map.cells.has(selected) and selected != sim.map.spawn and selected != sim.map.goal:
		footer.add_child(label("Построить башню",21))
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation",8)
		grid.add_theme_constant_override("v_separation",6)
		footer.add_child(grid)
		for kind in Balance.KINDS:
			var k: String = kind
			var data := Balance.tower(k)
			var entry := button("%s · %d" % [data.name,data.price],func() -> void:
				var error := sim.build(selected,k)
				if not error.is_empty():
					toast(error)
				refresh_actions(true)
				update_hud()
				save_session()
			,false,62)
			entry.add_theme_font_size_override("font_size",21)
			entry.add_theme_color_override("font_color",Color(data.color))
			entry.disabled = sim.credits < data.price
			grid.add_child(entry)
	else:
		footer.add_child(label("Выберите клетку для постройки",21,"99acba"))

func show_details(id: int) -> void:
	hide_details()
	var t := sim.find_tower(id)
	if t.is_empty():
		return
	details = PanelContainer.new()
	details.mouse_filter = Control.MOUSE_FILTER_IGNORE
	details.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	details.offset_top = 110
	details.offset_left = 28
	details.offset_right = -28
	add_child(details)
	var cost := Balance.upgrade_cost(t.kind,t.level+1) if t.level < 10 else Balance.ultimate_cost(t.kind)
	var info := label("%s · уровень %d%s\nУрон %.1f · %.2f атак/с · залп %d\nРадиус %.2f гекса · вложено %d\nУльта: %s · следующая покупка %d%s" % [Balance.tower(t.kind).name,t.level," · MEGA" if t.mega else "",Balance.damage(t),Balance.rate(t),Balance.volley(t),Balance.reach(t),t.invested,"установлена" if t.ultimate else "доступна на ур. 10",cost,"\nУстановка: %.1f игровых секунд" % t.job_left if not t.job.is_empty() else ""],22)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	details.add_child(info)

func hide_details() -> void:
	if is_instance_valid(details):
		details.queue_free()
	details = null

func setup_music() -> void:
	music = AudioStreamPlayer.new()
	music.name = "BackgroundMusic"
	if ResourceLoader.exists(TRACKS[music_index].path):
		music.stream = load(TRACKS[music_index].path)
	add_child(music)
	apply_audio()
	if music.stream != null:
		music.play()

func select_music(index: int) -> void:
	music_index=clampi(index,0,TRACKS.size()-1)
	if is_instance_valid(music):
		music.stop()
		music.stream=load(TRACKS[music_index].path)
		music.play()
		apply_audio()
	save_preferences()

func apply_audio() -> void:
	if is_instance_valid(music):
		music.volume_db = linear_to_db(maxf(.0001,music_volume))
		AudioServer.set_bus_mute(0,not sound_enabled or music_volume <= .001)

func add_audio_controls(parent: Control) -> void:
	parent.add_child(label("Фоновая песня",25,"a6c8da"))
	var tracks:=OptionButton.new()
	tracks.name="MusicTracks"
	tracks.action_mode=BaseButton.ACTION_MODE_BUTTON_RELEASE
	tracks.custom_minimum_size.y=84
	for track in TRACKS:tracks.add_item(track.title)
	tracks.select(music_index)
	tracks.item_selected.connect(select_music)
	parent.add_child(tracks)
	var mute := CheckButton.new()
	mute.action_mode=BaseButton.ACTION_MODE_BUTTON_RELEASE
	mute.text = "Фоновая музыка"
	mute.button_pressed = sound_enabled
	mute.toggled.connect(func(value: bool) -> void:
		sound_enabled = value
		apply_audio()
		save_preferences()
	)
	parent.add_child(mute)
	var volume_label:=label("Громкость: %d%%"%roundi(music_volume*100),24,"a6c8da")
	parent.add_child(volume_label)
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.value = music_volume*100
	slider.custom_minimum_size.y = 48
	slider.value_changed.connect(func(value: float) -> void:
		music_volume = value/100
		volume_label.text="Громкость: %d%%"%roundi(value)
		apply_audio()
		save_preferences()
	)
	parent.add_child(slider)

func save_session() -> void:
	if sim == null or sim.defeated:
		return
	var state := sim.snapshot(true)
	state.slot = slot
	state.speed = speed
	state.wave_mode = wave_mode
	state.paused = paused
	state.timer_remaining = timer_remaining
	sim.diagnostics.emit("save",sim.time,{"active":sim.active,"slot":slot,"schema":3})
	var error := SaveStore.save_session(slot,state)
	if not error.is_empty():
		toast(error)

func _exit_tree() -> void:
	if error_logger!=null:OS.remove_logger(error_logger)
	if sim!=null:sim.diagnostics.close()
	if is_instance_valid(music):
		music.stop()
		music.stream = null

func setup_diagnostics() -> void:
	sim.diagnostics.enabled=debug_enabled
	sim.diagnostics.attach(SaveStore.directory.path_join("diagnostics"))
	error_logger.directory=SaveStore.directory.path_join("diagnostics") if debug_enabled else ""
	sim.diagnostics.metadata.config_sha256=FileAccess.get_sha256("res://data/balance.json")

func show_diagnostics() -> void:
	var box:=open_sheet(780)
	sheet_page="diagnostics"
	sheet_back=show_game_menu
	box.add_child(label("Диагностика",34))
	box.add_child(label("Отчёт содержит события боя, причины простоя, урон, баланс и ошибки. Личные данные и сохранения в архив не входят.",22,"a8bac8"))
	var toggle:=CheckButton.new()
	toggle.action_mode=BaseButton.ACTION_MODE_BUTTON_RELEASE
	toggle.text="Записывать диагностику"
	toggle.button_pressed=debug_enabled
	toggle.toggled.connect(func(value: bool) -> void:
		debug_enabled=value;sim.diagnostics.enabled=value;save_preferences()
		error_logger.directory=SaveStore.directory.path_join("diagnostics") if value else ""
	)
	box.add_child(toggle)
	var rings:=CheckButton.new()
	rings.action_mode=BaseButton.ACTION_MODE_BUTTON_RELEASE
	rings.text="Радиусы 1R…5R и расстояние до цели"
	rings.button_pressed=board.diagnostic_rings
	rings.toggled.connect(func(value: bool) -> void:board.diagnostic_rings=value)
	box.add_child(rings)
	box.add_child(label("Событий: %d · предупреждений: %d\nБаланс %s · seed %s"%[sim.diagnostics.sequence,sim.diagnostics.warnings.size(),Balance.cfg.balance_id,str(sim.rng.seed)],22))
	box.add_child(button("Экспорт отчёта",export_diagnostics,true))
	box.add_child(button("Каталог башен",show_catalog))
	box.add_child(button("Закрыть",close_sheet))

func export_diagnostics() -> void:
	var path:=sim.diagnostics.export_zip(sim)
	if path.is_empty():
		toast("Не удалось создать архив отчёта")
		return
	if OS.get_name()=="Android":
		if Engine.has_singleton("ReportShare"):
			var error: String=Engine.get_singleton("ReportShare").shareReport(path)
			toast("Выберите, куда отправить ZIP" if error.is_empty() else error)
		else:toast("Модуль экспорта Android недоступен")
	else:
		OS.shell_show_in_file_manager(path)
		toast("ZIP отчёта создан: "+path)

func show_catalog() -> void:
	var from_diagnostics:=sheet_page=="diagnostics"
	var box:=open_sheet(940)
	sheet_back=show_diagnostics if from_diagnostics else show_game_menu
	box.add_child(label("Каталог башен",32))
	box.add_child(label("Уровни 1 · 5 · 10 · MEGA",21,"a9bac6"))
	var catalog:=TowerCatalog.new()
	catalog.custom_minimum_size=Vector2(580,620)
	box.add_child(catalog)
	box.add_child(button("Закрыть",close_sheet))
