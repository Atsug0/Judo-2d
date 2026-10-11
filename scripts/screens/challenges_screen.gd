extends Node2D
## Défis : liste des objectifs, légende à affronter, judoka utilisé (X pour changer).

const Style := preload("res://scripts/ui/style.gd")
const Rich := preload("res://scripts/ui/rich.gd")
const Art := preload("res://scripts/view/fighter_art.gd")
const Build := preload("res://scripts/build.gd")
const Challenges := preload("res://scripts/challenges.gd")

var app
var frame = 0
var index = 0
var bi = 0
var builds: Array = []


func on_enter(p: Dictionary) -> void:
	builds = Build.load_all()
	if p.has("index"):
		index = int(p.index)
	bi = clampi(int(p.get("bi", 0)), 0, builds.size() - 1)


func tick() -> void:
	frame += 1
	queue_redraw()


func nav(action: String, _player: int = 0) -> void:
	var n: int = Challenges.all().size()
	match action:
		"up":
			index = (index + n - 1) % n
		"down":
			index = (index + 1) % n
		"x":
			bi = (bi + 1) % builds.size()
		"back":
			app.goto("menu", {})
		"accept":
			var ch: Dictionary = Challenges.all()[index]
			var me: Dictionary = builds[bi]
			var opp: Dictionary = Build.find(String(ch.opp))
			app.goto("vs", {"controllers": [app.human_controller(), "ai"], "names": [me.name, opp.name],
				"tokui": [me.slots.tokui[0], opp.slots.tokui[0]], "builds": [me, opp],
				"seed": int(app.args.get("seed", str(frame))), "level": int(ch.level), "mode": "challenge",
				"challenge": ch.id, "challenge_index": index, "bi": bi})
	queue_redraw()


func _draw() -> void:
	var size = Vector2(1280, 720)
	Style.menu_background(self, size, Style.GOLD, frame * 0.01)
	Style.header(self, "DÉFIS", "%d / %d réussis" % [Challenges.count_done(), Challenges.all().size()], Style.GOLD)
	var list: Array = Challenges.all()
	var first = clampi(index - 5, 0, maxi(0, list.size() - 9))
	for k in range(first, mini(list.size(), first + 9)):
		var ch: Dictionary = list[k]
		var sel = k == index
		var y = 164 + (k - first) * 50
		var r = Rect2(40 + (12 if sel else 0), y, 420, 42)
		Style.panel(self, r, Style.GOLD if sel else Style.NIGHT_2, Style.INK, 3.0, 4.0)
		Style.label(self, Vector2(r.position.x + 22, r.position.y + 28), "%02d" % (k + 1), 15, Style.INK if sel else Style.MUTED, "black")
		Style.label(self, Vector2(r.position.x + 60, r.position.y + 28), String(ch.title).to_upper(), 18, Style.INK if sel else Style.PAPER, "black", HORIZONTAL_ALIGNMENT_LEFT, 270)
		Style.label(self, Vector2(r.position.x, r.position.y + 28), "IA %d" % int(ch.level), 13, Style.INK if sel else Style.MUTED, "black", HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 64)
		if Challenges.is_done(ch.id):
			var c = Vector2(r.end.x - 30, r.position.y + 21)
			draw_circle(c, 11.0, Style.INK)
			draw_circle(c, 9.0, Style.GOOD)
			draw_polyline(PackedVector2Array([c + Vector2(-5, 0), c + Vector2(-1, 4), c + Vector2(5, -4)]), Style.INK, 3.0)
	# détail du défi
	var ch2: Dictionary = list[index]
	var opp: Dictionary = Build.find(String(ch2.opp))
	var dr = Rect2(500, 164, 740, 446)
	Style.panel(self, dr, Style.NIGHT_2, Style.GOLD, 4.0, 8.0, 0.04)
	Style.label(self, dr.position + Vector2(34, 38), "DÉFI %02d" % (index + 1), 14, Style.GOLD, "black")
	Style.text(self, dr.position + Vector2(30, 86), String(ch2.title).to_upper(), 42, Style.PAPER, "display", HORIZONTAL_ALIGNMENT_LEFT, 440)
	var hh = Rich.draw(self, dr.position + Vector2(34, 126), String(ch2.desc), 420, 18, Style.PAPER)
	var y2 = dr.position.y + 150 + hh
	Style.label(self, Vector2(dr.position.x + 34, y2), "ADVERSAIRE", 13, Style.MUTED, "black")
	Style.text(self, Vector2(dr.position.x + 34, y2 + 38), "%s · IA %d" % [String(opp.get("name", "?")), int(ch2.level)], 28, Style.P2, "display", HORIZONTAL_ALIGNMENT_LEFT, 420)
	Style.label(self, Vector2(dr.position.x + 34, y2 + 60), String(opp.get("tag", "")).to_upper(), 12, Style.MUTED, "black", HORIZONTAL_ALIGNMENT_LEFT, 420)
	var me: Dictionary = builds[bi]
	Style.label(self, Vector2(dr.position.x + 34, y2 + 100), "TON JUDOKA", 13, Style.MUTED, "black")
	Style.text(self, Vector2(dr.position.x + 34, y2 + 138), String(me.name), 28, Style.P1, "display", HORIZONTAL_ALIGNMENT_LEFT, 300)
	Style.pad_button(self, Vector2(dr.position.x + 360, y2 + 128), "X", 12.0)
	Style.label(self, Vector2(dr.position.x + 380, y2 + 134), "CHANGER", 13, Style.PAPER, "black")
	if Challenges.is_done(ch2.id):
		var br = Rect2(dr.end.x - 230, dr.position.y + 24, 190, 44)
		Style.panel(self, br, Style.GOOD, Style.INK, 3.0, 4.0)
		Style.text(self, Vector2(br.position.x, br.position.y + 33), "RÉUSSI", 26, Style.INK, "display", HORIZONTAL_ALIGNMENT_CENTER, br.size.x, 1, -1.0)
	# les deux judokas face à face
	var sc = 2.6
	for pair in [[me, 0, Vector2(dr.end.x - 230, dr.end.y - 24)], [opp, 1, Vector2(dr.end.x - 110, dr.end.y - 24)]]:
		var b: Dictionary = pair[0]
		if b.is_empty():
			continue
		var xf = Art.stand_xform(pair[2], 1 if pair[1] == 0 else -1, 0.0, sc, 0.25)
		var pal = Art.palette(pair[1], b.get("look", {}))
		Art.shadow(self, pair[2] + Vector2(0, 2), sc, 0.35)
		Art.draw_arm(self, xf * Art.SHOULDER_BACK, xf * Art.REST_HANDS[0], pal, true, sc)
		Art.draw_body(self, xf, pal, 0.3)
		Art.draw_arm(self, xf * Art.SHOULDER_FRONT, xf * Art.REST_HANDS[1], pal, false, sc)
	Style.hints(self, [["A", "Relever le défi"], ["X", "Judoka"], ["B", "Retour"]])
