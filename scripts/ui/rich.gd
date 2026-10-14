extends RefCounted
## Texte riche avec boutons de manette : « Appuie sur {A} » dessine le bouton A.
## Jetons : {A} {B} {X} {Y} {LT} {RT} {LB} {RB} {LS} {RS}.

const Style := preload("res://scripts/ui/style.gd")
static var _re: RegEx = null


static func _regex() -> RegEx:
	if _re == null:
		_re = RegEx.new()
		_re.compile("\\{(A|B|X|Y|LT|RT|LB|RB|LS|RS)\\}")
	return _re


## Découpe un texte en lignes de segments {kind: "t"|"b", s, w} tenant dans `width`.
static func layout(text: String, width: float, size: int) -> Array:
	var lines = []
	var line = []
	var lw = 0.0
	var space = Style.text_width(" ", size, "bold")
	for word in text.split(" ", false):
		var parts = _split_tokens(word, size)
		var ww = 0.0
		for p in parts:
			ww += p.w
		if lw > 0.0 and lw + space + ww > width:
			lines.append(line)
			line = []
			lw = 0.0
		if lw > 0.0:
			line.append({"kind": "t", "s": " ", "w": space})
			lw += space
		line.append_array(parts)
		lw += ww
	if not line.is_empty():
		lines.append(line)
	return lines


static func _split_tokens(word: String, size: int) -> Array:
	var parts = []
	var pos = 0
	for m in _regex().search_all(word):
		if m.get_start() > pos:
			var s = word.substr(pos, m.get_start() - pos)
			parts.append({"kind": "t", "s": s, "w": Style.text_width(s, size, "bold")})
		var b = m.get_string(1)
		var aff := Style.token(b)        # au clavier, le jeton affiche la touche réglée
		var bw: float = size * 1.3 if aff.length() == 1 else maxf(size * 1.65, Style.text_width(aff, int(size * 0.62), "black") + 12.0)
		parts.append({"kind": "b", "s": b, "w": bw + 4.0})
		pos = m.get_end()
	if pos < word.length():
		var s2 = word.substr(pos)
		parts.append({"kind": "t", "s": s2, "w": Style.text_width(s2, size, "bold")})
	return parts


static func draw_lines(ci: CanvasItem, at: Vector2, lines: Array, size: int, col: Color, lh: float) -> void:
	var y = at.y
	for line in lines:
		var x = at.x
		for p in line:
			if p.kind == "t":
				Style.label(ci, Vector2(x, y), p.s, size, col, "bold")
			else:
				Style.pad_button(ci, Vector2(x + p.w * 0.5 - 1.0, y - size * 0.34), p.s, size * 0.62)
			x += p.w
		y += lh


## Dessine un paragraphe ; renvoie sa hauteur.
static func draw(ci: CanvasItem, at: Vector2, text: String, width: float, size: int, col: Color) -> float:
	var lines = layout(text, width, size)
	draw_lines(ci, at, lines, size, col, size * 1.38)
	return lines.size() * size * 1.38
