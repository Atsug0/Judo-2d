extends RefCounted
## Chargement des fichiers de données JSON.
## Les nombres entiers du JSON sont convertis en int pour que la simulation
## reste 100 % en arithmétique entière (déterminisme, rollback).


static func load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Impossible d'ouvrir %s" % path)
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("JSON invalide : %s" % path)
		return {}
	return _to_ints(parsed)


static func _to_ints(v):
	match typeof(v):
		TYPE_FLOAT:
			if v == floor(v):
				return int(v)
			return v
		TYPE_DICTIONARY:
			var d := {}
			for k in v:
				d[k] = _to_ints(v[k])
			return d
		TYPE_ARRAY:
			var a := []
			for item in v:
				a.append(_to_ints(item))
			return a
	return v
