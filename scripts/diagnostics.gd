class_name CombatDiagnostics
extends RefCounted

const MAX_BYTES:=524288
const MAX_RING:=160
var enabled:=true
var directory:=""
var events: FileAccess
var errors: FileAccess
var ring: Array=[]
var actions: Array=[]
var counts: Dictionary={}
var warnings: Dictionary={}
var last_sample: Dictionary={}
var metadata: Dictionary={}
var snapshot_clock:=0.0
var previous_damage:=0.0
var sequence:=0
var frames:=0
var fps_sum:=0.0
var last_export:=""

func _init(seed: int = 1) -> void:
	metadata={"version":"0.3.0","build":"patch03","source_base":"a83279afc0864655a0e17073328e959856371713","godot":Engine.get_version_info().string,
		"platform":OS.get_name(),"os_version":OS.get_version(),"model":OS.get_model_name(),"screen":str(DisplayServer.screen_get_size()),
		"seed":str(seed),"match_id":"%d-%d"%[int(Time.get_unix_time_from_system()),seed],"balance_id":Balance.cfg.get("balance_id","unknown"),
		"timestamp_utc":Time.get_datetime_string_from_system(true),"replay":"seed and player action timeline; exact deterministic replay UI is not implemented"}
	if FileAccess.file_exists("res://data/build_info.json"):
		metadata.source_build=JSON.parse_string(FileAccess.get_file_as_string("res://data/build_info.json"))

func attach(base: String) -> void:
	directory=base
	DirAccess.make_dir_recursive_absolute(directory)
	# Keep four bounded event generations. Files belong to the current user game only.
	rotate("events.jsonl",3)
	rotate("errors.jsonl",1)
	events=FileAccess.open(directory.path_join("events.jsonl"),FileAccess.WRITE)
	errors=FileAccess.open(directory.path_join("errors.jsonl"),FileAccess.WRITE)
	emit("metadata",0,metadata,true)

func rotate(name: String, generations: int) -> void:
	for i in range(generations,0,-1):
		var target:=directory.path_join(name+"."+str(i))
		var source:=directory.path_join(name+("" if i==1 else "."+str(i-1)))
		if FileAccess.file_exists(target): DirAccess.remove_absolute(target)
		if FileAccess.file_exists(source): DirAccess.rename_absolute(source,target)

func emit(kind: String, time: float, context: Dictionary = {}, important: bool = false) -> void:
	if not enabled: return
	counts[kind]=int(counts.get(kind,0))+1
	var key:=kind+":"+str(context.get("tower_id",context.get("id",0)))
	if not important and time-float(last_sample.get(key,-100))<.75: return
	last_sample[key]=time
	sequence+=1
	var record:={"seq":sequence,"event":kind,"game_time":snappedf(time,.0001),"data":StateCodec.encode(context)}
	ring.append(record)
	if ring.size()>MAX_RING: ring.pop_front()
	if events!=null:
		if events.get_position()>MAX_BYTES:
			events.close(); rotate("events.jsonl",3)
			events=FileAccess.open(directory.path_join("events.jsonl"),FileAccess.WRITE)
		events.store_line(JSON.stringify(record))
		if important: events.flush()

func action(kind: String, time: float, context: Dictionary = {}) -> void:
	if not enabled: return
	var record:={"action":kind,"game_time":time,"data":StateCodec.encode(context)}
	actions.append(record)
	if actions.size()>10000: actions.pop_front()
	emit(kind,time,context,true)

func issue(code: String, time: float, context: Dictionary = {}, stack: Array = []) -> void:
	if not enabled: return
	warnings[code]=int(warnings.get(code,0))+1
	if int(warnings[code])>3 and int(warnings[code])%100!=0: return
	var record:={"code":code,"game_time":time,"context":StateCodec.encode(context),"stack":stack,"recent_events":ring.slice(maxi(0,ring.size()-16))}
	if errors!=null:
		if errors.get_position()>MAX_BYTES:
			errors.close(); rotate("errors.jsonl",1)
			errors=FileAccess.open(directory.path_join("errors.jsonl"),FileAccess.WRITE)
		errors.store_line(JSON.stringify(record)); errors.flush()
	emit("warning",time,{"code":code,"context":context},true)

func tower_context(t: Dictionary) -> Dictionary:
	var p:=HexMap.point(t.cell)
	return {"tower_id":t.id,"class":t.kind,"level":t.level,"cell":t.cell,"world_position":p,
		"range_world":Balance.reach(t),"range_hex":Balance.reach(t),"target":t.get("target_id",-1),"target_distance":t.get("target_distance",-1),
		"last_shot":t.get("last_shot",-1),"cooldown":t.cd,"job":t.job,"job_left":t.job_left,"ultimate":t.ultimate,"mega":t.mega,
		"shots":t.get("shots",0),"hits":t.get("hits",0),"damage_attempted":t.get("attempted",0),"damage_effective":t.damage,"overkill":t.get("overkill",0),
		"boss_damage":t.get("boss_damage",0),"kills":t.kills,"expected_attacks":t.get("expected_attacks",0),"idle_seconds":t.get("idle_seconds",{})}

