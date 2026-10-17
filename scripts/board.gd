class_name GameBoard
extends Control

signal cell_selected(cell: Vector2i)
var sim: Simulation
var selected := Vector2i(999,999)
var show_route := false
var debug_grid := false
var draw_scale := 1.0
var draw_offset := Vector2.ZERO
var merge_source := -1
const BASE_SIZE = Vector2(698,950)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	custom_minimum_size = Vector2(0,300)

func layout_board() -> void:
	draw_scale = minf(size.x/BASE_SIZE.x,size.y/BASE_SIZE.y)
	draw_offset = (size - BASE_SIZE*draw_scale)*0.5

func source_position(cell: Vector2i) -> Vector2:
	return Vector2(150.0 + cell.x*58.25,53.5 + (cell.y + cell.x*0.5)*77.65)

func world_position(point: Vector2) -> Vector2:
	return draw_offset + Vector2(150.0+point.x*(58.25/(sqrt(3.0)/2.0)),53.5+point.y*77.65)*draw_scale

func center(cell: Vector2i) -> Vector2:
	return draw_offset + source_position(cell)*draw_scale

func polygon(position: Vector2, radius: float = 1.0) -> PackedVector2Array:
	var points := PackedVector2Array()
	for p in [Vector2(1,0),Vector2(0.5,1),Vector2(-0.5,1),Vector2(-1,0),Vector2(-0.5,-1),Vector2(0.5,-1)]:
		points.append(position + Vector2(p.x*37.3,p.y*37.3)*draw_scale*radius)
	return points

func _gui_input(event: InputEvent) -> void:
	var position := Vector2.ZERO
	var pressed := false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		position = event.position
		pressed = true
	elif event is InputEventScreenTouch and event.pressed:
		position = event.position
		pressed = true
	if not pressed or sim == null:
		return
	layout_board()
	var best := Vector2i(999,999)
	var distance := 40.0 * draw_scale
	# Hit test all grid cells, including blocked background.
	for q in range(-3,11):
		for r in range(-9,18):
			var cell := Vector2i(q,r)
			var value := position.distance_to(center(cell))
			if value < distance:
				distance = value
				best = cell
	if best.x != 999:
		cell_selected.emit(best)
		accept_event()

static func tower_shape(canvas: CanvasItem, position: Vector2, kind: String, radius: float, level: int = 0, ultimate: bool = false, mega: bool = false) -> void:
	var color := Color(Balance.tower(kind).color)
	var edge := color.lightened(0.35)
	var dark := Color("222c33")
	if mega:
		var outer := PackedVector2Array()
		for i in range(12):
			var angle := float(i)*TAU/12.0
			outer.append(position + Vector2.from_angle(angle)*radius*(1.22 if i%2 == 0 else 1.05))
		canvas.draw_colored_polygon(outer,color.darkened(0.5))
		outer.append(outer[0])
		canvas.draw_polyline(outer,edge,2.0,true)
	if level >= 5:
		canvas.draw_arc(position,radius*1.02,0,TAU,24,Color(color,0.38),1.7,true)
	match kind:
		"Minigun":
			canvas.draw_circle(position,radius*0.65,color)
			canvas.draw_circle(position,radius*0.4,dark)
			for i in range(3+int(level/7.0)):
				var x := (i-(2+int(level/7.0))*0.5)*radius*0.22
				canvas.draw_line(position+Vector2(x,0),position+Vector2(x,-radius),edge,3.3,true)
		"Laser":
			var p := PackedVector2Array([position+Vector2(0,-radius),position+Vector2(radius*.58,0),position+Vector2(0,radius),position+Vector2(-radius*.58,0)])
			canvas.draw_colored_polygon(p,color)
			canvas.draw_line(position+Vector2(0,-radius*.7),position+Vector2(0,radius*.7),edge,3.0,true)
		"Rocket":
			var p := PackedVector2Array()
			for i in range(8):
				p.append(position+Vector2.from_angle(PI/8+i*TAU/8)*radius)
			canvas.draw_colored_polygon(p,color)
			canvas.draw_circle(position,radius*.42,dark)
			canvas.draw_line(position+Vector2(-radius*.6,radius*.2),position+Vector2(radius*.6,-radius*.2),edge,2.0,true)
		"Shockwave":
			for i in range(3):
				canvas.draw_arc(position,radius*(.33+i*.29),0,TAU,24,color,2.5,true)
			canvas.draw_circle(position,radius*.15,edge)
	if ultimate:
		canvas.draw_circle(position+Vector2(radius*.75,radius*.65),radius*.16,Color("dceaf2"))

