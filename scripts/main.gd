extends Control

var debug_enabled:=true
var error_logger: EngineErrorLogger
var music: AudioStreamPlayer
var music_volume := .55
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

func save_preferences() -> void:
	var preferences := ConfigFile.new()
	preferences.set_value("game","speed",preferred_speed)
	preferences.set_value("game","wave_mode",preferred_wave_mode)
	preferences.set_value("game","last_slot",slot)
	preferences.set_value("audio","enabled",sound_enabled)
	preferences.set_value("audio","volume",music_volume)
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
	var version := label("v0.3.0  ·  Android 16  ·  офлайн",19,"7d8b96")
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(version)

func show_slots(new_slot: bool) -> void:
	clear_screen()
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
	setup_diagnostics()
	speed = preferred_speed
	wave_mode = preferred_wave_mode
	timer_remaining = 1.2 if wave_mode == 1 else 5.0
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
	if sim.finished_event:
		sim.finished_event = false
		checkpoint()
		timer_remaining = 1.2 if wave_mode == 1 else 5.0
		save_session()
		toast("Волна завершена · сохранено" if checkpoint_error.is_empty() else checkpoint_error)
	if not sim.active and not sim.defeated and not paused and wave_mode > 0 and overlay == null:
		timer_remaining -= delta*speed
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
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sheet.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation",14)
	scroll.add_child(box)
	return box

func close_sheet() -> void:
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
	mode.custom_minimum_size.y = 76
	for text in ["Волны: вручную","Волны: автоматически","Волны: таймер 5 секунд"]:
		mode.add_item(text)
	mode.select(wave_mode)
	mode.item_selected.connect(func(index: int) -> void:
		wave_mode = index
		timer_remaining = 1.2 if index == 1 else 5.0
		update_hud()
	)
	box.add_child(mode)
	box.add_child(button("Маршрут: %s" % ("показан" if board.show_route else "скрыт"),func() -> void: board.show_route = not board.show_route; close_sheet()))
	box.add_child(button("Координаты клеток / отладка",func() -> void: board.debug_grid = not board.debug_grid; close_sheet()))
	add_audio_controls(box)
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
	body.add_child(label("Как играть",38))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	var text := label("Враги идут от красного входа к фиолетовой базе по кратчайшему открытому пути.\n\nСтройте на чёрных клетках. Башня перекрывает свою клетку: маршрут перестроится. Полностью закрыть проход или замуровать врага нельзя.\n\nМиниган — быстрый одиночный огонь.\nЛазер — пробивающий луч через всех на линии.\nРакета — взрыв по площади.\nУдарная волна — импульс вокруг башни.\n\nТап по башне: действия снизу. Удержание: характеристики. Единый уровень 1–10. Улучшение и установка ульты занимают 3 игровые секунды. Ульта покупается отдельно на 10-м уровне. Слияние двух соседних башен одного класса с установленными ультами занимает 5 секунд. Пока идёт установка, башня не стреляет.\n\nБашни сами выбирают ближайшего к ним врага. У каждого пятого босса иммунитет к одному классу:\n5 — белый, Миниган;\n10 — зелёный, Лазер;\n15 — красный, Ракета;\n20 — синий, Ударная волна.\nЗатем цикл повторяется.\n\nБаза: 10 HP. Каждый прошедший враг снимает 1 HP. Продажа возвращает 70% вложений.\n\nНа паузе можно строить, улучшать, продавать и сливать. Скорости: ×1, ×2, ×3, ×5.\n\nПосле каждой волны игра автоматически сохраняется в выбранный слот. При поражении можно вернуться к чекпоинту. Ручное сохранение — между волнами.\n\nВся игра работает офлайн. Баланс B1 provisional: 100 волн, 3 типа врагов и 4 босса. Диагностика и экспорт отчёта доступны в игровом меню.",24,"bdc9d3")
	text.custom_minimum_size.x = 630
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(text)
	body.add_child(button("Назад",show_menu))

