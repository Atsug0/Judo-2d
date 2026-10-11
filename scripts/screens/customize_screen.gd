extends Node2D
## Création et personnalisation des judokas : profil (nom, surnom, apparence), set de
## techniques (15 points), garde et style, profil physique. Plusieurs judokas par joueur.

const Style := preload("res://scripts/ui/style.gd")
const Records := preload("res://scripts/records.gd")
const Rich := preload("res://scripts/ui/rich.gd")
const Art := preload("res://scripts/view/fighter_art.gd")
const Build := preload("res://scripts/build.gd")

const TABS := ["PROFIL", "APPARENCE", "TECHNIQUES", "GARDE & STYLE", "PHYSIQUE"]
const PROFILE_ROWS := ["NOM", "SURNOM", "NOUVEAU JUDOKA", "COPIER UNE LÉGENDE", "SUPPRIMER"]
## Apparence : [clé du look, libellé, liste des noms d'options]
const LOOK_ROWS := [["skin", "PEAU", "SKIN_NAMES"], ["hair", "CHEVEUX", "HAIR_STYLES"], ["hair_color", "COULEUR", "HAIR_COLOR_NAMES"],
	["build", "CARRURE", "BUILD_NAMES"], ["face", "VISAGE", "FACE_NAMES"], ["brow", "SOURCILS", "BROW_NAMES"],
	["beard", "BARBE", "BEARD_NAMES"], ["ears", "OREILLES", "EAR_NAMES"], ["belt", "CEINTURE", "BELT_NAMES"], ["trim", "LISERÉ", "TRIM_NAMES"]]
const KB_ROWS := [["A", "B", "C", "D", "E", "F", "G", "H", "I", "J"], ["K", "L", "M", "N", "O", "P", "Q", "R", "S", "T"],
	["U", "V", "W", "X", "Y", "Z", "É", "È", "-", "'"], ["ESPACE", "EFFACER", "OK"]]
const MAX_JUDOKAS := 12
const DIR_LABELS := {"avant": "AVANT", "arriere": "ARRIÈRE", "cote": "CÔTÉ", "arriere_cote": "ARRIÈRE-CÔTÉ",
	"avant_cote": "AVANT-CÔTÉ", "arriere_avant": "ARRIÈRE → AVANT", "cote_avant": "CÔTÉ → AVANT", "sol": "SOL"}
## Pierre-feuille-ciseaux des styles : clé bat valeur.
const STYLE_BEATS := {"haute": "classique", "courte": "haute", "classique": "courte"}

var app
var cat: Dictionary
var builds: Array
var bi = 0
var tab = 0
var row = 0
var frame = 0
var flash = 0
var rows: Array = []  # [[slot_id, index]]
var legend_i = 0
var kb_open = false     # clavier à l'écran (nom, surnom)
var kb_field = "name"
var kb_text = ""
var kb_r = 0
var kb_c = 0


func on_enter(_params: Dictionary) -> void:
	cat = Build.catalog()
	builds = Build.load_all()
	for s in cat.slots:
		for k in s.count:
			rows.append([s.id, k])


func tick() -> void:
	frame += 1
	if flash > 0:
		flash -= 1
	queue_redraw()


func _b() -> Dictionary:
	return builds[bi]


func nav(action: String, _player: int = 0) -> void:
	if kb_open:
		_kb_nav(action)
		queue_redraw()
		return
	match action:
		"prev":
			tab = (tab + TABS.size() - 1) % TABS.size()
			row = 0
		"next":
			tab = (tab + 1) % TABS.size()
			row = 0
		"x":
			bi = (bi + 1) % builds.size()
		"up":
			row = maxi(0, row - 1)
		"down":
			row = mini(_row_count() - 1, row + 1)
		"left":
			_change(-1)
		"right":
			_change(1)
		"accept":
			if tab == 0 and _profile_action():
				pass
			else:
				Build.save_all(builds)
				flash = 60
		"back":
			Build.save_all(builds)
			app.goto("menu", {})
	queue_redraw()


func _row_count() -> int:
	match tab:
		0:
			return PROFILE_ROWS.size()
		1:
			return LOOK_ROWS.size()
		2:
			return rows.size()
		3:
			return 2
	return cat.physique.stats.size()


## Actions du profil (A) : renommer, créer, copier une légende, supprimer. Renvoie true si consommé.
func _profile_action() -> bool:
	match PROFILE_ROWS[row]:
		"NOM", "SURNOM":
			kb_open = true
			kb_field = "name" if PROFILE_ROWS[row] == "NOM" else "nick"
			kb_text = String(_b().get(kb_field, ""))
			kb_r = 0
			kb_c = 0
			return true
		"NOUVEAU JUDOKA":
			if builds.size() < MAX_JUDOKAS:
				builds.append(Build.new_judoka({}, builds.size()))
				bi = builds.size() - 1
				Build.save_all(builds)
			return true
		"COPIER UNE LÉGENDE":
			if builds.size() < MAX_JUDOKAS:
				var lg: Dictionary = Build.legends()[legend_i]
				builds.append(Build.new_judoka(lg, builds.size()))
				bi = builds.size() - 1
				Build.save_all(builds)
			return true
		"SUPPRIMER":
			if builds.size() > 1:
				builds.remove_at(bi)
				bi = mini(bi, builds.size() - 1)
				Build.save_all(builds)
			return true
	return false


