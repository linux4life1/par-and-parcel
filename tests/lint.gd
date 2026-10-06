extends Node
## Loads every script so parse errors show up in seconds.

func _ready() -> void:
	var bad := 0
	for path in _scripts("res://scripts"):
		var s: Variant = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_REUSE)
		if s == null or not (s is GDScript) or not (s as GDScript).can_instantiate():
			print("LINT FAIL: ", path)
			bad += 1
	print("LINT %s" % ("OK" if bad == 0 else "FAILED (%d)" % bad))
	get_tree().quit(bad)


func _scripts(dir: String) -> Array[String]:
	var out: Array[String] = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir + "/" + f)
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_scripts(dir + "/" + d))
	return out
