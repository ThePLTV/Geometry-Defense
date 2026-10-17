class_name GameBoard
extends Control

signal cell_selected(cell: Vector2i)
signal tower_hold_started(id: int)
signal tower_hold_ended
var sim: Simulation
var selected := Vector2i(999,999)
var show_route := false
var debug_grid := false
var draw_scale := 1.0
var draw_offset := Vector2.ZERO
var merge_source := -1
var interpolation := 1.0
var held_id := -1
var hold_time := 0.0
var hold_shown := false
var down_position := Vector2.ZERO
const BASE_SIZE = Vector2(620,930)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	custom_minimum_size = Vector2(0,240)

func layout_board() -> void:
	draw_scale = minf(size.x/BASE_SIZE.x,size.y/BASE_SIZE.y)
	draw_offset = (size-BASE_SIZE*draw_scale)*.5

func source_position(cell: Vector2i) -> Vector2:
	return Vector2(105+cell.x*58.25,53.5+(cell.y+cell.x*.5)*77.65)

func world_position(point: Vector2) -> Vector2:
	return draw_offset+Vector2(105+point.x*(58.25/(sqrt(3.0)/2)),53.5+point.y*77.65)*draw_scale

func center(cell: Vector2i) -> Vector2:
	return draw_offset+source_position(cell)*draw_scale

func polygon(position: Vector2, radius: float = 1.0) -> PackedVector2Array:
	var points := PackedVector2Array()
	for p in [Vector2(1,0),Vector2(.5,1),Vector2(-.5,1),Vector2(-1,0),Vector2(-.5,-1),Vector2(.5,-1)]:
		points.append(position+p*37.3*draw_scale*radius)
	return points

func cell_at(position: Vector2) -> Vector2i:
	var best := Vector2i(999,999)
	var distance := 39*draw_scale
	for cell in sim.map.cells:
		var d := position.distance_to(center(cell))
		if d < distance:
			distance = d
			best = cell
	return best

func release_hold() -> void:
	held_id = -1
	hold_time = 0
	if hold_shown:
		hold_shown = false
		tower_hold_ended.emit()

func _gui_input(event: InputEvent) -> void:
	if sim == null:
		return
	var pointer: bool = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT
	pointer = pointer or (event is InputEventScreenTouch and event.index == 0)
	if pointer:
		if not event.pressed:
			release_hold()
			return
		layout_board()
		var cell := cell_at(event.position)
		if cell.x != 999:
			cell_selected.emit(cell)
			var t := sim.tower_at(cell)
			held_id = -1 if t.is_empty() else int(t.id)
			down_position = event.position
			hold_time = 0
			accept_event()
	elif (event is InputEventMouseMotion or event is InputEventScreenDrag) and held_id >= 0:
		if event.position.distance_to(down_position) > 24:
			release_hold()

func _input(event: InputEvent) -> void:
	# Capture release even if the pointer has left the field.
	if (event is InputEventScreenTouch or event is InputEventMouseButton) and not event.pressed:
		release_hold()

func _process(delta: float) -> void:
	if held_id >= 0 and not hold_shown:
		hold_time += delta
		if hold_time >= .4:
			hold_shown = true
			tower_hold_started.emit(held_id)

static func tower_shape(canvas: CanvasItem, position: Vector2, kind: String, radius: float, level: int = 1, ultimate: bool = false, mega: bool = false) -> void:
	TowerVisuals.draw(canvas,position,kind,radius,clampi(level,1,10),ultimate,mega)

func ring(origin: Vector2, radius: float, color: Color, width: float = 1.8) -> void:
	var points := PackedVector2Array()
	for i in 65:
		points.append(world_position(origin+Vector2.from_angle(i*TAU/64)*radius))
	draw_polyline(points,color,width*draw_scale,true)

func hp_visible(e: Dictionary) -> bool:
	return sim.time-float(e.last_hit) < float(Balance.cfg.hp_bar_seconds)

