class_name EngineErrorLogger
extends Logger

var pending: Array=[]
var lock:=Mutex.new()
var directory:=""

func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, script_backtraces: Array[ScriptBacktrace]) -> void:
	var stack: Array=[]
	for trace in script_backtraces: stack.append(str(trace))
	lock.lock()
	if not directory.is_empty():
		var filename:=directory.path_join("engine_errors.jsonl")
		if FileAccess.file_exists(filename) and FileAccess.get_file_as_bytes(filename).size()>262144:
			var backup:=filename+".1"
			if FileAccess.file_exists(backup):DirAccess.remove_absolute(backup)
			DirAccess.rename_absolute(filename,backup)
		var stream:=FileAccess.open(filename,FileAccess.READ_WRITE if FileAccess.file_exists(filename) else FileAccess.WRITE)
		if stream!=null:
			stream.seek_end()
			stream.store_line(JSON.stringify({"function":function,"file":file,"line":line,"code":code,"rationale":rationale,"error_type":error_type,"stack":stack}))
			stream.close()
	if pending.size()<64:
		pending.append({"function":function,"file":file,"line":line,"code":code,"rationale":rationale,"error_type":error_type,"stack":stack})
	lock.unlock()

func drain() -> Array:
	lock.lock()
	var result:=pending.duplicate()
	pending.clear()
	lock.unlock()
	return result