func _draw() -> void:
	layout_board()
	draw_style_box(panel_style(),Rect2(Vector2.ZERO,size))
	if sim == null:
		return
	for q in range(-3,11):
		for r in range(-9,18):
			var cell := Vector2i(q,r)
			var position := center(cell)
			if position.x < -45 or position.x > size.x+45 or position.y < -40 or position.y > size.y+40:
				continue
			var color := Color("223631") if (q+r)%2 == 0 else Color("243934")
			if sim.map.cells.has(cell):
				color = Color("080d10")
			if cell == sim.map.spawn:
				color = Color("a04f58")
			elif cell == sim.map.goal:
				color = Color("79629a")
			var poly := polygon(position)
			draw_colored_polygon(poly,color)
			poly.append(poly[0])
			draw_polyline(poly,Color("344540") if not sim.map.cells.has(cell) else Color("39434a"),1.1*draw_scale,true)
	if show_route or debug_grid:
		var route := sim.map.route(sim.map.spawn)
		var points := PackedVector2Array()
		for cell in route:
			points.append(center(cell))
		if points.size() > 1:
			draw_polyline(points,Color(0.50,0.75,0.86,0.48),3.0*draw_scale,true)
		for i in range(route.size()):
			draw_circle(center(route[i]),4.0*draw_scale,Color("8ac7de"))
			if debug_grid:
				draw_string(ThemeDB.fallback_font,center(route[i])+Vector2(-9,-11)*draw_scale,str(i),HORIZONTAL_ALIGNMENT_LEFT,-1,14*draw_scale,Color.WHITE)
	if selected.x != 999 and sim.map.cells.has(selected):
		var border := polygon(center(selected),1.03)
		border.append(border[0])
		draw_polyline(border,Color("9ed5ed"),3.0*draw_scale,true)
		var chosen := sim.tower_at(selected)
		if not chosen.is_empty():
			var radius := Balance.reach(chosen)
			var ring := PackedVector2Array()
			var from := HexMap.point(selected)
			for i in range(64):
				ring.append(world_position(from+Vector2.from_angle(i*TAU/64.0)*radius))
			draw_colored_polygon(ring,Color(0.45,0.68,0.82,0.08))
			ring.append(ring[0])
			draw_polyline(ring,Color(0.45,0.68,0.82,0.55),1.5,true)
	for t in sim.towers:
		tower_shape(self,center(t.cell),t.kind,23.0*draw_scale,int(t.d+t.s),t.ultimate,t.mega)
		if t.id == merge_source:
			draw_arc(center(t.cell),32*draw_scale,0,TAU,24,Color("ead69a"),3.0,true)
	for e in sim.enemies:
		var position := world_position(e.pos)
		var radius := (19.0 if e.kind == "boss" else 10.0 if e.kind == "child" else 13.0)*draw_scale
		var color := Color(e.color)
		var points := PackedVector2Array()
		var sides := 6 if e.kind == "boss" else 4 if e.kind in ["heavy","armored"] else 3 if e.kind == "fast" else 10
		for i in range(sides):
			points.append(position+Vector2.from_angle(-PI/2+i*TAU/sides)*radius)
		draw_colored_polygon(points,color)
		if e.kind == "boss" or e.kind == "resistant":
			draw_arc(position,radius+3,0,TAU,20,Color(Balance.tower(e.immune if e.kind == "boss" else e.resist).color),2.3,true)
		if e.kind == "armored":
			draw_arc(position,radius*.75,0,TAU,12,Color("e5ebf0"),2.0,true)
		draw_rect(Rect2(position+Vector2(-radius,-radius-7),Vector2(radius*2,3)),Color("35434b"))
		draw_rect(Rect2(position+Vector2(-radius,-radius-7),Vector2(radius*2*maxf(0,e.hp/e.max_hp),3)),Color("b6d1ba"))
	for p in sim.projectiles:
		var position := world_position(p.pos)
		draw_circle(position,(3.0 if p.mini else 5.5)*draw_scale,Color("eabf94"))
	for effect in sim.effects:
		var color: Color = effect.color
		color.a = effect.life/effect.duration
		var from := world_position(effect.a)
		if effect.type in ["bullet","laser"]:
			draw_line(from,world_position(effect.b),color,(3.2 if effect.type == "laser" else 1.8)*draw_scale,true)
		else:
			var ring := PackedVector2Array()
			var radius: float = effect.radius*(1.0-effect.life/effect.duration)
			for i in range(49):
				ring.append(world_position(effect.a+Vector2.from_angle(i*TAU/48)*radius))
			draw_polyline(ring,color,2.5*draw_scale,true)
	var font := ThemeDB.fallback_font
	draw_string(font,center(sim.map.spawn)+Vector2(-22,-45)*draw_scale,"ВХОД",HORIZONTAL_ALIGNMENT_LEFT,-1,14*draw_scale,Color("d6a7aa"))
	draw_string(font,center(sim.map.goal)+Vector2(-16,7)*draw_scale,str(sim.base_hp),HORIZONTAL_ALIGNMENT_LEFT,-1,22*draw_scale,Color.WHITE)
	if debug_grid:
		for cell in sim.map.cells:
			draw_string(font,center(cell)+Vector2(-21,23)*draw_scale,"%d,%d"%[cell.x,cell.y],HORIZONTAL_ALIGNMENT_LEFT,-1,12*draw_scale,Color("bbcbd3"))

func panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("1c2828")
	style.corner_radius_top_left = 20
	style.corner_radius_top_right = 20
	style.corner_radius_bottom_left = 20
	style.corner_radius_bottom_right = 20
	return style
