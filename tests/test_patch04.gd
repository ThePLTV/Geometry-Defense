extends SceneTree

var checks:=0
var failures: Array=[]
var reload_rows: Array=[]
func expect(ok: bool, message: String) -> void:
	checks+=1
	if not ok:failures.append(message);printerr("FAIL ",message)
func _init() -> void:call_deferred("run")

func run() -> void:
	Balance.load_config()
	for kind in Balance.KINDS:
		for level in range(1,11):
			for form in ["base","ultimate","mega"]:
				if form!="base" and level!=10:continue
				var s:=Simulation.new(42)
				s.visuals=false;s.diagnostics.enabled=false;s.credits=100000;s.next_id=6705
				s.build(Vector2i(-1,2),kind)
				var t: Dictionary=s.towers[0]
				t.level=level;t.ultimate=form!="base";t.mega=form=="mega"
				var e:=s.spawn_enemy("normal")
				e.pos=HexMap.point(t.cell)+Vector2(.7,0);e.previous_pos=e.pos;e.hp=1e7;e.max_hp=e.hp;e.speed=0
				Combat.step(s,.025) # Save with a real projectile in flight.
				var restored:=Simulation.new()
				restored.visuals=false;restored.diagnostics.enabled=false
				var raw=JSON.parse_string(JSON.stringify(s.snapshot(true)))
				expect(restored.restore(raw),"JSON restore "+kind+str(level)+form)
				expect(restored.towers[0].id is int and not restored.owner(6705).is_empty(),"Canonical live owner ID")
				var before: float=restored.towers[0].damage
				for tick in 200:
					s.time+=.025;restored.time+=.025
					Combat.step(s,.025);Combat.step(restored,.025)
				expect(restored.towers[0].damage>before,"Damage continues after reload "+kind+str(level)+form)
				expect(is_equal_approx(s.total_damage,restored.total_damage),"Restored projectile damage equals uninterrupted play")
				expect(s.towers[0].shots==restored.towers[0].shots and s.towers[0].hits==restored.towers[0].hits,"Cadence and collisions survive JSON")
				expect(s.projectiles.size()==restored.projectiles.size(),"Projectile lifecycle survives JSON")
				reload_rows.append({"kind":kind,"level":level,"form":form,"damage_after_load":restored.towers[0].damage-before,"shots":restored.towers[0].shots})
		# Load during an installation, finish it, and fire again.
		var busy:=Simulation.new();busy.credits=10000;busy.visuals=false;busy.diagnostics.enabled=false
		busy.build(Vector2i(-1,2),kind);busy.upgrade(busy.towers[0].id)
		var loaded:=Simulation.new();loaded.visuals=false;loaded.diagnostics.enabled=false
		expect(loaded.restore(JSON.parse_string(JSON.stringify(busy.snapshot(true)))),"Load during installation "+kind)
		for tick in 121:loaded.step(.025)
		expect(loaded.towers[0].level==2 and loaded.towers[0].job=="","Installation finishes after reload")
		var e:=loaded.spawn_enemy("normal");e.pos=HexMap.point(loaded.towers[0].cell)+Vector2(.7,0);e.previous_pos=e.pos;e.hp=10000;e.max_hp=e.hp
		for tick in 160:Combat.step(loaded,.025)
		expect(loaded.towers[0].damage>0,"Installation does not freeze loaded gun")
	# Modifiers are bounded, serialized, frozen per wave, and inherited by children.
	for hp_factor in [.7,1.0,2.0]:
		var s:=Simulation.new();s.visuals=false;s.diagnostics.enabled=false;s.credits=10000;s.next_wave=24
		s.rules={"hp":hp_factor,"money":3.0,"pressure":1.5};s.start_wave()
		s.build(Vector2i(-1,2),"Minigun")
		var e:=s.spawn_enemy("split")
		expect(e.hp==WaveCatalog.rounded(WaveCatalog.generate(24).hp.split*hp_factor),"HP modifier applies to parent")
		expect(is_equal_approx(s.spawn_interval,Balance.cfg.spawn_interval/1.5),"Difficulty changes stream pressure")
		s.rules.hp=1.0;s.rules.money=.25
		s.hit(e,1e9,s.towers[0])
		for child in s.enemies:
			if child.kind=="child":
				expect(child.hp==WaveCatalog.rounded(WaveCatalog.generate(24).hp.child*hp_factor),"Child retains wave HP setting")
				expect(child.reward==maxi(1,WaveCatalog.rounded(WaveCatalog.generate(24).reward.child*3)),"Child retains wave reward setting")
		var restored:=Simulation.new()
		expect(restored.restore(JSON.parse_string(JSON.stringify(s.snapshot(true)))),"Settings slot loads")
		expect(restored.rules==s.rules and restored.wave_rules==s.wave_rules,"Current and next wave settings persist separately")
	var last:=0
	for wave in range(1,101):
		var hp: int=WaveCatalog.generate(wave).hp.normal
		expect(hp>last,"HP increases on every wave")
		last=hp
	for kind in ["Minigun","Rocket"]:
		var previous:=0.0
		var step_size:=1.75/9 if kind=="Minigun" else 2.25/9
		for level in range(1,11):
			var t: Dictionary={"kind":kind,"level":level,"mega":false,"ultimate":false}
			var r:=Balance.reach(t)
			if level>1:expect(is_equal_approx(r-previous,step_size),"Uniform reach step "+kind)
			previous=r
		expect(is_equal_approx(previous,3.0 if kind=="Minigun" else 4.0),"Maximum radius reduced by one hex")
	var report: Dictionary={"checks":checks,"failures":failures,"reload_cases":reload_rows}
	var file:=FileAccess.open("res://tests/patch04-tests.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	print("PATCH04: ",checks," checks; ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