func idle(t: Dictionary, reason: String, delta: float, time: float) -> void:
	if not t.has("idle_seconds"): t.idle_seconds={}
	t.idle_seconds[reason]=float(t.idle_seconds.get(reason,0))+delta
	if t.get("idle_reason","")!=reason:
		t.idle_reason=reason
		emit("idle_reason",time,{"tower_id":t.id,"reason":reason})

func tick(s, delta: float) -> void:
	if not enabled: return
	snapshot_clock+=delta
	if snapshot_clock<5: return
	var dps: float=(s.total_damage-previous_damage)/snapshot_clock
	snapshot_clock=0
	previous_damage=s.total_damage
	var idle_counts: Dictionary={}
	for t in s.towers:
		var reason: String=t.get("idle_reason","NO_TARGET")
		idle_counts[reason]=int(idle_counts.get(reason,0))+1
		emit("tower_snapshot",s.time,tower_context(t))
	emit("snapshot",s.time,{"wave":s.next_wave,"enemies":s.enemies.size(),"towers":s.towers.size(),"projectiles":s.projectiles.size(),"dps_5s":dps,
		"fps":Engine.get_frames_per_second(),"idle":idle_counts,"memory_free":OS.get_memory_info().get("free",-1)},true)

func frame(speed: int) -> void:
	frames+=1
	fps_sum+=Engine.get_frames_per_second()
	metadata.speed=speed

func summary(s) -> Dictionary:
	var towers: Array=[]
	for t in s.tower_history.values(): towers.append(tower_context(t).merged({"invested":t.invested,"status":t.status,"damage_per_credit":t.damage/maxf(1,t.invested)}))
	return {"metadata":metadata,"time":s.time,"wave":s.next_wave,"base_hp":s.base_hp,"credits":s.credits,"earned":s.total_earned,"spent":s.total_spent,
		"damage_effective":s.total_damage,"kills":s.total_kills,"mean_fps":fps_sum/maxi(1,frames),"towers":towers,"waves":s.history,
		"current_wave":s.wave_stats,"active_enemies":StateCodec.encode(s.enemies),
		"event_counts":counts,"warnings":warnings,"warning_top10":top_warnings(),"actions":actions,"recent_events":ring}

func top_warnings() -> Array:
	var result: Array=[]
	for code in warnings: result.append({"code":code,"count":warnings[code]})
	result.sort_custom(func(a,b): return a.count>b.count)
	return result.slice(0,mini(10,result.size()))

func write_summary(s) -> void:
	if directory.is_empty(): return
	var file:=FileAccess.open(directory.path_join("match_summary.json"),FileAccess.WRITE)
	if file!=null: file.store_string(JSON.stringify(StateCodec.encode(summary(s)),"  "))
	if events!=null: events.flush()
	if errors!=null: errors.flush()

func export_zip(s) -> String:
	if directory.is_empty(): attach("user://diagnostics")
	write_summary(s)
	var csv:=FileAccess.open(directory.path_join("balance_report.csv"),FileAccess.WRITE)
	csv.store_csv_line(PackedStringArray(["wave","hp_pool","effective_damage","income","spend","leaks","boss_hp_at_exit","median_death_path_fraction","seconds"]))
	for w in s.history:
		csv.store_csv_line(PackedStringArray([str(w.wave),str(w.enemy_hp),str(w.damage),str(w.earned),str(w.spent),str(w.leaked),str(w.get("boss_exit_hp",0)),str(w.get("median_death_fraction",0)),str(w.seconds)]))
	csv.close()
	var json:=FileAccess.open(directory.path_join("balance_report.json"),FileAccess.WRITE)
	json.store_string(JSON.stringify(StateCodec.encode(summary(s)),"  ")); json.close()
	var out:="user://exports"
	DirAccess.make_dir_recursive_absolute(out)
	last_export=out.path_join("GeometryDefense-03-report.zip")
	var pack:=ZIPPacker.new()
	if pack.open(last_export)!=OK: return ""
	for name in DirAccess.get_files_at(directory):
		pack.start_file(name)
		pack.write_file(FileAccess.get_file_as_bytes(directory.path_join(name)))
		pack.close_file()
	pack.close()
	return ProjectSettings.globalize_path(last_export)

func close() -> void:
	if events!=null: events.close(); events=null
	if errors!=null: errors.close(); errors=null
