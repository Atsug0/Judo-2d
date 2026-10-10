extends RefCounted
## Design system — direction artistique inspirée de 2XKO :
## panneaux inclinés, gros contours d'encre, couleurs saturées,
## typographie grasse condensée en italique, trames et éclats façon BD.
## Toutes les fonctions dessinent sur un CanvasItem passé en paramètre.

# --- Palette -----------------------------------------------------------------
const INK := Color("0b0a14")          # contours, ombres portées
const NIGHT := Color("161131")        # fond profond
const NIGHT_2 := Color("231b4d")      # fond de panneau
const NIGHT_3 := Color("33296b")      # panneau survolé
const PAPER := Color("f6f1e3")        # texte clair, judogi blanc
const MUTED := Color("a49fc4")        # texte secondaire
const P1 := Color("ffd23f")           # accent joueur 1 (judogi blanc) : jaune électrique
const P1_DEEP := Color("ff8a1f")
const P2 := Color("3de7ff")           # accent joueur 2 (judogi bleu) : cyan
const P2_DEEP := Color("2e6bff")
const HOT := Color("ff2e88")          # accent global : magenta
const GOOD := Color("b6ff3b")         # validation, endurance pleine
const DANGER := Color("ff3b3b")
const GOLD := Color("ffc21a")         # ippon
const GI_WHITE := Color("f3efe4")
const GI_WHITE_SHADE := Color("c9c2b4")
const GI_BLUE := Color("2a5fe0")
const GI_BLUE_SHADE := Color("1b3c9c")
const SKIN_A := Color("e7b78f")
const SKIN_A_SHADE := Color("c08a63")
const SKIN_B := Color("9a6440")
const SKIN_B_SHADE := Color("744528")
const MAT_COMBAT := Color("f2c53d")
const MAT_COMBAT_SHADE := Color("d19f1c")
const MAT_SAFETY := Color("2b5bd8")
const MAT_SAFETY_SHADE := Color("1d3f9e")

const SLANT := 0.22  # inclinaison des panneaux (décalage horizontal / hauteur)

static var _fonts := {}


# --- Polices -----------------------------------------------------------------
## "display" : titres, très gras, italique condensé. "ui" : texte courant.
static func font(kind: String = "ui") -> Font:
	if _fonts.has(kind):
		return _fonts[kind]
	var f: Font
	match kind:
		"display":
			var v := FontVariation.new()
			v.base_font = load("res://fonts/InterDisplay-BlackItalic.otf")
			v.variation_transform = Transform2D(Vector2(0.84, 0), Vector2(0, 1), Vector2.ZERO)
			v.spacing_glyph = -1
			f = v
		"display_x":
			var v := FontVariation.new()
			v.base_font = load("res://fonts/InterDisplay-ExtraBoldItalic.otf")
			v.variation_transform = Transform2D(Vector2(0.86, 0), Vector2(0, 1), Vector2.ZERO)
			f = v
		"black":
			f = load("res://fonts/Inter-Black.otf")
		"bold":
			f = load("res://fonts/Inter-Bold.otf")
		_:
			f = load("res://fonts/Inter-SemiBold.otf")
	_fonts[kind] = f
	return f


# --- Texte -------------------------------------------------------------------
## Texte avec contour d'encre et ombre portée décalée (effet sticker).
static func text(ci: CanvasItem, pos: Vector2, s: String, size: int, color: Color,
		kind: String = "display", align: int = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1,
		outline: int = 0, shadow: float = 0.0) -> void:
	var f := font(kind)
	if outline <= 0:
		outline = maxi(2, size / 7)
	if shadow == 0.0:
		shadow = maxf(2.0, size / 12.0)
	if shadow > 0.0:
		ci.draw_string_outline(f, pos + Vector2(shadow, shadow), s, align, width, size, outline, INK)
		ci.draw_string(f, pos + Vector2(shadow, shadow), s, align, width, size, INK)
	ci.draw_string_outline(f, pos, s, align, width, size, outline, INK)
	ci.draw_string(f, pos, s, align, width, size, color)


