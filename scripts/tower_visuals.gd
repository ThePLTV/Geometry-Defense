class_name TowerVisuals
extends RefCounted

static func poly(c: CanvasItem, p: Vector2, r: float, n: int, color: Color, rotation: float = 0.0, width: float = 1.8) -> void:
	var points:=PackedVector2Array()
	for i in n:points.append(p+Vector2.from_angle(rotation+TAU*i/n)*r)
	points.append(points[0]);c.draw_polyline(points,color,width,true)

static func shape(c: CanvasItem, p: Vector2, points: Array, r: float, angle: float, fill: Color, edge: Color, width: float) -> void:
	var polygon:=PackedVector2Array()
	for point in points:polygon.append(p+(point as Vector2).rotated(angle)*r)
	c.draw_colored_polygon(polygon,fill)
	polygon.append(polygon[0]);c.draw_polyline(polygon,edge,width,true)

static func part(c: CanvasItem, p: Vector2, u: Vector2, v: Vector2, color: Color, width: float) -> void:
	var corners:=PackedVector2Array([p-u-v,p+u-v,p+u+v,p-u+v])
	c.draw_colored_polygon(corners,color.darkened(.72))
	corners.append(corners[0]);c.draw_polyline(corners,color,width,true)

static func draw(c: CanvasItem, p: Vector2, kind: String, r: float, level: int, ultimate: bool, mega: bool, aim: float=-PI/2, flash: float=0.0, clock: float=0.0) -> void:
	var color:=Color(Balance.tower(kind).color)
	var muted:=color.darkened(.5)
	var bright:=color.lightened(.25)
	var dark:=Color("111a23")
	var width:=maxf(.8,r*.045)
	var u:=Vector2.from_angle(aim)
	var v:=u.orthogonal()
	if kind=="Shockwave" and flash>0:p+=Vector2(sin(clock*130),cos(clock*101))*r*.035
	# Stationary foundation: four feet, four bolts, six separated armour plates,
	# central pivot and chassis. All are placed in distinct visible regions.
	for i in 4:
		var direction:=Vector2.from_angle(PI/4+i*PI/2)
		part(c,p+direction*r*.88,direction*r*.18,direction.orthogonal()*r*.14,muted,width)
		c.draw_circle(p+direction*r*.9,r*.035,bright)
	var outline:=PackedVector2Array()
	for i in 8:outline.append(p+Vector2.from_angle(PI/8+i*TAU/8)*r*.82)
	c.draw_colored_polygon(outline,dark)
	outline.append(outline[0]);c.draw_polyline(outline,muted,width,true)
	for i in 6:
		var a:=i*TAU/6
		var direction:=Vector2.from_angle(a)
		part(c,p+direction*r*.7,direction*r*.11,direction.orthogonal()*r*.14,color.darkened(.35),width)
	c.draw_circle(p,r*.47,color.darkened(.65))
	c.draw_arc(p,r*.47,0,TAU,32,muted,width,true)
	# Upgrade modules: paired cooling/armour housings, seams and fasteners.
	# Distinct sectors avoid repeatedly drawing hidden geometry at the pivot.
	for upgrade in range(1,level):
		var a: float=(upgrade-1)*TAU/9+PI/18
		var direction:=Vector2.from_angle(a)
		var pos:=p+direction*r*(.91 if upgrade<=5 else .6)
		part(c,pos,direction*r*.1,direction.orthogonal()*r*.1,muted,width*.8)
		c.draw_line(pos-direction.orthogonal()*r*.065,pos+direction.orthogonal()*r*.065,bright,width*.7,true)
		for side in [-1,1]:
			c.draw_circle(pos+direction.orthogonal()*r*.075*side,r*.023,bright)
	match kind:
		"Minigun":
			# Upper turret rotates independently of the foundation.
			shape(c,p,[Vector2(-.52,-.35),Vector2(.38,-.38),Vector2(.57,-.2),Vector2(.57,.2),Vector2(.38,.38),Vector2(-.52,.35)],r,aim,color.darkened(.7),color,width)
			var count:=mini(level,5)
			for i in count:
				var side:=v*(i-(count-1)*.5)*r*.13
				part(c,p+side+u*r*.6,u*r*.47,v*r*.045,color,width*.8)
				c.draw_line(p+side+u*r*.83-v*r*.055,p+side+u*r*.83+v*r*.055,bright,width,true)
			for i in 3:
				part(c,p-u*r*(.13+i*.13),u*r*.035,v*r*.3,muted,width*.7)
			for side in [-1,1]:
				part(c,p+v*r*.4*side-u*r*.22,u*r*.23,v*r*.1,color,width)
				c.draw_line(p+v*r*.4*side-u*r*.4,p+v*r*.4*side-u*r*.1,bright,width,true)
		"Laser":
			shape(c,p,[Vector2(-.55,-.3),Vector2(.28,-.48),Vector2(.6,-.23),Vector2(.6,.23),Vector2(.28,.48),Vector2(-.55,.3)],r,aim,color.darkened(.74),color,width)
			for side in [-1,1]:
				part(c,p+v*r*.36*side,u*r*.33,v*r*.08,color,width)
				for i in 3:
					c.draw_line(p+v*r*.36*side+u*r*(i*.17-.17),p+v*r*.48*side+u*r*(i*.17-.17),bright,width,true)
			for i in 3:
				c.draw_line(p+u*r*(.25+i*.23)-v*r*(.31-i*.04),p+u*r*(.25+i*.23)+v*r*(.31-i*.04),color,width,true)
			c.draw_circle(p+u*r*.85,r*.13,color)
			c.draw_circle(p+u*r*.85,r*.065,bright)
			for i in mini(level,10):
				var side:=v*(i-(level-1)*.5)*r*.035
				c.draw_line(p+side-u*r*.2,p+side+u*r*.6,color,width*.55,true)
		"Rocket":
			part(c,p-u*r*.12,u*r*.48,v*r*.52,muted,width)
			var racks:=2 if level<6 else 3
			for i in racks:
				var side:=v*(i-(racks-1)*.5)*r*.42
				shape(c,p+side,[Vector2(-.48,-.16),Vector2(.42,-.16),Vector2(.7,0),Vector2(.42,.16),Vector2(-.48,.16)],r,aim,color.darkened(.6),color,width)
				for j in 3:
					c.draw_line(p+side+u*r*(j*.2-.34)-v*r*.12,p+side+u*r*(j*.2-.34)+v*r*.12,bright,width*.7,true)
			for side in [-1,1]:
				part(c,p-u*r*.4+v*r*.48*side,u*r*.12,v*r*.1,color,width)
				c.draw_circle(p-u*r*.4+v*r*.48*side,r*.035,bright)
		"Shockwave":
			poly(c,p,r*.58,4,color,PI/4,width)
			c.draw_arc(p,r*.38,0,TAU,32,color,width,true)
			c.draw_circle(p,r*.16,color.darkened(.5));c.draw_arc(p,r*.16,0,TAU,24,bright,width,true)
			for i in 4:
				var direction:=Vector2.from_angle(i*PI/2)
				part(c,p+direction*r*.48,direction*r*.17,direction.orthogonal()*r*.1,color,width)
				c.draw_line(p+direction*r*.34,p+direction*r*.6,bright,width,true)
				c.draw_circle(p+direction*r*.6,r*.035,bright)
	if ultimate:
		for i in 4:
			var a:=PI/4+i*PI/2
			var direction:=Vector2.from_angle(a)
			part(c,p+direction*r*1.05,direction*r*.12,direction.orthogonal()*r*.09,color,width)
			poly(c,p+direction*r*1.05,r*.055,3,bright,a,width*.6)
		if kind=="Laser":c.draw_arc(p,r*1.08,0,TAU,48,color,width,true)
		elif kind=="Minigun":
			for side in [-1,1]:poly(c,p+v*r*.7*side,r*.16,3,bright,aim,width)
		elif kind=="Rocket":
			for i in 3:poly(c,p-u*r*.76+v*r*(i-1)*.25,r*.09,3,bright,aim,width)
		else:poly(c,p,r*.9,8,color,PI/8,width)
	if mega:
		poly(c,p,r*1.25,8,bright,PI/8,width*1.4)
		for i in 8:
			var direction:=Vector2.from_angle(PI/8+i*TAU/8)
			part(c,p+direction*r*1.2,direction*r*.13,direction.orthogonal()*r*.08,color,width)
			c.draw_circle(p+direction*r*1.25,r*.035,bright)
	if flash>0 and kind!="Shockwave":c.draw_circle(p+u*r*1.05,r*.08,Color(bright,minf(1,flash*7)))
