extends SceneTree

var checks:=0
var failures: Array=[]
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:failures.append(message);printerr("FAIL ",message)
func _init() -> void:call_deferred("run")
func run() -> void:
	SaveStore.directory="user://music041_"+str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(SaveStore.directory)
	# A 0.4 installation with any old numeric selection adopts the title track.
	var prefs:=ConfigFile.new()
	prefs.set_value("audio","track",2)
	prefs.set_value("audio","volume",.37)
	prefs.save(SaveStore.directory.path_join("preferences.cfg"))
	var game=load("res://main.tscn").instantiate();root.add_child(game)
	await process_frame
	game.set_process(false)
	check(game.music_index==0 and game.TRACKS[0].id=="jazz_noir","New default overrides legacy numeric selection once")
	check(game.music.stream.resource_path.ends_with("jazz_noir.ogg"),"Title song actually loaded")
	check(game.music.playing and game.music.stream.loop,"Title song plays and loops")
	check(absf(game.music.stream.get_length()-4910.441)<.1,"Entire 81-minute mix retained")
	check(is_equal_approx(game.music_volume,.37),"Existing volume preserved")
	check(game.TRACKS.size()==4,"Four selectable tracks")
	for i in game.TRACKS.size():
		game.select_music(i)
		check(game.music.stream!=null and game.music.stream.loop,"Track selectable and looped "+str(i))
		var expected: String=game.TRACKS[i].id
		game.music_index=0;game.load_preferences()
		check(game.TRACKS[game.music_index].id==expected,"Stable track ID survives reload "+expected)
	game.show_settings();game.show_settings_page("audio")
	await process_frame;await process_frame
	var picker: OptionButton=game.find_child("MusicTracks",true,false)
	check(picker!=null and picker.item_count==4,"Settings offer title track and all three previous songs")
	game.music.stop();game.music.stream=null
	await create_timer(.15).timeout
	root.remove_child(game);game.free();await process_frame
	var file:=FileAccess.open("res://tests/patch041-music.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures},"  "));file.close()
	print("MUSIC041: ",checks," checks; ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