func _kb_nav(action: String) -> void:
	match action:
		"up":
			kb_r = (kb_r + KB_ROWS.size() - 1) % KB_ROWS.size()
		"down":
			kb_r = (kb_r + 1) % KB_ROWS.size()
		"left":
			kb_c -= 1
		"right":
			kb_c += 1
		"back":
			kb_text = kb_text.substr(0, maxi(0, kb_text.length() - 1))
		"start":
			_kb_commit()
		"accept":
			var key: String = KB_ROWS[kb_r][clampi(kb_c, 0, KB_ROWS[kb_r].size() - 1)]
			match key:
				"ESPACE":
					if kb_text.length() < 14:
						kb_text += " "
				"EFFACER":
					kb_text = kb_text.substr(0, maxi(0, kb_text.length() - 1))
				"OK":
					_kb_commit()
				_:
					if kb_text.length() < 14:
						kb_text += key
	kb_c = (kb_c + KB_ROWS[kb_r].size()) % KB_ROWS[kb_r].size()


func _kb_commit() -> void:
	var t := kb_text.strip_edges()
	if kb_field == "name" and t == "":
		return
	_b()[kb_field] = t
	kb_open = false
	Build.save_all(builds)


func _change(delta: int) -> void:
	var b = _b()
	match tab:
		0:
			if PROFILE_ROWS[row] == "COPIER UNE LÉGENDE":
				var n: int = Build.legends().size()
				legend_i = (legend_i + delta + n) % n
		1:
			var lk: Dictionary = b.look
			var lr: Array = LOOK_ROWS[row]
			var names: Array = _look_names(lr[2])
			lk[lr[0]] = (int(lk.get(lr[0], 0)) + delta + names.size()) % names.size()
		2:
			var slot_id: String = rows[row][0]
			var k: int = rows[row][1]
			var kind = Build.kind_of(slot_id)
			var options: Array = [""]
			for id in cat[kind]:
				options.append(id)
			var cur: String = b.slots[slot_id][k]
			var idx = options.find(cur)
			for step in options.size():
				idx = (idx + delta + options.size()) % options.size()
				var cand: String = options[idx]
				if cand == "" or not _used_elsewhere(cand, kind, slot_id, k):
					b.slots[slot_id][k] = cand
					break
		3:
			if row == 0:
				b.garde = "gaucher" if b.garde == "droitier" else "droitier"
			else:
				var keys: Array = cat.styles.keys()
				b.style = keys[(keys.find(b.style) + delta + keys.size()) % keys.size()]
		4:
			var st: Dictionary = cat.physique.stats[row]
			var v: int = b.physique[st.id]
			if delta > 0 and v < cat.physique.max:
				b.physique[st.id] = v + 1
				if Build.physique_cost(b) > cat.physique.budget:
					b.physique[st.id] = v
			elif delta < 0 and v > cat.physique.base:
				b.physique[st.id] = v - 1


func _used_elsewhere(id: String, kind: String, slot_id: String, k: int) -> bool:
	var b = _b()
	for s in cat.slots:
		if s.kind != kind:
			continue
		for j in b.slots[s.id].size():
			if (s.id != slot_id or j != k) and b.slots[s.id][j] == id:
				return true
	return false


# =============================================================================

func _draw() -> void:
	var b = _b()
	Style.menu_background(self, Vector2(1280, 720), Style.P1)
	Style.header(self, "PERSONNALISATION", "Construis ton judoka", Style.P1)
	_draw_build_chip(b)
	_draw_tabs()
	match tab:
		0:
			_draw_profile(b)
		1:
			_draw_look(b)
		2:
			_draw_techniques(b)
		3:
			_draw_style(b)
		4:
			_draw_physique(b)
	if flash > 0:
		var r = Rect2(500, 300, 280, 70)
		Style.panel(self, r, Style.GOOD, Style.INK, 4.0, 8.0)
		Style.text(self, Vector2(r.position.x, r.position.y + 50), "SAUVEGARDÉ", 40, Style.INK, "display", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 1, -1.0)
	var h = [["LB", "RB", "Onglets"], ["X", "Judoka suivant"], ["A", "Valider"], ["B", "Retour"]]
	h.insert(0, ["←→", "Modifier"])
	if kb_open:
		h = [["A", "Taper"], ["B", "Effacer"], ["START", "Valider"]]
	Style.hints(self, h)
	if kb_open:
		_draw_keyboard()


