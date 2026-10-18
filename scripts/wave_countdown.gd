class_name WaveCountdown
extends Control

var remaining := 5.0

func _ready() -> void:
	custom_minimum_size=Vector2(64,64)
	mouse_filter=Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var center := size*.5
	var radius := minf(size.x,size.y)*.40
	draw_arc(center,radius,0,TAU,48,Color("384653"),5,true)
	var progress := clampf(1.0-remaining/5.0,0,1)
	if progress>0:
		draw_arc(center,radius,-PI*.5,-PI*.5+TAU*progress,48,Color("9fd4ed"),5,true)
	var text := str(ceili(maxf(0,remaining)))
	var font := ThemeDB.fallback_font
	var width := font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,22).x
	draw_string(font,center+Vector2(-width*.5,8),text,HORIZONTAL_ALIGNMENT_LEFT,-1,22,Color("e3e9ee"))