## Texte simple, sans contour (petits libellés sur fond uni).
static func label(ci: CanvasItem, pos: Vector2, s: String, size: int, color: Color,
		kind: String = "ui", align: int = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1) -> void:
	ci.draw_string(font(kind), pos, s, align, width, size, color)


static func text_width(s: String, size: int, kind: String = "display") -> float:
	return font(kind).get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


# --- Formes ------------------------------------------------------------------
## Parallélogramme incliné (forme de base de toute l'interface).
static func slant_points(r: Rect2, slant: float = SLANT, flip: bool = false) -> PackedVector2Array:
	var o := r.size.y * slant
	if flip:
		return PackedVector2Array([r.position, Vector2(r.end.x - o, r.position.y), r.end, Vector2(r.position.x + o, r.end.y)])
	return PackedVector2Array([Vector2(r.position.x + o, r.position.y), Vector2(r.end.x, r.position.y),
		Vector2(r.end.x - o, r.end.y), Vector2(r.position.x, r.end.y)])


## Panneau incliné : ombre d'encre décalée, remplissage, contour épais.
static func panel(ci: CanvasItem, r: Rect2, fill: Color, border: Color = INK, border_w: float = 4.0,
		shadow: float = 6.0, slant: float = SLANT, flip: bool = false) -> void:
	if shadow > 0.0:
		ci.draw_colored_polygon(slant_points(Rect2(r.position + Vector2(shadow, shadow), r.size), slant, flip), INK)
	var pts := slant_points(r, slant, flip)
	ci.draw_colored_polygon(pts, fill)
	if border_w > 0.0:
		var closed := pts.duplicate()
		closed.append(pts[0])
		ci.draw_polyline(closed, border, border_w, true)


## Barre de jauge inclinée (endurance, budget…), remplie de droite à gauche si flip.
static func gauge(ci: CanvasItem, r: Rect2, ratio: float, color: Color, flip: bool = false, back: Color = NIGHT) -> void:
	panel(ci, r, back, INK, 3.0, 3.0, SLANT, flip)
	ratio = clampf(ratio, 0.0, 1.0)
	if ratio <= 0.0:
		return
	var inner := r.grow(-4)
	var w := inner.size.x * ratio
	var fr := Rect2(inner.position, Vector2(w, inner.size.y))
	if flip:
		fr.position.x = inner.end.x - w
	ci.draw_colored_polygon(slant_points(fr, SLANT, flip), color)
	# reflet
	var hl := Rect2(fr.position, Vector2(fr.size.x, fr.size.y * 0.35))
	ci.draw_colored_polygon(slant_points(hl, SLANT * 2.8, flip), Color(1, 1, 1, 0.22))


## Trame de points (halftone) dans un rectangle, densité décroissante selon la direction.
static func halftone(ci: CanvasItem, r: Rect2, color: Color, step: float = 14.0, max_r: float = 4.0, dir: Vector2 = Vector2(1, 0)) -> void:
	var y := r.position.y
	var row := 0
	while y < r.end.y:
		var x := r.position.x + (step * 0.5 if row % 2 == 1 else 0.0)
		while x < r.end.x:
			var fx := (x - r.position.x) / r.size.x
			var fy := (y - r.position.y) / r.size.y
			var t := fx
			if dir.x < 0:
				t = 1.0 - fx
			elif dir.x == 0:
				t = fy if dir.y > 0 else 1.0 - fy
			var rad := max_r * (1.0 - clampf(t, 0.0, 1.0))
			if rad > 0.4:
				ci.draw_circle(Vector2(x, y), rad, color)
			x += step
		y += step * 0.86
		row += 1


## Éclat d'impact façon BD (étoile irrégulière déterministe).
static func burst(ci: CanvasItem, c: Vector2, r_in: float, r_out: float, spikes: int, fill: Color,
		border: Color = INK, seed_value: int = 7, rot: float = 0.0) -> void:
	var pts := PackedVector2Array()
	var s := seed_value
	for k in spikes * 2:
		s = (s * 1103515245 + 12345) & 0x7fffffff
		var jitter := 0.78 + float(s % 1000) / 1000.0 * 0.44
		var rad := (r_out if k % 2 == 0 else r_in) * jitter
		var a := rot + TAU * float(k) / float(spikes * 2)
		pts.append(c + Vector2(cos(a), sin(a)) * rad)
	var shadow := PackedVector2Array()
	for p in pts:
		shadow.append(p + Vector2(6, 6))
	ci.draw_colored_polygon(shadow, INK)
	ci.draw_colored_polygon(pts, fill)
	var closed := pts.duplicate()
	closed.append(pts[0])
	ci.draw_polyline(closed, border, 4.0, true)