func _draw_build_chip(b: Dictionary) -> void:
	var r = Rect2(850, 28, 400, 60)
	Style.panel(self, r, Style.NIGHT_2, Style.INK, 4.0, 6.0)
	var pal = Art.palette(0, b.get("look", {}))
	draw_circle(Vector2(r.position.x + 44, r.position.y + 30), 21, Style.INK)
	draw_circle(Vector2(r.position.x + 44, r.position.y + 30), 18, pal.accent)
	Style.label(self, Vector2(r.position.x + 32, r.position.y + 38), b.name.substr(0, 1), 22, Style.INK, "black", HORIZONTAL_ALIGNMENT_CENTER, 24)
	Style.text(self, Vector2(r.position.x + 76, r.position.y + 34), b.name, 30, Style.PAPER, "display")
	Style.label(self, Vector2(r.position.x + 78, r.position.y + 52), b.tag.to_upper(), 13, Style.MUTED, "black")
	Style.pad_button(self, Vector2(r.end.x - 34, r.position.y + 30), "X", 13.0)
	Style.label(self, Vector2(r.end.x - 160, r.position.y + 36), "JUDOKA %d/%d" % [bi + 1, builds.size()], 15, Style.MUTED, "black", HORIZONTAL_ALIGNMENT_RIGHT, 100)


func _draw_tabs() -> void:
	var x = 40.0
	Style.pad_button(self, Vector2(x + 14, 168), "LB", 12.0)
	x += 40
	for k in TABS.size():
		var sel = k == tab
		var w = Style.text_width(TABS[k], 24) + 50
		var r = Rect2(x, 150, w, 38)
		Style.panel(self, r, Style.P1 if sel else Style.NIGHT_2, Style.INK, 3.0, 4.0)
		Style.text(self, Vector2(r.position.x, r.position.y + 29), TABS[k], 24, Style.INK if sel else Style.MUTED, "display", HORIZONTAL_ALIGNMENT_CENTER, w, 1 if sel else 3, -1.0 if sel else 0.0)
		x += w + 10
	Style.pad_button(self, Vector2(x + 18, 168), "RB", 12.0)


# --- Onglet 0 : profil -----------------------------------------------------------

func _draw_profile(b: Dictionary) -> void:
	var lk: Dictionary = b.look
	var vals := {
		"NOM": String(b.name), "SURNOM": String(b.get("nick", "")) if String(b.get("nick", "")) != "" else "—",
		"NOUVEAU JUDOKA": "%d / %d" % [builds.size(), MAX_JUDOKAS], "COPIER UNE LÉGENDE": String(Build.legends()[legend_i].name) + " « " + String(Build.legends()[legend_i].nick) + " »",
		"SUPPRIMER": "" if builds.size() > 1 else "(dernier judoka)",
	}
	var y = 210.0
	for k in PROFILE_ROWS.size():
		var key: String = PROFILE_ROWS[k]
		var sel = k == row
		var action_row = key in ["NOUVEAU JUDOKA", "COPIER UNE LÉGENDE", "SUPPRIMER"]
		if key == "NOUVEAU JUDOKA":
			y += 14.0
		var r = Rect2(60 + (12.0 if sel else 0.0), y, 600, 42)
		var fill = Style.NIGHT_3 if sel else Style.NIGHT_2
		if key == "SUPPRIMER" and sel:
			fill = Style.DANGER.darkened(0.35)
		Style.panel(self, r, fill, Style.P1 if sel else Style.INK, 3.0, 4.0)
		Style.label(self, Vector2(r.position.x + 22, r.position.y + 28), key, 14, Style.P1 if sel else Style.MUTED, "black")
		Style.label(self, Vector2(r.position.x + 230, r.position.y + 29), vals[key].to_upper(), 19, Style.PAPER, "black")
		if sel:
			if key in ["NOM", "SURNOM"] or action_row:
				Style.pad_button(self, Vector2(r.end.x - 30, r.position.y + 21), "A", 11.0)
			if key == "COPIER UNE LÉGENDE":
				_arrow(Vector2(r.position.x + 214, r.position.y + 21), -1)
				_arrow(Vector2(r.end.x - 60, r.position.y + 21), 1)
		y += 48.0
	_draw_preview(b)


func _look_names(list_name: String) -> Array:
	match list_name:
		"SKIN_NAMES":
			return Art.SKIN_NAMES
		"HAIR_STYLES":
			return Art.HAIR_STYLES
		"HAIR_COLOR_NAMES":
			return Art.HAIR_COLOR_NAMES
		"BUILD_NAMES":
			return Art.BUILD_NAMES
		"FACE_NAMES":
			return Art.FACE_NAMES
		"BROW_NAMES":
			return Art.BROW_NAMES
		"BEARD_NAMES":
			return Art.BEARD_NAMES
		"EAR_NAMES":
			return Art.EAR_NAMES
		"BELT_NAMES":
			return Art.BELT_NAMES
	return Art.TRIM_NAMES