func show_settings() -> void:
	clear_screen()
	body.add_child(label("Настройки",38))
	body.add_child(label("Настройки новых игр. Каждый сохранённый слот хранит собственную скорость и режим волн.",25,"b0bec9"))
	spacer(body,20)
	body.add_child(label("Начальная скорость",27,"a6c8da"))
	var speed_choice := OptionButton.new()
	speed_choice.custom_minimum_size.y = 84
	for value in speed_values:
		speed_choice.add_item("×%d" % value)
	speed_choice.select(speed_values.find(preferred_speed))
	speed_choice.item_selected.connect(func(index: int) -> void:
		preferred_speed = speed_values[index]
		save_preferences()
	)
	body.add_child(speed_choice)
	body.add_child(label("Запуск волн",27,"a6c8da"))
	var wave_choice := OptionButton.new()
	wave_choice.custom_minimum_size.y = 84
	for text in ["Вручную","Автоматически","По таймеру: 5 секунд"]:
		wave_choice.add_item(text)
	wave_choice.select(preferred_wave_mode)
	wave_choice.item_selected.connect(func(index: int) -> void:
		preferred_wave_mode = index
		save_preferences()
	)
	body.add_child(wave_choice)
	spacer(body,20)
	body.add_child(label("Скорость и режим можно менять во время игры.\nИгра полностью офлайн.\n\nФоновая музыка: Барабанщики. Громкость регулируется ниже.",24,"a6b5c0"))
	spacer(body,0,true)
	add_audio_controls(body)
	body.add_child(button("Назад",show_menu))

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST or what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_session()
		if overlay != null:
			close_sheet()
		elif game_visible:
			paused = true
			show_game_menu()
		else:
			get_tree().quit()
	elif what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if is_instance_valid(music):
			music.stream_paused = true
		save_session()
		if game_visible:
			paused = true
	elif what == NOTIFICATION_APPLICATION_RESUMED or what == NOTIFICATION_APPLICATION_FOCUS_IN:
		if is_instance_valid(music):
			music.stream_paused = false


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
	if ResourceLoader.exists("res://assets/audio/background.ogg"):
		music.stream = load("res://assets/audio/background.ogg")
	add_child(music)
	apply_audio()
	if music.stream != null:
		music.play()

func apply_audio() -> void:
	if is_instance_valid(music):
		music.volume_db = linear_to_db(maxf(.0001,music_volume))
		AudioServer.set_bus_mute(0,not sound_enabled or music_volume <= .001)

func add_audio_controls(parent: Control) -> void:
	var mute := CheckButton.new()
	mute.text = "Фоновая музыка"
	mute.button_pressed = sound_enabled
	mute.toggled.connect(func(value: bool) -> void:
		sound_enabled = value
		apply_audio()
		save_preferences()
	)
	parent.add_child(mute)
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.value = music_volume*100
	slider.custom_minimum_size.y = 48
	slider.value_changed.connect(func(value: float) -> void:
		music_volume = value/100
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
	box.add_child(label("Диагностика",34))
	box.add_child(label("Отчёт содержит события боя, причины простоя, урон, баланс и ошибки. Личные данные и сохранения в архив не входят.",22,"a8bac8"))
	var toggle:=CheckButton.new()
	toggle.text="Записывать диагностику"
	toggle.button_pressed=debug_enabled
	toggle.toggled.connect(func(value: bool) -> void:
		debug_enabled=value;sim.diagnostics.enabled=value;save_preferences()
		error_logger.directory=SaveStore.directory.path_join("diagnostics") if value else ""
	)
	box.add_child(toggle)
	var rings:=CheckButton.new()
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
	var box:=open_sheet(940)
	box.add_child(label("Каталог башен",32))
	box.add_child(label("Уровни 1 · 5 · 10 · MEGA",21,"a9bac6"))
	var catalog:=TowerCatalog.new()
	catalog.custom_minimum_size=Vector2(580,620)
	box.add_child(catalog)
	box.add_child(button("Закрыть",close_sheet))
