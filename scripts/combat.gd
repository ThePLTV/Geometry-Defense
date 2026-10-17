class_name Combat
extends RefCounted

static func ray_end(from: Vector2, direction: Vector2) -> Vector2:
	var limits := Rect2(-1.56,-.69,9.22,11.98)
	var distance := 1000.0
	if absf(direction.x) > .00001:
		distance = minf(distance,((limits.end.x if direction.x>0 else limits.position.x)-from.x)/direction.x)
	if absf(direction.y) > .00001:
		distance = minf(distance,((limits.end.y if direction.y>0 else limits.position.y)-from.y)/direction.y)
	return from+direction*maxf(0,distance)

static func laser(s, t: Dictionary, target: Dictionary) -> void:
	var from := HexMap.point(t.cell)
	var direction: Vector2 = (target.pos-from).normalized()
	var end := ray_end(from,direction)
	var width: float = Balance.cfg.laser_line_width+Balance.cfg.laser_line_width_per_level*(t.level-1)
	for e in s.enemies.duplicate():
		if e.dead:
			continue
		var nearest := Geometry2D.get_closest_point_to_segment(e.pos,from,end)
		if nearest.distance_to(e.pos) <= Balance.cfg.enemy_hit_radius+width:
			s.hit(e,Balance.damage(t),t)
	s.add_effect("laser",from,end,Color(Balance.tower(t.kind).color),float(t.level),.14)

static func append(s, p: Dictionary) -> void:
	if s.projectiles.size() < int(Balance.cfg.max_projectiles):
		s.projectiles.append(p)
	else:
		var target: Dictionary = s.enemy_by_id(int(p.get("target",-1)))
		var t: Dictionary = s.owner(p.owner_id)
		if not target.is_empty() and not t.is_empty():
			s.hit(target,float(p.get("damage",0)),t,bool(p.get("mini",false)))

static func bullet(s, t: Dictionary, from: Vector2, target: Dictionary, amount: float, bounced: bool, excluded: Array = []) -> void:
	append(s,{"type":"bullet","pos":from,"previous_pos":from,"target":target.id,"owner_id":t.id,
		"damage":amount,"bounced":bounced,"excluded":excluded,"life":3.0})

static func rocket(s, t: Dictionary, from: Vector2, target: Dictionary, amount: float, mini: bool, spread: float) -> void:
	var direction: Vector2 = (target.pos-from).normalized().rotated(spread)
	append(s,{"type":"rocket","pos":from,"previous_pos":from,"velocity":direction*(Balance.cfg.mini_speed if mini else Balance.cfg.rocket_speed),
		"target":target.id,"owner_id":t.id,"damage":amount,"mini":mini,"life":10.0})

static func shoot(s, t: Dictionary, target: Dictionary) -> void:
	t.flash = .10 if t.kind == "Minigun" else .22
	var from := HexMap.point(t.cell)
	match t.kind:
		"Minigun":
			bullet(s,t,from,target,Balance.damage(t),false)
		"Laser":
			laser(s,t,target)
		"Rocket":
			var count := Balance.volley(t)
			for i in range(count):
				var spread := (.72+i*.16)*(1.0 if i%2==0 else -1.0)
				rocket(s,t,from,target,Balance.damage(t),false,spread)
		"Shockwave":
			var period: float = Balance.cfg.mega_reverse_period if t.mega else Balance.cfg.reverse_period
			var reverse: bool = t.ultimate and t.reverse_clock >= period
			if reverse:
				t.reverse_clock = 0.0
			append(s,{"type":"wave","pos":from,"previous_pos":from,"owner_id":t.id,"radius":0.0,
				"previous_radius":0.0,"maximum":Balance.reach(t),"damage":Balance.damage(t),
				"hit":[],"reverse":reverse,"life":3.0})