## Onglet apparence : visage, cheveux, carrure, barbe, ceinture, liseré.
func _draw_look(b: Dictionary) -> void:
	var lk: Dictionary = b.look
	var y = 204.0
	for k in LOOK_ROWS.size():
		var lr: Array = LOOK_ROWS[k]
		var sel = k == row
		var r = Rect2(60 + (12.0 if sel else 0.0), y, 600, 38)
		Style.panel(self, r, Style.NIGHT_3 if sel else Style.NIGHT_2, Style.P1 if sel else Style.INK, 3.0, 4.0)
		Style.label(self, Vector2(r.position.x + 22, r.position.y + 25), lr[1], 14, Style.P1 if sel else Style.MUTED, "black")
		var names: Array = _look_names(lr[2])
		var v = clampi(int(lk.get(lr[0], 0)), 0, names.size() - 1)
		Style.label(self, Vector2(r.position.x + 230, r.position.y + 26), String(names[v]).to_upper(), 18, Style.PAPER, "black", HORIZONTAL_ALIGNMENT_LEFT, 300)
		Style.label(self, Vector2(r.end.x - 70, r.position.y + 25), "%d/%d" % [v + 1, names.size()], 12, Style.MUTED, "black", HORIZONTAL_ALIGNMENT_RIGHT, 50)
		if sel:
			_arrow(Vector2(r.position.x + 214, r.position.y + 19), -1)
			_arrow(Vector2(r.end.x - 86, r.position.y + 19), 1)
		y += 43.0
	_draw_preview(b)


func _draw_preview(b: Dictionary) -> void:
	var lk: Dictionary = b.look
	# aperçu du judoka
	var pr = Rect2(700, 206, 550, 436)
	Style.panel(self, pr, Style.NIGHT_2, Style.INK, 4.0, 10.0, 0.06)
	Style.halftone(self, pr.grow(-10), Color(1, 1, 1, 0.04), 16.0, 4.0, Vector2(0, 1))
	var sc = 3.3
	var feet = Vector2(pr.position.x + 190, pr.end.y - 30)
	var xf = Art.stand_xform(feet, 1, 0.0, sc, 0.15)
	var pal = Art.palette(0, lk)
	Art.shadow(self, feet + Vector2(0, 2), sc, 0.4)
	Art.draw_arm(self, xf * Art.SHOULDER_BACK, xf * Art.REST_HANDS[0], pal, true, sc)
	Art.draw_body(self, xf, pal, 0.3)
	Art.draw_arm(self, xf * Art.SHOULDER_FRONT, xf * Art.REST_HANDS[1], pal, false, sc)
	var tx = pr.position.x + 330
	Style.text(self, Vector2(tx, pr.position.y + 60), String(b.name), 34, Style.P1, "display")
	if String(b.get("nick", "")) != "":
		Style.label(self, Vector2(tx + 2, pr.position.y + 98), "« %s »" % String(b.nick).to_upper(), 16, Style.PAPER, "black")
	var info = [["TOKUI", Build.entry("technique", b.slots.tokui[0]).get("name", "—")], ["GARDE", String(b.garde).capitalize()],
		["STYLE", cat.styles[b.style].name], ["SET", "%d / %d pts" % [Build.set_cost(b), cat.budget]], ["PHYSIQUE", "%d / %d pts" % [Build.physique_cost(b), cat.physique.budget]]]
	var iy = pr.position.y + 124
	for it in info:
		Style.label(self, Vector2(tx, iy), it[0], 12, Style.MUTED, "black")
		Style.label(self, Vector2(tx, iy + 19), String(it[1]).to_upper(), 17, Style.PAPER, "black", HORIZONTAL_ALIGNMENT_LEFT, 205)
		iy += 36
	for st in cat.physique.stats:
		var v: int = b.physique[st.id]
		Style.label(self, Vector2(tx, iy + 2), String(st.name).substr(0, 4).to_upper(), 11, Style.MUTED, "black")
		for s2 in 10:
			draw_rect(Rect2(tx + 44 + s2 * 15, iy - 8, 12, 10), Style.P2 if s2 < v else Style.NIGHT)
		iy += 16
	# palmarès
	var rec: Dictionary = Records.of(String(b.get("id", "")))
	var py = iy + 8
	Style.label(self, Vector2(tx, py), "PALMARÈS", 12, Style.MUTED, "black")
	if int(rec.m) == 0:
		Style.label(self, Vector2(tx, py + 22), "AUCUN COMBAT", 15, Style.MUTED, "black")
	else:
		Style.label(self, Vector2(tx, py + 22), "%d V · %d D · %d %%" % [rec.w, rec.l, Records.win_rate(rec)], 17, Style.GOLD, "black", HORIZONTAL_ALIGNMENT_LEFT, 200)
		var fav = Records.favorite(rec)
		var fav_txt = "%d IPPON · SÉRIE %d" % [rec.ippon, rec.best]
		if fav != "":
			fav_txt += " · " + String(Build.entry("technique", fav).get("name", fav)).to_upper()
		Style.label(self, Vector2(tx, py + 42), fav_txt, 12, Style.PAPER, "black", HORIZONTAL_ALIGNMENT_LEFT, 205)


