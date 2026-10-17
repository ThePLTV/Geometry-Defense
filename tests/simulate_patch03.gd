extends SceneTree

var strategy:="mixed"
var seeds:=3
var max_wave:=100
var out:="res://tests/patch03-simulation.json"
const STRATEGIES=["mixed","minigun","laser","rocket","shockwave","upgrades","expansion","economy","ultimates","fusion"]

func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--strategy="):strategy=a.get_slice("=",1)
		elif a.begins_with("--seeds="):seeds=int(a.get_slice("=",1))
		elif a.begins_with("--max-wave="):max_wave=int(a.get_slice("=",1))
		elif a.begins_with("--report="):out=a.trim_prefix("--report=")
	call_deferred("run")

func coverage(s: Simulation, cell: Vector2i, radius: float) -> float:
	var score:=0.0
	var route:=s.map.route(s.map.spawn)
	for index in route.size():
		var d:=HexMap.point(cell).distance_to(HexMap.point(route[index]))
		if d<=radius:
			score+=1+(radius-d)*.1
	for t in s.towers:
		if HexMap.point(t.cell).distance_to(HexMap.point(cell))<1.8:score*=.84
	return score

func cell_for(s: Simulation, kind: String) -> Vector2i:
	var best:=Vector2i(999,999)
	var score:=-1.0
	for cell in s.map.cells:
		if not s.map.validate_build(cell,[]).is_empty():continue
		var value:=coverage(s,cell,Balance.tower(kind).range)
		if value>score:score=value;best=cell
	return best

func dps(t: Dictionary) -> float:
	var area:=1.8 if t.kind=="Laser" else 1.4 if t.kind in ["Rocket","Shockwave"] else 1.0
	return Balance.damage(t)*Balance.rate(t)*Balance.volley(t)*area

func bias(kind: String) -> float:
	return 4.0 if strategy==kind.to_lower() else 1.0

func buy(s: Simulation) -> void:
	var reserve:=mini(200,s.next_wave*2) if strategy=="economy" and s.next_wave>10 else 0
	# A single level-2 starter leaves enough budget to save for a different class.
	if s.next_wave==1:
		for initial in 1:
			var cell:=cell_for(s,"Minigun")
			if cell.x!=999:
				s.build(cell,"Minigun")
				s.upgrade(s.towers[-1].id)
	for attempt in 80:
		var best:=0.0
		var choice: Dictionary={}
		var class_count: Dictionary={}
		for t in s.towers:class_count[t.kind]=int(class_count.get(t.kind,0))+1
		var required_classes:=2 if s.next_wave>=2 else 1
		if s.next_wave>=8:required_classes=3
		if s.next_wave>=15:required_classes=4
		if class_count.size()<required_classes:
			var missing:=""
			var best_missing:=-1.0
			for kind in Balance.KINDS:
				if class_count.has(kind):continue
				var initial:={"kind":kind,"level":1,"ultimate":false,"mega":false}
				var value: float=dps(initial)/Balance.tower(kind).price*bias(kind)
				if value>best_missing:best_missing=value;missing=kind
			if not missing.is_empty() and s.credits>=int(Balance.tower(missing).price):
				var cell:=cell_for(s,missing)
				if cell.x!=999:s.build(cell,missing);continue
			break
		for t in s.towers:
			if not t.job.is_empty() or t.mega:continue
			if t.level<10:
				var cost:=Balance.upgrade_cost(t.kind,t.level+1)
				var next: Dictionary=t.duplicate();next.level+=1
				var reach_gain:=pow(Balance.reach(next)/Balance.reach(t),.7)
				var value:=(dps(next)*reach_gain-dps(t))/cost*bias(t.kind)
				if strategy in ["upgrades","ultimates","fusion"]:value*=1.45
				if class_count.size()<2 and s.next_wave>=4:value*=.1
				if s.next_wave%5==0 and t.kind!=Balance.boss(s.next_wave).immune:value*=6.0
				if cost<=s.credits-reserve and value>best:best=value;choice={"type":"upgrade","id":t.id}
			elif not t.ultimate:
				var cost:=Balance.ultimate_cost(t.kind)
				var value:=dps(t)*(.5 if t.kind!="Laser" else 1.2)/cost
				if strategy in ["ultimates","fusion"]:value*=2
				if cost<=s.credits-reserve and value>best:best=value;choice={"type":"ultimate","id":t.id}
		for kind in Balance.KINDS:
			var cost:=int(Balance.tower(kind).price)
			if cost>s.credits-reserve or s.towers.size()>=24:continue
			var t:={"kind":kind,"level":1,"ultimate":false,"mega":false}
			var value:=dps(t)/cost*bias(kind)*(.8 if s.towers.size()>=3 else 1.2)
			if strategy=="expansion":value*=1.8
			if strategy in ["upgrades","ultimates","fusion"]:value*=.7
			if class_count.size()<2 and s.next_wave>=4 and not class_count.has(kind):value*=5
			if class_count.size()<3 and s.next_wave>=8 and not class_count.has(kind):value*=3.5
			if class_count.size()<4 and s.next_wave>=15 and not class_count.has(kind):value*=3
			if value>best:
				var cell:=cell_for(s,kind)
				if cell.x!=999:best=value;choice={"type":"build","kind":kind,"cell":cell}
		if choice.is_empty():break
		match choice.type:
			"build":s.build(choice.cell,choice.kind)
			"upgrade":s.upgrade(choice.id)
			"ultimate":s.buy_ultimate(choice.id)
	if strategy=="fusion":
		for a in s.towers.duplicate():
			for b in s.towers.duplicate():
				if s.can_merge(a,b):s.merge(a.id,b.id);return

func run() -> void:
	var all: Array=[]
	var start:=Time.get_ticks_msec()
	for seed_index in seeds:
		var s:=Simulation.new(seed_index+1)
		s.visuals=false
		s.diagnostics.enabled=false
		var stalled:=false
		while s.next_wave<=max_wave and not s.defeated:
			if s.next_wave%10==0:print("WAVE ",strategy," ",s.next_wave)
			buy(s)
			for tick in 200:s.step(.025)
			s.start_wave()
			var tick:=0
			while s.active and tick<12000:
				s.step(.025);tick+=1
			if s.active:stalled=true;break
		all.append({"seed":seed_index+1,"last_completed":s.next_wave-1,"defeated":s.defeated,"hp":s.base_hp,"credits":s.credits,
			"earned":s.total_earned,"spent":s.total_spent,"towers":StateCodec.encode(s.towers),"waves":s.history,"failed_wave":s.wave_stats.merged({"seconds":s.wave_time,"hp_end":s.base_hp}) if s.defeated else {},"timeout":stalled})
		print("PATCH03 SIM ",strategy," seed ",seed_index+1," completed ",s.next_wave-1," hp ",s.base_hp)
	var passed:=0
	for result in all:
		if result.last_completed>=max_wave:passed+=1
	var report:={"strategy":strategy,"balance_id":Balance.cfg.balance_id,"seeds":seeds,"max_wave":max_wave,"passed":passed,"seconds":(Time.get_ticks_msec()-start)/1000.0,"rows":all}
	var file:=FileAccess.open(out,FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	print("RESULT ",strategy," ",passed,"/",seeds," passed ",max_wave," waves")
	quit()
