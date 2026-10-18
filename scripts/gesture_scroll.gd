class_name GestureScroll
extends ScrollContainer

# Observe input before child buttons consume GUI events. The engine's scroll
# notification cancels their pending tap, including OptionButton and toggles.
var pointer := -2
var origin := Vector2.ZERO
var initial_scroll := 0
var dragging := false
var horizontal := false

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree(): return
	var pos := Vector2.ZERO
	var begin := false
	var end := false
	var motion := false
	var index := -1
	if event is InputEventScreenTouch:
		pos=event.position;index=event.index;begin=event.pressed;end=not event.pressed
	elif event is InputEventScreenDrag:
		pos=event.position;index=event.index;motion=true
	elif event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		if event.device==-1: return # Native touch is handled above.
		pos=event.position;begin=event.pressed;end=not event.pressed
	elif event is InputEventMouseMotion:
		if event.device==-1: return
		pos=event.position;motion=true
	else: return
	if begin:
		if pointer!=-2 or not get_global_rect().has_point(pos): return
		pointer=index;origin=pos;initial_scroll=scroll_vertical;dragging=false;horizontal=false
	elif index==pointer:
		if motion and not horizontal:
			var travel := pos-origin
			if not dragging and absf(travel.x)>14 and absf(travel.x)>absf(travel.y)*1.3:
				horizontal=true # Preserve normal slider gestures.
			elif dragging or absf(travel.y)>14:
				if not dragging:
					dragging=true
					propagate_notification(Control.NOTIFICATION_SCROLL_BEGIN)
				get_viewport().set_input_as_handled()
				scroll_vertical=initial_scroll-int(travel.y)
		if end:
			if dragging:
				get_viewport().set_input_as_handled()
				propagate_notification(Control.NOTIFICATION_SCROLL_END)
			pointer=-2;dragging=false;horizontal=false

# Only wheel/pan events use the built-in scroller; touch is owned above to avoid
# the built-in and custom drag offsets competing on blank areas.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		accept_event()