func _draw_keyboard() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Color(0.04, 0.03, 0.1, 0.75))
	var r = Rect2(240, 150, 800, 420)
	Style.panel(self, r, Style.NIGHT_2, Style.P1, 4.0, 10.0)
	Style.label(self, r.position + Vector2(40, 40), "NOM" if kb_field == "name" else "SURNOM", 15, Style.MUTED, "black")
	var fr = Rect2(r.position.x + 36, r.position.y + 56, r.size.x - 72, 64)
	Style.panel(self, fr, Style.INK, Style.P1, 3.0, 4.0, 0.08)
	var caret = "_" if (frame / 20) % 2 == 0 else " "
	Style.text(self, Vector2(fr.position.x + 24, fr.position.y + 48), kb_text + caret, 40, Style.PAPER, "display")
	for rr in KB_ROWS.size():
		var keys: Array = KB_ROWS[rr]
		var kw = 62.0 if keys.size() > 3 else 220.0
		var x = r.position.x + 40 + (0.0 if keys.size() > 3 else 0.0)
		for cc in keys.size():
			var sel = rr == kb_r and cc == clampi(kb_c, 0, keys.size() - 1)
			var kr = Rect2(x, r.position.y + 146 + rr * 64, kw, 54)
			Style.panel(self, kr, Style.P1 if sel else Style.NIGHT_3, Style.INK, 3.0, 4.0, 0.1)
			Style.label(self, Vector2(kr.position.x, kr.position.y + 36), keys[cc], 22 if keys.size() > 3 else 18,
				Style.INK if sel else Style.PAPER, "black", HORIZONTAL_ALIGNMENT_CENTER, kr.size.x)
			x += kw + 10


# --- Onglet 1 : techniques ------------------------------------------------------

func _draw_techniques(b: Dictionary) -> void:
	var cost = Build.set_cost(b)
	var budget: int = cat.budget
	# jauge de budget
	var gr = Rect2(856, 100, 394, 32)
	var over = cost > budget
	Style.gauge(self, gr, float(cost) / float(budget), Style.DANGER if over else Style.P1)
	Style.text(self, Vector2(gr.position.x, gr.position.y + 25), "BUDGET %d / %d PTS" % [cost, budget], 22, Style.PAPER, "display", HORIZONTAL_ALIGNMENT_CENTER, gr.size.x, 3, 0.0)
	# liste des slots
	var y = 204.0
	var last_slot = ""
	var labels = {}
	for s in cat.slots:
		labels[s.id] = s
	for k in rows.size():
		var slot_id: String = rows[k][0]
		var j: int = rows[k][1]
		var s: Dictionary = labels[slot_id]
		var sel = k == row
		var id: String = b.slots[slot_id][j]
		var e = Build.entry(s.kind, id)
		var r = Rect2(60 - k * 2.0 + (12.0 if sel else 0.0), y, 520, 36)
		var fill = Style.NIGHT_3 if sel else Style.NIGHT_2
		if slot_id == "tokui":
			fill = Style.P1 if sel else Style.P1.darkened(0.55)
		Style.panel(self, r, fill, Style.P1 if sel else Style.INK, 3.0, 4.0 if sel else 3.0)
		var lab: String = s.label + ("" if s.count == 1 else " %d" % (j + 1))
		var tcol = Style.INK if slot_id == "tokui" and sel else Style.MUTED
		Style.label(self, Vector2(r.position.x + 22, r.position.y + 24), lab, 13, tcol, "black")
		var name: String = e.get("name", "— vide —")
		var ncol = Style.PAPER if not e.is_empty() else Style.MUTED
		if slot_id == "tokui" and sel:
			ncol = Style.INK
		Style.label(self, Vector2(r.position.x + 176, r.position.y + 26), name.to_upper(), 19, ncol, "black")
		if not e.is_empty():
			var cr = Rect2(r.end.x - 64, r.position.y + 6, 46, 24)
			Style.chip(self, cr, Style.INK, Style.P1)
			Style.label(self, Vector2(cr.position.x, cr.position.y + 18), "%d" % e.cost, 16, Style.P1, "black", HORIZONTAL_ALIGNMENT_CENTER, cr.size.x)
		if sel:
			_arrow(Vector2(r.position.x - 12, r.position.y + 18), -1)
			_arrow(Vector2(r.end.x + 12, r.position.y + 18), 1)
		y += 40.0
	# carte de détail
	var cur_slot: String = rows[row][0]
	var cur_id: String = b.slots[cur_slot][rows[row][1]]
	_draw_card(Build.entry(Build.kind_of(cur_slot), cur_id), cur_slot == "tokui")


