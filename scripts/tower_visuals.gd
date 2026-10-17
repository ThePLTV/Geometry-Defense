class_name TowerVisuals
extends RefCounted

static func poly(c: CanvasItem, p: Vector2, r: float, n: int, color: Color, rotation: float = 0.0, width: float = 1.8) -> void:
	var points := PackedVector2Array()
	for i in n:
		points.append(p+Vector2.from_angle(rotation+TAU*i/n)*r)
	points.append(points[0])
	c.draw_polyline(points,color,width,true)

# Each level adds a visible component. Models share the original class silhouettes.
static func draw(c: CanvasItem, p: Vector2, kind: String, r: float, level: int, ultimate: bool, mega: bool, aim: float = -PI/2, flash: float = 0.0, clock: float = 0.0) -> void:
	var color := Color(Balance.tower(kind).color)
	var dark := Color("151d23")
	var u := Vector2.from_angle(aim)
	var v := u.orthogonal()
	var w := maxf(1.1,r*.075)
	if kind == "Shockwave" and flash > 0:
		p += Vector2(sin(clock*130),cos(clock*101))*r*.045
	if mega:
		poly(c,p,r*1.24,12,color,PI/12,w)
		poly(c,p,r*1.08,6,color.lightened(.35),0,w)
		for i in 6:
			c.draw_circle(p+Vector2.from_angle(i*TAU/6)*r*1.24,r*.1,color)
	match kind:
		"Minigun":
			c.draw_circle(p,r*.64,dark)
			c.draw_arc(p,r*.64,0,TAU,40,color,w,true)
			c.draw_arc(p,r*.39,0,TAU,32,color,w*.65,true)
			var barrels := mini(level,5)
			for i in barrels:
				var side := v*(i-(barrels-1)*.5)*r*.18
				c.draw_line(p+side+u*r*.1,p+side+u*r*(1.0+float(i%2)*.09),color,w,true)
			if level >= 6:
				c.draw_line(p-u*r*.75-v*r*.48,p-u*r*.75+v*r*.48,color,w,true)
			if level >= 7:
				c.draw_circle(p-u*r*.72,r*.2,color)
			if level >= 8:
				poly(c,p,r*.83,8,color.darkened(.2),aim,w*.8)
			if level >= 9:
				for side in [-1,1]:
					c.draw_line(p+v*r*.75*side,p+v*r*.75*side-u*r*.5,color,w,true)
			if level >= 10:
				c.draw_arc(p-u*r*.12,r*.93,aim+.8,aim+TAU-.8,32,color,w,true)
		"Laser":
			c.draw_circle(p,r*.73,dark)
			c.draw_arc(p,r*.73,0,TAU,40,color,w,true)
			for i in level:
				var side := v*(i-(level-1)*.5)*r*.11
				c.draw_line(p+side-u*r*.2,p+side+u*r*.94,color,w*.65,true)
			if level >= 2:
				c.draw_arc(p,r*.49,aim+.6,aim+TAU-.6,24,color,w*.7,true)
			if level >= 6:
				for i in range(level-5):
					var a := aim+PI+(i-(level-6)*.5)*.32
					c.draw_line(p+Vector2.from_angle(a)*r*.8,p+Vector2.from_angle(a)*r*1.08,color,w,true)
		"Rocket":
			# One visible launcher tube per level; two staggered rows at high levels.
			for i in level:
				var row := i/5
				var col := i%5
				var count := mini(level,5)
				var a := p+v*(col-(count-1)*.5)*r*.3-u*r*.3*row
				var pts := PackedVector2Array([a-u*r*.45-v*r*.1,a+u*r*.55-v*r*.1,a+u*r*.8,a+u*r*.55+v*r*.1,a-u*r*.45+v*r*.1,a-u*r*.45-v*r*.1])
				c.draw_polyline(pts,color,w*.75,true)
			if level >= 6:
				c.draw_line(p-u*r*.7-v*r*.83,p-u*r*.7+v*r*.83,color,w,true)
		"Shockwave":
			poly(c,p,r*.82,4,color,PI/4,w)
			poly(c,p,r*.42,4,color,PI/4,w)
			c.draw_arc(p,r*.23,0,TAU,24,color,w,true)
			for i in range(level-1):
				var a := -PI/2+i*TAU/9
				c.draw_line(p+Vector2.from_angle(a)*r*.85,p+Vector2.from_angle(a)*r*1.08,color,w,true)
			if level >= 6:
				c.draw_arc(p,r*.64,0,TAU,32,color,w*.65,true)
	if ultimate:
		# Class specific permanent ultimate components, separate from the level model.
		match kind:
			"Minigun":
				for side in [-1,1]:
					poly(c,p+v*r*.82*side,r*.22,3,color,aim,w)
			"Laser":
				c.draw_arc(p,r*.98,0,TAU,48,color,w,true)
				c.draw_line(p-u*r,p+u*r,color,w*.65,true)
			"Rocket":
				for i in 3:
					poly(c,p-u*r*.94+v*r*(i-1)*.4,r*.16,3,color,aim,w*.8)
			"Shockwave":
				poly(c,p,r*1.03,4,color,0,w)
				for i in 4:
					poly(c,p+Vector2.from_angle(i*PI/2)*r*.93,r*.15,3,color,i*PI/2+PI,w)
	if flash > 0 and kind != "Shockwave":
		c.draw_circle(p+u*r,r*.09,Color(color,minf(1,flash*9)))
