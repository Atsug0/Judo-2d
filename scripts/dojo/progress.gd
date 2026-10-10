extends RefCounted
## Progression du dojo (leçons réussies), sauvegardée dans user://dojo.json.

const PATH := "user://dojo.json"
static var _done := {}
static var _loaded := false


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	if FileAccess.file_exists(PATH):
		var f = FileAccess.open(PATH, FileAccess.READ)
		var d = JSON.parse_string(f.get_as_text())
		if typeof(d) == TYPE_DICTIONARY:
			_done = d.get("done", {})


static func is_done(id: String) -> bool:
	_load()
	return _done.get(id, false)


static func mark_done(id: String) -> void:
	_load()
	_done[id] = true
	var f = FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"done": _done}, "  "))


static func count_done(ids: Array) -> int:
	var n = 0
	for id in ids:
		if is_done(id):
			n += 1
	return n