func _arrow(c: Vector2, dir: int) -> void:
	var pts = PackedVector2Array([c + Vector2(dir * 10, 0), c + Vector2(-dir * 6, -10), c + Vector2(-dir * 6, 10)])
	var sh = PackedVector2Array()
	for p in pts:
		sh.append(p + Vector2(2, 2))
	draw_colored_polygon(sh, Style.INK)
	draw_colored_polygon(pts, Style.P1)


func _draw_card(e: Dictionary, tokui: bool) -> void:
	var r = Rect2(650, 204, 590, 436)
	Style.panel(self, r, Style.NIGHT_2, Style.INK, 4.0, 10.0, 0.06)
	if e.is_empty():
		Style.text(self, Vector2(r.position.x, r.position.y + 210), "SLOT LIBRE", 44, Style.MUTED, "display", HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		Style.label(self, Vector2(r.position.x, r.position.y + 250), "← → pour choisir une technique", 18, Style.MUTED, "bold", HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		return
	var x0 = r.position.x + 36
	Style.text(self, Vector2(x0, r.position.y + 66), e.name.to_upper(), 46, Style.P1, "display", HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 72)
	# puces : famille, jouable, tokui
	var cx = x0
	var chips = [[e.family.to_upper(), Style.PAPER]]
	chips.append(["JOUABLE" if e.jouable else "BIENTÔT", Style.GOOD if e.jouable else Style.MUTED])
	if tokui:
		chips.append(["TOKUI : BONUS DE RÉUSSITE", Style.P1])
	for c in chips:
		var w = Style.text_width(c[0], 14, "black") + 30
		var cr = Rect2(cx, r.position.y + 86, w, 28)
		Style.chip(self, cr, Style.INK, c[1])
		Style.label(self, Vector2(cr.position.x, cr.position.y + 20), c[0], 14, c[1], "black", HORIZONTAL_ALIGNMENT_CENTER, w)
		cx += w + 10
	# stats
	var stats = [["VITESSE", e.speed, Style.P2], ["RISQUE", e.risk, Style.DANGER], ["ENDURANCE", e.stamina, Style.P1], ["PUISSANCE", e.power, Style.HOT]]
	var sy = r.position.y + 150
	for st in stats:
		Style.label(self, Vector2(x0, sy + 20), st[0], 16, Style.MUTED, "black")
		for k in 5:
			var br = Rect2(x0 + 130 + k * 46, sy + 2, 40, 22)
			Style.panel(self, br, st[2] if k < st[1] else Style.NIGHT, Style.INK, 2.5, 0.0)
		sy += 38
	# direction de kuzushi
	var dc = Vector2(r.end.x - 110, r.position.y + 206)
	_draw_dir(dc, e.dir)
	Style.label(self, Vector2(dc.x - 90, dc.y + 78), "KUZUSHI", 13, Style.MUTED, "black", HORIZONTAL_ALIGNMENT_CENTER, 180)
	Style.label(self, Vector2(dc.x - 90, dc.y + 96), DIR_LABELS.get(e.dir, e.dir), 16, Style.P1, "black", HORIZONTAL_ALIGNMENT_CENTER, 180)
	# garde favorable
	var gy = r.position.y + 330
	draw_line(Vector2(x0, gy), Vector2(r.end.x - 40, gy), Style.NIGHT_3, 2.0)
	Style.label(self, Vector2(x0, gy + 32), "GARDE FAVORABLE", 13, Style.MUTED, "black")
	Rich.draw(self, Vector2(x0, gy + 56), String(e.garde), r.size.x - 240, 18, Style.PAPER)
	# coût
	var cr2 = Rect2(r.end.x - 170, r.end.y - 76, 130, 52)
	Style.panel(self, cr2, Style.P1, Style.INK, 4.0, 6.0)
	Style.text(self, Vector2(cr2.position.x, cr2.position.y + 40), "%d PTS" % e.cost, 34, Style.INK, "display", HORIZONTAL_ALIGNMENT_CENTER, cr2.size.x, 1, -1.0)


func _draw_dir(c: Vector2, dir: String) -> void:
	var r = 58.0
	draw_circle(c + Vector2(4, 4), r + 4, Style.INK)
	draw_circle(c, r + 4, Style.INK)
	draw_circle(c, r, Style.NIGHT)
	draw_arc(c, r * 0.5, 0, TAU, 32, Style.NIGHT_3, 2.0, true)
	draw_line(c - Vector2(r, 0), c + Vector2(r, 0), Style.NIGHT_3, 2.0)
	draw_line(c - Vector2(0, r), c + Vector2(0, r), Style.NIGHT_3, 2.0)
	Style.label(self, c + Vector2(r - 26, -6), "AV", 12, Style.MUTED, "black")
	Style.label(self, c + Vector2(-r + 6, -6), "AR", 12, Style.MUTED, "black")
	var vecs = []
	match dir:
		"avant":
			vecs = [Vector2(1, 0)]
		"arriere":
			vecs = [Vector2(-1, 0)]
		"cote":
			vecs = [Vector2(0, 1)]
		"arriere_cote":
			vecs = [Vector2(-0.7, 0.7)]
		"avant_cote":
			vecs = [Vector2(0.7, 0.7)]
		"arriere_avant":
			vecs = [Vector2(-1, 0), Vector2(1, 0)]
		"cote_avant":
			vecs = [Vector2(0, 1), Vector2(1, 0)]
	for k in vecs.size():
		var v: Vector2 = vecs[k]
		var tip: Vector2 = c + v * (r - 8)
		var col = Style.P1 if k == vecs.size() - 1 else Style.MUTED
		draw_line(c, tip, Style.INK, 9.0, true)
		draw_line(c, tip, col, 5.0, true)
		var n = Vector2(-v.y, v.x)
		draw_colored_polygon(PackedVector2Array([tip + v * 10, tip + n * 9, tip - n * 9]), col)
	if dir == "sol":
		Style.text(self, Vector2(c.x - r, c.y + 12), "SOL", 34, Style.P1, "display", HORIZONTAL_ALIGNMENT_CENTER, r * 2)


# --- Onglet 2 : garde et style --------------------------------------------------

func _draw_style(b: Dictionary) -> void:
	# garde
	var y = 210.0
	Style.label(self, Vector2(60, y), "GARDE", 18, Style.P1 if row == 0 else Style.MUTED, "black")
	var gx = 60.0
	for g in ["droitier", "gaucher"]:
		var on: bool = b.garde == g
		var r = Rect2(gx, y + 14, 250, 64)
		Style.panel(self, r, Style.P1 if on else Style.NIGHT_2, Style.P1 if (row == 0 and on) else Style.INK, 4.0, 6.0)
		Style.text(self, Vector2(r.position.x, r.position.y + 46), cat.gardes[g].to_upper(), 34, Style.INK if on else Style.PAPER, "display", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 1 if on else 3, -1.0 if on else 0.0)
		gx += 270
	Style.label(self, Vector2(620, y + 40), "Aucun bonus de stats : le gaucher surprend les droitiers,", 17, Style.PAPER, "bold")
	Style.label(self, Vector2(620, y + 64), "le kenka-yotsu change la bataille de mains.", 17, Style.PAPER, "bold")
	# style
	y = 330.0
	Style.label(self, Vector2(60, y), "STYLE DE KUMIKATA", 18, Style.P1 if row == 1 else Style.MUTED, "black")
	var sx = 60.0
	for key in cat.styles:
		var st: Dictionary = cat.styles[key]
		var on: bool = b.style == key
		var r = Rect2(sx, y + 16, 300, 270)
		Style.panel(self, r, Style.NIGHT_3 if on else Style.NIGHT_2, Style.P1 if on else Style.INK, 4.0 if not on else 5.0, 8.0, 0.08)
		if on:
			draw_colored_polygon(Style.slant_points(Rect2(r.position + Vector2(6, 6), Vector2(r.size.x - 12, 50)), 0.08), Style.P1)
		Style.text(self, Vector2(r.position.x + 22, r.position.y + 44), st.name.to_upper(), 30, Style.INK if on else Style.PAPER, "display", HORIZONTAL_ALIGNMENT_LEFT, -1, 1 if on else 3, -1.0 if on else 0.0)
		Style.label(self, Vector2(r.position.x + 24, r.position.y + 82), st.detail.to_upper(), 14, Style.MUTED, "black")
		Style.label(self, Vector2(r.position.x + 24, r.position.y + 116), "+ FORCE", 14, Style.GOOD, "black")
		_wrap(st.force, Vector2(r.position.x + 24, r.position.y + 122), r.size.x - 50, 16, Style.PAPER)
		Style.label(self, Vector2(r.position.x + 24, r.position.y + 190), "− FAIBLESSE", 14, Style.DANGER, "black")
		_wrap(st.faiblesse, Vector2(r.position.x + 24, r.position.y + 196), r.size.x - 50, 16, Style.PAPER)
		sx += 318
	# triangle pierre-feuille-ciseaux
	var c = Vector2(1130, 470)
	var pts = {"haute": c + Vector2(0, -92), "classique": c + Vector2(-80, 46), "courte": c + Vector2(80, 46)}
	for k in STYLE_BEATS:
		var a: Vector2 = pts[k]
		var bb: Vector2 = pts[STYLE_BEATS[k]]
		var d = (bb - a).normalized()
		var p0 = a + d * 30
		var p1 = bb - d * 30
		draw_line(p0, p1, Style.INK, 7.0, true)
		draw_line(p0, p1, Style.HOT, 3.5, true)
		var n = Vector2(-d.y, d.x)
		draw_colored_polygon(PackedVector2Array([p1 + d * 4, p1 - d * 10 + n * 7, p1 - d * 10 - n * 7]), Style.HOT)
	for k in pts:
		var on: bool = b.style == k
		draw_circle(pts[k], 27, Style.INK)
		draw_circle(pts[k], 24, Style.P1 if on else Style.NIGHT_3)
		var short = {"haute": "HAUTE", "classique": "CLASS.", "courte": "COURTE"}
		Style.label(self, pts[k] + Vector2(-30, 5), short[k], 12, Style.INK if on else Style.PAPER, "black", HORIZONTAL_ALIGNMENT_CENTER, 60)
	Style.label(self, Vector2(1040, 600), "LA FLÈCHE = « BAT »", 13, Style.MUTED, "black", HORIZONTAL_ALIGNMENT_CENTER, 180)


# --- Onglet 3 : profil physique ------------------------------------------------

func _draw_physique(b: Dictionary) -> void:
	var phys: Dictionary = cat.physique
	var cost = Build.physique_cost(b)
	var gr = Rect2(856, 100, 394, 32)
	Style.gauge(self, gr, float(cost) / float(phys.budget), Style.P2)
	Style.text(self, Vector2(gr.position.x, gr.position.y + 25), "PROFIL %d / %d PTS" % [cost, phys.budget], 22, Style.PAPER, "display", HORIZONTAL_ALIGNMENT_CENTER, gr.size.x, 3, 0.0)
	var y = 214.0
	for k in phys.stats.size():
		var st: Dictionary = phys.stats[k]
		var sel = k == row
		var v: int = b.physique[st.id]
		var r = Rect2(60 + (12.0 if sel else 0.0), y, 840, 92)
		Style.panel(self, r, Style.NIGHT_3 if sel else Style.NIGHT_2, Style.P2 if sel else Style.INK, 4.0, 6.0, 0.1)
		Style.text(self, Vector2(r.position.x + 30, r.position.y + 42), st.name.to_upper(), 30, Style.P2 if sel else Style.PAPER, "display")
		Style.label(self, Vector2(r.position.x + 32, r.position.y + 72), st.detail, 14, Style.MUTED, "bold")
		for s in phys.max:
			var seg = Rect2(r.position.x + 420 + s * 33, r.position.y + 24, 28, 40)
			var on = s < v
			var col = Style.P2 if on else Style.NIGHT
			if on and s >= phys.base:
				col = Style.P2
			elif on:
				col = Style.P2.darkened(0.35)
			Style.panel(self, seg, col, Style.INK, 2.5, 0.0, 0.25)
		var nxt = "MAX" if v >= phys.max else "+1 : %d PT%s" % [Build.step_cost(v), "S" if Build.step_cost(v) > 1 else ""]
		Style.label(self, Vector2(r.position.x + 756, r.position.y + 52), nxt, 13, Style.P2 if sel else Style.MUTED, "black")
		y += 104
	# encart règle
	var info = Rect2(940, 214, 300, 400)
	Style.panel(self, info, Style.INK, Style.P2, 3.0, 6.0, 0.06)
	Style.text(self, Vector2(info.position.x + 26, info.position.y + 48), "RENDEMENTS", 30, Style.P2, "display")
	Style.text(self, Vector2(info.position.x + 26, info.position.y + 82), "DÉCROISSANTS", 30, Style.P2, "display")
	var lines = [["NIVEAUX 3 → 5", "1 pt"], ["NIVEAUX 5 → 7", "2 pts"], ["NIVEAUX 7 → 10", "3 pts"]]
	var ly = info.position.y + 130
	for l in lines:
		Style.label(self, Vector2(info.position.x + 28, ly), l[0], 16, Style.PAPER, "black")
		Style.label(self, Vector2(info.position.x + 28, ly), l[1], 16, Style.P2, "black", HORIZONTAL_ALIGNMENT_RIGHT, info.size.x - 70)
		ly += 34
	_wrap("Tout mettre dans une stat coûte cher : un profil équilibré est souvent plus solide.", Vector2(info.position.x + 28, ly + 6), info.size.x - 60, 16, Style.MUTED)


func _wrap(s: String, pos: Vector2, width: float, size: int, col: Color) -> float:
	var words = s.split(" ")
	var line = ""
	var y = pos.y
	var f = Style.font("bold")
	for w in words:
		var test = (line + " " + w).strip_edges()
		if f.get_string_size(test, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width:
			draw_string(f, Vector2(pos.x, y + size), line, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
			y += size * 1.35
			line = w
		else:
			line = test
	if line != "":
		draw_string(f, Vector2(pos.x, y + size), line, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
	return y + size * 1.35
