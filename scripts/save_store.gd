class_name SaveStore
extends RefCounted

static var directory := "user://"

static func path(slot: int) -> String:
	return directory.path_join("slot_%d.json" % slot)

static func decode(filename: String) -> Dictionary:
	if not FileAccess.file_exists(filename):
		return {}
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(filename)) != OK:
		return {}
	var envelope = parser.data
	if envelope is not Dictionary or not envelope.has("payload") or not envelope.has("sha256"):
		return {}
	if envelope.payload is not String or envelope.sha256 is not String:
		return {}
	if str(envelope.payload).sha256_text() != str(envelope.sha256):
		return {}
	if parser.parse(envelope.payload) != OK:
		return {}
	var data = parser.data
	if data is not Dictionary or int(data.get("schema",0)) not in [2,3]:
		return {}
	return data

static func load_slot(slot: int) -> Dictionary:
	if slot < 1 or slot > 5:
		return {}
	var data := decode(path(slot))
	return decode(path(slot)+".bak") if data.is_empty() else data

static func save_slot(slot: int, state: Dictionary) -> String:
	if state.get("active",false):
		return "Активная волна не является чекпоинтом"
	return write_state(path(slot),slot,state)

static func write_state(filename: String, slot: int, state: Dictionary) -> String:
	if slot < 1 or slot > 5 or int(state.get("base_hp",0)) <= 0:
		return "Некорректное сохранение"
	var payload := JSON.stringify(state)
	var envelope := {"payload":payload,"sha256":payload.sha256_text()}
	var temporary := filename + ".tmp"
	var backup := filename + ".bak"
	var file := FileAccess.open(temporary,FileAccess.WRITE)
	if file == null:
		return "Не удалось записать сохранение"
	file.store_string(JSON.stringify(envelope))
	file.flush()
	file.close()
	if decode(temporary).is_empty():
		return "Ошибка проверки сохранения"
	if FileAccess.file_exists(filename):
		# Keep a complete valid previous generation. Never replace a valid backup
		# with a corrupt main file.
		if not decode(filename).is_empty():
			var copy_error := DirAccess.copy_absolute(filename,backup)
			if copy_error != OK:
				return "Не удалось создать резервную копию"
	var error := DirAccess.rename_absolute(temporary,filename)
	return "" if error == OK else "Не удалось заменить сохранение (%d)" % error

static func session_path(slot: int) -> String:
	return directory.path_join("session_%d.json" % slot)

static func save_session(slot: int, state: Dictionary) -> String:
	return write_state(session_path(slot),slot,state)

static func load_session(slot: int) -> Dictionary:
	var data := decode(session_path(slot))
	return decode(session_path(slot)+".bak") if data.is_empty() else data

static func clear_session(slot: int) -> void:
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(session_path(slot)+suffix):
			DirAccess.remove_absolute(session_path(slot)+suffix)