func _draw() -> void:
	layout_board()
	draw_style_box(panel_style(),Rect2(Vector2.ZERO,size))
	if sim == null:
		return
	for q in range(-3,11):
		for r in range(-9,18):
			var cell := Vector2i(q,r)
			var position := center(cell)
			if position.x < -40 or position.x > size.x+40 or position.y < -40 or position.y > size.y+40:
				continue
			var color := Color("21352d")
			if sim.map.cells.has(cell):
				color = Color("080d10")
			if cell == sim.map.spawn:
				color = Color("8d4650")
			elif cell == sim.map.goal:
				color = Color("70538d")
			var points := polygon(position)
			draw_colored_polygon(points,color)
			points.append(points[0])
			draw_polyline(points,Color("3b4946"),maxf(.8,draw_scale),true)
	if show_route or debug_grid:
		var path := PackedVector2Array()
		for cell in sim.map.route(sim.map.spawn):
			path.append(center(cell))
		if path.size() > 1:
			draw_polyline(path,Color(.5,.75,.86,.48),2*draw_scale,true)
	if selected.x != 999 and sim.map.cells.has(selected):
		var border := polygon(center(selected),1.01)
		border.append(border[0])
		draw_polyline(border,Color("9ed5ed"),2.3*draw_scale,true)
		var chosen := sim.tower_at(selected)
		if not chosen.is_empty():
			ring(HexMap.point(selected),Balance.reach(chosen),Color(.55,.75,.87,.55))
	for t in sim.towers:
		TowerVisuals.draw(self,center(t.cell),t.kind,23*draw_scale,t.level,t.ultimate,t.mega,t.angle,t.flash,sim.time)
		if not t.job.is_empty():
			var progress: float = 1-t.job_left/maxf(.001,t.job_total)
			draw_arc(center(t.cell),32*draw_scale,-PI/2,TAU-PI/2,48,Color("34424d"),3*draw_scale,true)
			draw_arc(center(t.cell),32*draw_scale,-PI/2,-PI/2+maxf(.001,TAU*progress),48,Color("e7cd86"),3*draw_scale,true)
		if t.id == merge_source:
			draw_arc(center(t.cell),35*draw_scale,0,TAU,32,Color("e7cd86"),2*draw_scale,true)
	for e in sim.enemies:
		if e.hp <= 0:
			continue
		var point: Vector2 = e.get("previous_pos",e.pos).lerp(e.pos,interpolation)
		var position := world_position(point)
		var data: Dictionary = Balance.cfg.enemies.get(e.kind,Balance.cfg.enemies.heavy)
		var radius := (25.0 if e.kind == "boss" else float(data.radius))*draw_scale
		var color := Color(e.color)
		var shape: String = data.shape if e.kind != "boss" else "hexagon"
		var sides := 6 if shape == "hexagon" else 3 if shape == "triangle" else 4
		var angle := PI/4 if shape in ["square","double_square"] else -PI/2
		TowerVisuals.poly(self,position,radius,sides,color,angle,2.3*draw_scale)
		if shape == "double_square" or e.kind == "boss":
			TowerVisuals.poly(self,position,radius*.68,sides,color,angle,1.2*draw_scale)
		if hp_visible(e):
			draw_rect(Rect2(position+Vector2(-radius,-radius-8*draw_scale),Vector2(radius*2,3*draw_scale)),Color("394650"))
			draw_rect(Rect2(position+Vector2(-radius,-radius-8*draw_scale),Vector2(radius*2*clampf(e.hp/e.max_hp,0,1),3*draw_scale)),Color("c2d5ba"))
	for p in sim.projectiles:
		var origin: Vector2 = p.get("previous_pos",p.pos).lerp(p.pos,interpolation)
		var position := world_position(origin)
		if p.type == "wave":
			ring(p.pos,p.radius,Color("39b4f6"),2)
		elif p.type == "bullet":
			draw_circle(position,2.4*draw_scale,Color.WHITE)
		else:
			var velocity: Vector2 = p.velocity
			var angle := atan2(velocity.y*77.65,velocity.x*67.26)
			var u := Vector2.from_angle(angle)
			var v := u.orthogonal()
			var r := (4.5 if p.mini else 7.0)*draw_scale
			draw_line(position-u*r,position-u*r*2.3,Color("b86d3c"),1.5*draw_scale,true)
			draw_colored_polygon(PackedVector2Array([position+u*r,position-u*r+v*r*.44,position-u*r*.5,position-u*r-v*r*.44]),Color("f08772"))
	for effect in sim.effects:
		var color: Color = effect.color
		var fraction: float = clampf(effect.life/effect.duration,0,1)
		color.a = fraction
		var position := world_position(effect.a)
		if effect.type == "laser":
			var endpoint := world_position(effect.b)
			var normal := (endpoint-position).normalized().orthogonal()
			var count := maxi(1,int(effect.radius))
			for i in count:
				var offset := normal*(i-(count-1)*.5)*1.7*draw_scale
				draw_line(position+offset,endpoint+offset,color,maxf(.7,draw_scale),true)
		elif effect.type == "death":
			for i in 5:
				var direction := Vector2.from_angle(i*TAU/5)
				TowerVisuals.poly(self,position+direction*(1-fraction)*28*draw_scale,3*draw_scale*fraction,3,color,i,1.3*draw_scale)
		elif effect.type in ["hit","spawn"]:
			TowerVisuals.poly(self,position,(4+(1-fraction)*9)*draw_scale,4,color,PI/4,1.2*draw_scale)
		else:
			ring(effect.a,effect.radius*(1-fraction),color,1.5)
	var font := ThemeDB.fallback_font
	var text := str(sim.base_hp)
	var font_size := int(24*draw_scale)
	var measure := font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size)
	draw_string(font,center(sim.map.goal)+Vector2(-measure.x*.5,(font.get_ascent(font_size)-font.get_descent(font_size))*.5),text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,Color.WHITE)
	if debug_grid:
		for cell in sim.map.cells:
			draw_string(font,center(cell)+Vector2(-20,25)*draw_scale,"%d,%d"%[cell.x,cell.y],HORIZONTAL_ALIGNMENT_LEFT,-1,int(12*draw_scale),Color("bbcbd3"))

func panel_style() -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = Color("1c2828")
	result.set_corner_radius_all(12)
	return result