## Traits de vitesse (speed lines) rayonnants.
static func speed_lines(ci: CanvasItem, c: Vector2, r_in: float, r_out: float, count: int, color: Color, seed_value: int = 3) -> void:
	var s := seed_value
	for k in count:
		s = (s * 1103515245 + 12345) & 0x7fffffff
		var a := TAU * float(k) / float(count) + float(s % 100) / 100.0 * 0.08
		var len_j := 0.7 + float((s >> 8) % 100) / 100.0 * 0.3
		var d := Vector2(cos(a), sin(a))
		var w := 2.0 + float((s >> 4) % 4)
		ci.draw_line(c + d * r_in, c + d * (r_in + (r_out - r_in) * len_j), color, w)


## Rectangle à coins arrondis via polygone (pour les petits chips).
static func chip(ci: CanvasItem, r: Rect2, fill: Color, border: Color = INK) -> void:
	panel(ci, r, fill, border, 3.0, 3.0, 0.12)


## Bouton de manette stylisé (A/B/X/Y, LT, RT…), couleurs façon Xbox.
static func pad_button(ci: CanvasItem, c: Vector2, name: String, size: float = 13.0) -> void:
	var col := MUTED
	match name:
		"A":
			col = Color("47d16b")
		"B":
			col = Color("ff5050")
		"X":
			col = Color("3d8bff")
		"Y":
			col = Color("ffcf33")
	if name.length() == 1:
		ci.draw_circle(c + Vector2(2, 2), size, INK)
		ci.draw_circle(c, size, col)
		ci.draw_arc(c, size, 0, TAU, 32, INK, 2.5, true)
		var fs := int(size * 1.15)
		ci.draw_string(font("black"), c + Vector2(-size, fs * 0.36), name, HORIZONTAL_ALIGNMENT_CENTER, size * 2, fs, INK)
	else:
		var w := size * 2.6
		var r := Rect2(c - Vector2(w / 2, size * 0.8), Vector2(w, size * 1.6))
		ci.draw_rect(Rect2(r.position + Vector2(2, 2), r.size), INK)
		ci.draw_rect(r, Color("d8d4ea"))
		ci.draw_rect(r, INK, false, 2.0)
		var fs := int(size * 0.95)
		ci.draw_string(font("black"), Vector2(r.position.x, c.y + fs * 0.36), name, HORIZONTAL_ALIGNMENT_CENTER, w, fs, INK)


## Fond d'écran de menu : dégradé nuit, grandes bandes inclinées, trame.
static func menu_background(ci: CanvasItem, size: Vector2, accent: Color = HOT, t: float = 0.0) -> void:
	ci.draw_rect(Rect2(Vector2.ZERO, size), NIGHT)
	# grandes bandes diagonales
	var bands := [[0.55, 0.30, NIGHT_2], [0.78, 0.12, accent.darkened(0.55)], [0.93, 0.05, accent]]
	for b in bands:
		var x0: float = size.x * b[0]
		var w: float = size.x * b[1]
		var pts := PackedVector2Array([Vector2(x0, 0), Vector2(x0 + w, 0),
			Vector2(x0 + w - size.y * 0.45, size.y), Vector2(x0 - size.y * 0.45, size.y)])
		ci.draw_colored_polygon(pts, b[2])
	halftone(ci, Rect2(size.x * 0.45, 0, size.x * 0.55, size.y), Color(1, 1, 1, 0.05), 16.0, 4.0, Vector2(-1, 0))
	halftone(ci, Rect2(0, size.y * 0.55, size.x * 0.5, size.y * 0.45), Color(0, 0, 0, 0.35), 14.0, 4.5, Vector2(0, -1))