static func explode(s, position: Vector2, t: Dictionary, amount: float, mini: bool) -> void:
	var radius: float = Balance.cfg.mini_radius if mini else Balance.cfg.rocket_radius
	s.add_effect("blast",position,position,Color(Balance.tower(t.kind).color),radius,.28)
	for e in s.enemies.duplicate():
		if not e.dead and position.distance_squared_to(e.pos) <= radius*radius:
			s.hit(e,amount,t,mini)
	if not mini and t.ultimate and t.job.is_empty():
		var count := int(Balance.cfg.mega_mini_count if t.mega else Balance.cfg.mini_count)
		var seen: Array = []
		for i in range(count):
			var target: Dictionary = s.nearest(position,Balance.cfg.mini_search,seen)
			if target.is_empty():
				target = s.nearest(position,Balance.cfg.mini_search)
			if target.is_empty():
				break
			seen.append(target.id)
			rocket(s,t,position,target,amount*Balance.cfg.mini_damage,true,(i-count*.5)*.45)

static func update_projectile(s, p: Dictionary, delta: float) -> bool:
	var t: Dictionary = s.owner(p.owner_id)
	if t.is_empty() or not t.job.is_empty():
		return false
	p.life -= delta
	if p.life <= 0:
		return false
	p.previous_pos = p.pos
	if p.type == "wave":
		p.previous_radius = p.radius
		p.radius = minf(p.maximum,p.radius+Balance.cfg.wave_speed*delta)
		for e in s.enemies.duplicate():
			var distance: float = p.pos.distance_to(e.pos)
			var before: float = p.pos.distance_to(e.get("previous_pos",e.pos))
			if not e.dead and not p.hit.has(e.id) and distance <= p.radius+.000001 and before >= p.previous_radius-.000001:
				p.hit.append(e.id)
				if s.hit(e,p.damage,t,p.reverse) and p.reverse:
					s.push_back(e,t,Balance.cfg.mega_shock_push if t.mega else Balance.cfg.shock_push)
		return p.radius < p.maximum
	var target: Dictionary = s.enemy_by_id(p.target)
	if target.is_empty():
		target = s.nearest(p.pos,1000000.0,p.get("excluded",[]))
		if target.is_empty():
			return false
		p.target = target.id
	if p.type == "bullet":
		var destination: Vector2 = target.pos
		var next: Vector2 = p.pos.move_toward(destination,Balance.cfg.bullet_speed*delta)
		p.pos = next
		if next.distance_to(destination) <= .03:
			var hit: bool = s.hit(target,p.damage,t,p.bounced)
			s.add_effect("muzzle_hit",destination,destination,Color("f4f6f8"),.09,.07)
			if hit and t.ultimate and not p.bounced:
				var second: Dictionary = s.nearest(destination,1000000.0,[target.id])
				if not second.is_empty():
					bullet(s,t,destination,second,p.damage*(Balance.cfg.mega_ricochet_damage if t.mega else Balance.cfg.ricochet_damage),true,[target.id])
			return false
		return true
	var speed: float = Balance.cfg.mini_speed if p.mini else Balance.cfg.rocket_speed
	var desired: Vector2 = (target.pos-p.pos).normalized()*speed
	p.velocity = p.velocity.lerp(desired,1.0-exp(-Balance.cfg.rocket_steering*delta))
	p.pos += p.velocity*delta
	var closest := Geometry2D.get_closest_point_to_segment(target.pos,p.previous_pos,p.pos)
	if closest.distance_to(target.pos) <= .17 or p.pos.distance_to(target.pos) < speed*delta*.6:
		explode(s,target.pos,t,p.damage,p.mini)
		return false
	return true

static func step(s, delta: float) -> void:
	for t in s.towers:
		t.previous_angle = t.angle
		if not t.job.is_empty():
			continue
		t.cd -= delta
		var target: Dictionary = s.nearest(HexMap.point(t.cell),Balance.reach(t))
		if target.is_empty():
			t.cd = maxf(0,t.cd)
			continue
		var direction: Vector2 = target.pos-HexMap.point(t.cell)
		t.angle = lerp_angle(t.angle,direction.angle(),1.0-exp(-10.0*delta))
		var safety := 0
		while t.cd <= .000001 and not target.is_empty() and safety < 16:
			shoot(s,t,target)
			t.cd += 1.0/Balance.rate(t)
			target = s.nearest(HexMap.point(t.cell),Balance.reach(t))
			safety += 1
	for p in s.projectiles.duplicate():
		if not update_projectile(s,p,delta):
			s.projectiles.erase(p)
