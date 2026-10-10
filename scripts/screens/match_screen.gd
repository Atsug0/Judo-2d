extends Node2D
## Écran de combat : fait tourner la simulation et dessine l'arène, les judokas et le HUD.

const Style := preload("res://scripts/ui/style.gd")
const Art := preload("res://scripts/view/fighter_art.gd")
const GameData := preload("res://scripts/game_data.gd")
const Sim := preload("res://scripts/sim/match_sim.gd")
const Ai := preload("res://scripts/sim/ai_controller.gd")
const Pad := preload("res://scripts/pad_reader.gd")
const Settings := preload("res://scripts/settings.gd")
const SpriteLib := preload("res://scripts/view/sprite_library.gd")

const W := 1280.0
const H := 720.0
const FEET_Y := 604.0
const K := 2.2  # échelle des personnages
const MAT_BACK := 556.0
const MAT_FRONT := 652.0
const GRIP_LABELS := ["MANCHE", "REVERS", "COL HAUT", "CEINTURE"]

var app  # main.gd
var cfg: Dictionary
var techs: Dictionary
var sim
var controllers = ["ai", "ai"]  # "pad0", "pad1" ou "ai"
var ais = [null, null]
var names = ["J1", "J2"]
var feed: Array = []        # [{text, color, t}]
var popups: Array = []      # [{text, who, color, t}]
var shake = 0.0
var paused = false
var pause_index = 0
var end_timer = 0
var capture_flag = false   # demande de capture (mode capture d'écran)
var attack_flag = false    # une attaque est à mi-entrée
var frame = 0
var params: Dictionary = {}
var stats = []  # statistiques par joueur pour l'écran de résultats
var libs = [null, null]  # sprites par joueur (null = dessin placeholder)
const PAUSE_ITEMS := ["REPRENDRE", "RECOMMENCER", "PERSONNALISATION", "MENU PRINCIPAL"]


func on_enter(p: Dictionary) -> void:
	params = p
	stats = [_new_stats(), _new_stats()]
	cfg = GameData.load_json("res://data/config.json")
	techs = GameData.load_json("res://data/techniques.json")
	controllers = p.get("controllers", ["ai", "ai"])
	names = p.get("names", ["HUGO", "KENJI"])
	var tokui: Array = p.get("tokui", ["seoi_nage", "o_soto_gari"])
	var seed_value: int = p.get("seed", 1)
	var level: int = p.get("level", 2)
	sim = Sim.new(cfg, techs, names, p.get("builds", tokui))
	# Sprites : "placeholder" (images cuites) ou un identifiant de personnage par joueur.
	var sprite_set: String = p.get("sprites", "")
	if sprite_set != "":
		for i in 2:
			var cid := sprite_set
			if sprite_set == "placeholder":
				cid = "placeholder_blanc" if i == 0 else "placeholder_bleu"
			libs[i] = SpriteLib.load_character(cid)
	for i in 2:
		if controllers[i] == "ai":
			ais[i] = Ai.new(i, seed_value + i * 7, level)


func tick() -> void:
	frame += 1
	if paused:
		return
	var inputs = []
	for i in 2:
		match controllers[i]:
			"pad0":
				inputs.append(Pad.read(0))
			"pad1":
				inputs.append(Pad.read(1))
			_:
				inputs.append(ais[i].think(sim))
	sim.step(inputs)
	_consume_events()
	for p in popups:
		p.t += 1
	popups = popups.filter(func(p): return p.t < 70)
	for e in feed:
		e.t += 1
	shake = maxf(0.0, shake - 0.6)
	if sim.state.phase == "ended":
		end_timer += 1
		if end_timer == 200 and app != null and not app.capture_mode:
			app.goto("results", {"state": sim.get_state(), "names": names, "stats": stats, "match_params": params})
	queue_redraw()


func nav(action: String, _player: int = 0) -> void:
	if action == "start":
		paused = not paused
		pause_index = 0
	elif paused:
		match action:
			"up":
				pause_index = (pause_index + PAUSE_ITEMS.size() - 1) % PAUSE_ITEMS.size()
			"down":
				pause_index = (pause_index + 1) % PAUSE_ITEMS.size()
			"back":
				paused = false
			"accept":
				match pause_index:
					0:
						paused = false
					1:
						app.goto("match", app.last_match_params)
					2:
						app.goto("customize", {})
					3:
						app.goto("menu", {})
	queue_redraw()


func _new_stats() -> Dictionary:
	return {"attacks": 0, "throws": 0, "counters": 0, "breaks": 0, "feints": 0, "exposed": 0,
		"blocks": 0, "shidos": 0, "kuzushi_max": 0, "method": ""}


func _consume_events() -> void:
	capture_flag = false
	for i in 2:
		var o: Dictionary = sim.state.fighters[1 - i]
		var mag := maxi(absi(o.bal_x), absi(o.bal_y))
		stats[i].kuzushi_max = maxi(stats[i].kuzushi_max, mag)
	for e in sim.events:
		var who: int = e.get("who", -1)
		if who >= 0:
			var st: Dictionary = stats[who]
			match e.type:
				"attack":
					st.attacks += 1
				"throw":
					st.throws += 1
					st.method = sim.tech_name(e.tech)
				"counter":
					st.counters += 1
				"break":
					st.breaks += 1
				"feint":
					st.feints += 1
				"exposed":
					st.exposed += 1
				"block":
					st.blocks += 1
				"shido":
					st.shidos += 1
		var nm: String = names[who] if who >= 0 else ""
		var col: Color = Style.P1 if who == 0 else Style.P2
		match e.type:
			"attack":
				_feed("%s attaque : %s" % [nm, sim.tech_name(e.tech)], col)
			"throw":
				var res = "IPPON" if e.result == "ippon" else "WAZA-ARI"
				_feed("%s : %s → %s" % [nm, sim.tech_name(e.tech), res], Style.GOLD)
			"counter":
				_feed("%s contre : %s !" % [nm, sim.tech_name(e.tech)], Style.HOT)
				_popup("CONTRE !", who, Style.HOT)
			"exposed":
				_popup("EXPOSÉ", who, Style.DANGER)
			"stuffed":
				_popup("STOPPÉ", who, Style.MUTED)
			"block":
				_popup("BLOQUE", who, Style.PAPER)
			"break":
				_popup("CASSE LA GARDE", who, Style.GOOD)
			"feint":
				_popup("FEINTE", who, Style.MUTED)
			"shido":
				_feed("Shido %s : %s" % [nm, e.reason], Style.P1)
				capture_flag = true
			"golden":
				_feed("Golden score !", Style.GOLD)
			"combo_open":
				_popup("ENCHAÎNE !", who, Style.GOLD)
			"newaza":
				_feed("%s passe au sol" % nm, col)
			"osaekomi":
				_feed("%s : osaekomi (%s)" % [nm, sim.tech_name(e.tech)], Style.GOLD)
				capture_flag = true
			"toketa":
				_popup("TOKETA", who, Style.PAPER)
			"escape":
				_popup("SORTIE !", who, Style.GOOD)
			"sub_start":
				_feed("%s tente %s" % [nm, sim.tech_name(e.tech)], Style.HOT)
				capture_flag = true
			"sub_escape":
				_popup("RÉSISTE !", who, Style.GOOD)
			"submission":
				_feed("%s : %s, maitta !" % [nm, sim.tech_name(e.tech)], Style.GOLD)
			"end":
				_feed("Victoire de %s — %s" % [nm, e.reason], Style.GOLD)
	attack_flag = false
	for f in sim.state.fighters:
		if not f.attack.is_empty() and f.attack.t == 9:
			attack_flag = true
	var th: Dictionary = sim.state.throw
	if sim.state.phase == "throw" and th.t == cfg.throw_ticks - 4:
		shake = 9.0 if th.result == "ippon" else 6.0
		for i in 2:
			if controllers[i].begins_with("pad"):
				Settings.rumble(int(controllers[i].substr(3)), 1.0 if th.result == "ippon" else 0.7, 0.35)
	if sim.state.phase == "throw" and th.t == cfg.throw_ticks / 2:
		capture_flag = true
	if sim.state.phase in ["score", "ended"] and sim.state.phase_t == 14:
		capture_flag = true
	if sim.state.phase == "newaza" and sim.state.newaza.t in [90, 400]:
		capture_flag = true


func _feed(text: String, color: Color) -> void:
	feed.append({"text": text, "color": color, "t": 0})
	if feed.size() > 4:
		feed.pop_front()


func _popup(text: String, who: int, color: Color) -> void:
	popups.append({"text": text, "who": who, "color": color, "t": 0})


# =============================================================================
# Dessin
# =============================================================================

func _draw() -> void:
	if sim == null:
		return
	var off = Vector2.ZERO
	if shake > 0.0:
		off = Vector2(sin(frame * 1.7) * shake, cos(frame * 2.3) * shake * 0.6)
	draw_set_transform(off)
	_draw_arena()
	_draw_mat()
	_draw_fighters()
	draw_set_transform(Vector2.ZERO)
	_draw_hud()
	_draw_popups()
	_draw_announce()
	if Settings.value("feed"):
		_draw_feed()
	if Settings.value("hints"):
		_draw_hints()
	if paused:
		_draw_pause()


func wx(x_cpx: int) -> float:
	return float(x_cpx) / 50.0


func _persp(x: float, y: float) -> float:
	return 640.0 + (x - 640.0) * (1.0 + (y - FEET_Y) * 0.0013)


func _draw_arena() -> void:
	# ciel de salle : bandes de dégradé
	var top = Color("0f0b24")
	var bottom = Color("2a1f5e")
	var steps = 24
	for k in steps:
		var y0 = MAT_BACK * k / steps
		draw_rect(Rect2(0, y0, W, MAT_BACK / steps + 1), top.lerp(bottom, float(k) / steps))
	# projecteurs
	for sx in [260.0, 640.0, 1020.0]:
		var pts = PackedVector2Array([Vector2(sx - 18, 0), Vector2(sx + 18, 0), Vector2(sx + 210, MAT_BACK), Vector2(sx - 210, MAT_BACK)])
		draw_colored_polygon(pts, Color(1, 1, 1, 0.035))
	# tribunes : rangées de silhouettes
	var s = 12345
	for row in 5:
		var y = 330.0 + row * 34.0
		var col = Color("1a1440").lerp(Color("2e2465"), row / 5.0)
		var x = -10.0 + (row % 2) * 14.0
		while x < W + 20:
			s = (s * 1103515245 + 12345) & 0x7fffffff
			var hy = y + float(s % 9)
			draw_circle(Vector2(x, hy), 10.0, col)
			draw_rect(Rect2(x - 15, hy + 7, 30, 30), col)
			if s % 19 == 0:
				var glow = Style.HOT if s % 2 == 0 else Style.P2
				draw_circle(Vector2(x + 8, hy - 16), 7.0, Color(glow, 0.18))
				draw_line(Vector2(x + 6, hy + 4), Vector2(x + 8, hy - 16), col.lightened(0.15), 4.0)
				draw_circle(Vector2(x + 8, hy - 16), 3.0, glow)  # bâton lumineux
			x += 28.0 + float(s % 6)
	Style.halftone(self, Rect2(0, 320, W, 190), Color(0, 0, 0, 0.28), 12.0, 3.6, Vector2(0, -1))
	# bandeau LED
	var led = Rect2(0, 498, W, 44)
	draw_rect(led, Style.INK)
	draw_rect(led.grow_individual(0, -5, 0, -5), Color("1c1048"))
	var segs = [["JUDO 2D", 26, Style.HOT], ["★", 20, Style.PAPER], ["TOURNOI", 24, Style.P2], ["★", 20, Style.PAPER],
		["KUMIKATA · KUZUSHI · IPPON", 20, Style.P1], ["★", 20, Style.PAPER]]
	var seg_w = []
	var total = 0.0
	for sg in segs:
		var sw = Style.text_width(sg[0], sg[1]) + 34.0
		seg_w.append(sw)
		total += sw
	var x2 = -fmod(frame * 1.5, total)
	while x2 < W:
		for k in segs.size():
			Style.label(self, Vector2(x2, 529), segs[k][0], segs[k][1], segs[k][2], "display")
			x2 += seg_w[k]
	# grands éclats décoratifs aux bords (couleurs des joueurs)
	draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(150, 0), Vector2(30, 330), Vector2(0, 330)]), Style.P1.darkened(0.72))
	draw_colored_polygon(PackedVector2Array([Vector2(W, 0), Vector2(W - 150, 0), Vector2(W - 30, 330), Vector2(W, 330)]), Style.P2.darkened(0.72))


func _draw_mat() -> void:
	# face avant du tatami
	var fr = PackedVector2Array([Vector2(_persp(40, MAT_FRONT), MAT_FRONT), Vector2(_persp(1240, MAT_FRONT), MAT_FRONT),
		Vector2(_persp(1240, MAT_FRONT) + 4, MAT_FRONT + 16), Vector2(_persp(40, MAT_FRONT) - 4, MAT_FRONT + 16)])
	draw_colored_polygon(fr, Style.MAT_SAFETY_SHADE.darkened(0.3))
	draw_rect(Rect2(0, MAT_FRONT + 16, W, H - MAT_FRONT - 16), Color("0d0a1e"))
	# zone de sécurité (bleu) puis zone de combat (jaune)
	_mat_quad(40, 1240, Style.MAT_SAFETY)
	_mat_quad(wx(cfg.mat_left), wx(cfg.mat_right), Style.MAT_COMBAT)
	# coutures des tatamis
	var x = 40.0
	while x <= 1240.0:
		var c = Style.MAT_COMBAT_SHADE if x >= wx(cfg.mat_left) and x <= wx(cfg.mat_right) else Style.MAT_SAFETY_SHADE
		draw_line(Vector2(_persp(x, MAT_BACK), MAT_BACK), Vector2(_persp(x, MAT_FRONT), MAT_FRONT), c, 2.0)
		x += 80.0
	draw_line(Vector2(_persp(40, 604), 604), Vector2(_persp(1240, 604), 604), Color(0, 0, 0, 0.08), 2.0)
	# contour d'encre
	var outline = PackedVector2Array([Vector2(_persp(40, MAT_BACK), MAT_BACK), Vector2(_persp(1240, MAT_BACK), MAT_BACK),
		Vector2(_persp(1240, MAT_FRONT), MAT_FRONT), Vector2(_persp(40, MAT_FRONT), MAT_FRONT), Vector2(_persp(40, MAT_BACK), MAT_BACK)])
	draw_polyline(outline, Style.INK, 4.0, true)
	# bandes de départ (repères tori / uke)
	for sx in [-1, 1]:
		var cx = 640.0 + sx * wx(cfg.start_gap) / 2.0
		var col = Style.GI_WHITE if sx < 0 else Style.GI_BLUE
		draw_line(Vector2(_persp(cx, 590), 590), Vector2(_persp(cx, 618), 618), col, 5.0)


func _mat_quad(x0: float, x1: float, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([Vector2(_persp(x0, MAT_BACK), MAT_BACK), Vector2(_persp(x1, MAT_BACK), MAT_BACK),
		Vector2(_persp(x1, MAT_FRONT), MAT_FRONT), Vector2(_persp(x0, MAT_FRONT), MAT_FRONT)]), col)


# --- Judokas -----------------------------------------------------------------

func _fighter_xform(i: int) -> Transform2D:
	var f: Dictionary = sim.state.fighters[i]
	var lean = clampf(float(f.bal_x) / 10000.0, -1.0, 1.0) * 0.2
	var crouch = 0.0
	if not f.attack.is_empty():
		var atk: Dictionary = f.attack
		crouch = clampf(float(atk.t) / float(atk.entry), 0.0, 1.0)
	return Art.stand_xform(Vector2(_draw_x(i), FEET_Y), f.facing, lean, K, crouch)


## Position d'affichage : écart visuel minimum entre les deux judokas (lisibilité du kumikata).
const VIS_GAP := 118.0
func _draw_x(i: int) -> float:
	var fs: Array = sim.state.fighters
	var x := wx(fs[i].x)
	var ox := wx(fs[1 - i].x)
	var d := absf(ox - x)
	if d < VIS_GAP:
		x -= signf(ox - x) * (VIS_GAP - d) * 0.5
	return x


func _draw_fighters() -> void:
	var nwz: Dictionary = sim.state.newaza
	if not nwz.is_empty() and sim.state.phase in ["newaza", "score", "ended"]:
		_draw_newaza(nwz)
		return
	var th: Dictionary = sim.state.throw
	var throwing: bool = not th.is_empty() and sim.state.phase in ["throw", "score", "ended"]
	if _draw_sprites(th, throwing):
		return
	var xfs = [_fighter_xform(0), _fighter_xform(1)]
	var p = 0.0
	if throwing:
		p = clampf(float(th.t) / float(cfg.throw_ticks), 0.0, 1.0)
		xfs = _throw_xforms(th, p)
	# ombres
	for i in 2:
		Art.shadow(self, Vector2(xfs[i].origin.x, FEET_Y + 2), K, 0.3)
	# ordre de dessin : uke derrière pendant la projection, sinon J2 derrière
	var order = [1, 0]
	if throwing:
		order = [th.uke, th.tori] if th.dir in ["avant", "contre"] and p < 0.5 else [th.tori, th.uke]
	for i in order:
		var pal = Art.palette(i)
		var f: Dictionary = sim.state.fighters[i]
		var xf: Transform2D = xfs[i]
		var o = 1 - i
		var oxf: Transform2D = xfs[o]
		# bras arrière (main gauche), corps, bras avant (main droite)
		_draw_hand(i, 0, xf, oxf, pal, throwing, p)
		Art.draw_body(self, xf, pal, 1.0 if f.attack.is_empty() else 0.4)
		_draw_hand(i, 1, xf, oxf, pal, throwing, p)
		_draw_callout(i, xf)


## Rendu par sprites quand les animations existent. Renvoie false pour retomber
## sur le dessin placeholder (animation absente).
func _draw_sprites(th: Dictionary, throwing: bool) -> bool:
	if libs[0] == null or libs[1] == null:
		return false
	if throwing:
		var a_t := "throw/%s/tori" % th.tech
		var a_u := "throw/%s/uke" % th.tech
		var lt = libs[th.tori]
		var lu = libs[th.uke]
		if not (lt.has(a_t) and lu.has(a_u)):
			return false
		var p := clampf(float(th.t) / float(cfg.throw_ticks), 0.0, 1.0)
		var feet := Vector2(wx(th.tori_x), FEET_Y)
		Art.shadow(self, feet + Vector2(0, 2), K * 1.4, 0.3)
		var first_uke: bool = th.dir in ["avant", "contre"] and p < 0.5
		if first_uke:
			lu.draw(self, a_u, p, 0, feet, th.facing, K)
		lt.draw(self, a_t, p, 0, feet, th.facing, K)
		if not first_uke:
			lu.draw(self, a_u, p, 0, feet, th.facing, K)
		return true
	for i in [1, 0]:
		var f: Dictionary = sim.state.fighters[i]
		var lib = libs[i]
		var feet := Vector2(_draw_x(i), FEET_Y)
		var lean := clampf(float(f.bal_x) / 10000.0, -1.0, 1.0) * 0.2
		Art.shadow(self, feet + Vector2(0, 2), K, 0.3)
		if not f.attack.is_empty() and lib.has("entry/" + f.attack.tech):
			lib.draw(self, "entry/" + f.attack.tech, float(f.attack.t) / float(f.attack.entry), 0, feet, f.facing, K)
		elif f.last_move * f.facing > 0 and lib.has("walk_fwd"):
			lib.draw(self, "walk_fwd", -1.0, frame, feet, f.facing, K, lean)
		elif lib.has("idle"):
			lib.draw(self, "idle", -1.0, frame, feet, f.facing, K, lean)
		else:
			return false
		_draw_callout(i, Art.stand_xform(feet, f.facing, lean, K))
	return true


func _draw_hand(i: int, h: int, xf: Transform2D, oxf: Transform2D, pal: Dictionary, throwing: bool, p: float) -> void:
	var f: Dictionary = sim.state.fighters[i]
	var hand: Dictionary = f.hands[h]
	var shoulder: Vector2 = xf * (Art.SHOULDER_BACK if h == 0 else Art.SHOULDER_FRONT)
	var rest: Vector2 = xf * Art.REST_HANDS[h]
	var target_name: String = cfg.grip_targets[hand.target]
	var target: Vector2 = oxf * Art.GRIP_POINTS[target_name]
	var pos = rest
	var strength = -1.0
	if throwing and ((p > 0.85 and sim.state.throw.tori != i) or (p > 0.7 and sim.state.throw.tori == i and h == 1)):
		pos = rest  # uke lâche ; tori ne garde que la manche
	elif hand.state == Sim.HAND_GRIP or (throwing and hand.state != Sim.HAND_FREE):
		pos = target
		strength = float(hand.trig) / 100.0
	elif hand.state == Sim.HAND_REACH:
		pos = rest.lerp(target, clampf(float(hand.t) / float(cfg.grip_reach_ticks), 0.0, 1.0))
	Art.draw_arm(self, shoulder, pos, pal, h == 0, K, strength)


## Ne-waza : poses articulées selon la situation (transition, osaekomi, clé, étranglement).
func _draw_newaza(nw: Dictionary) -> void:
	var fc: int = nw.facing
	var ctrl := float(nw.control) / 10000.0
	var kind := "transition"
	if not nw.sub.is_empty():
		kind = "%s:%s" % [nw.sub.kind, nw.sub.tech]
	elif nw.osae:
		kind = "osaekomi:%s" % nw.hold
	var poses: Array = Art.ground_poses(kind, frame, ctrl)
	# zoom caméra au sol : la scène est agrandie et recentrée pour rester lisible
	var kg := K * 1.55
	var cx := clampf(wx(nw.x), 360.0, W - 360.0)
	var center: float = poses[0].get("center", 12.0)
	var origin := Vector2(cx - fc * center * kg, FEET_Y + 12.0)
	var xf := Transform2D(0.0, Vector2(fc * kg, kg), 0.0, origin)
	Art.shadow(self, origin + Vector2(fc * center * kg, 2), kg * 1.9, 0.32)
	Art.draw_figure(self, xf, Art.palette(nw.bottom), poses[1])
	Art.draw_figure(self, xf, Art.palette(nw.top), poses[0], ctrl)


## Jauge de contrôle au sol, chrono d'osaekomi, bras de fer des clés et étranglements.
func _draw_newaza_hud() -> void:
	var nw: Dictionary = sim.state.newaza
	if nw.is_empty() or sim.state.phase != "newaza":
		return
	var top: int = nw.top
	var col: Color = Style.P1 if top == 0 else Style.P2
	var r := Rect2(440, 104, 400, 84)
	Style.panel(self, r, Style.INK, col, 3.0, 6.0)
	Style.label(self, Vector2(r.position.x + 28, r.position.y + 26), "NE-WAZA · %s CONTRÔLE" % names[top], 14, col, "black")
	var gr := Rect2(r.position.x + 22, r.position.y + 38, r.size.x - 60, 24)
	Style.gauge(self, gr, float(nw.control) / 10000.0, col)
	for mark in [cfg.toketa_below, cfg.osaekomi_on]:
		var mx := gr.position.x + 4 + (gr.size.x - 8) * float(mark) / 10000.0
		draw_line(Vector2(mx, gr.position.y - 4), Vector2(mx, gr.end.y + 4), Style.PAPER, 2.0)
	if nw.osae:
		var secs: int = nw.osae_t / 60
		var c := Vector2(r.position.x - 50, r.get_center().y)
		draw_circle(c + Vector2(3, 3), 38, Style.INK)
		draw_circle(c, 38, Style.INK)
		draw_arc(c, 32, -PI / 2, -PI / 2 + TAU * clampf(float(nw.osae_t) / float(cfg.osaekomi_ippon), 0.0, 1.0), 48, Style.GOLD, 7.0, true)
		Style.text(self, Vector2(c.x - 40, c.y + 14), str(secs), 38, Style.GOLD, "display", HORIZONTAL_ALIGNMENT_CENTER, 80, 3, 0.0)
		Style.label(self, Vector2(r.position.x + 28, r.end.y - 6), "OSAEKOMI — %s" % sim.tech_name(nw.hold).to_upper(), 13, Style.GOLD, "black")
	elif not nw.sub.is_empty():
		var sub: Dictionary = nw.sub
		var tot := maxf(1.0, float(sub.tp + sub.bp))
		var tr := Rect2(r.position.x, r.end.y + 10, r.size.x, 34)
		Style.panel(self, tr, Style.INK, Style.HOT, 3.0, 4.0)
		var split := tr.position.x + tr.size.x * float(sub.tp) / tot
		draw_rect(Rect2(tr.position.x + 6, tr.position.y + 6, split - tr.position.x - 6, tr.size.y - 12), col)
		draw_rect(Rect2(split, tr.position.y + 6, tr.end.x - 6 - split, tr.size.y - 12), Style.P2 if top == 0 else Style.P1)
		Style.label(self, Vector2(tr.position.x, tr.position.y + 24), sim.tech_name(sub.tech).to_upper(), 16, Style.INK, "black", HORIZONTAL_ALIGNMENT_CENTER, tr.size.x)


## Transforms des deux judokas pendant une projection (p de 0 à 1).
func _throw_xforms(th: Dictionary, p: float) -> Array:
	var pair: Array = Art.throw_xforms(th.dir, th.result == "ippon", th.facing, wx(th.tori_x), wx(th.uke_x), FEET_Y, K, p)
	var res = [Transform2D(), Transform2D()]
	res[th.tori] = pair[0]
	res[th.uke] = pair[1]
	return res


func _draw_callout(i: int, xf: Transform2D) -> void:
	var f: Dictionary = sim.state.fighters[i]
	if f.attack.is_empty():
		return
	var atk: Dictionary = f.attack
	var head: Vector2 = xf * Vector2(0, -124)
	var nm = sim.tech_name(atk.tech).to_upper()
	var col: Color = Style.P1 if i == 0 else Style.P2
	var wdt = Style.text_width(nm, 22) + 40.0
	var r = Rect2(head.x - wdt / 2.0, head.y - 34.0, wdt, 34.0)
	Style.panel(self, r, Style.INK, col, 3.0, 4.0)
	Style.text(self, Vector2(r.position.x, r.position.y + 26), nm, 22, col, "display", HORIZONTAL_ALIGNMENT_CENTER, wdt, 3, 0.0)
	var ratio = clampf(float(atk.t) / float(atk.entry), 0.0, 1.0)
	Style.gauge(self, Rect2(r.position.x + 8, r.end.y + 4, wdt - 16, 12), ratio, col)


# --- HUD ---------------------------------------------------------------------

func _draw_hud() -> void:
	for i in 2:
		_draw_player_hud(i)
	_draw_timer()
	_draw_newaza_hud()


func _mirror(r: Rect2, i: int) -> Rect2:
	if i == 0:
		return r
	return Rect2(W - r.end.x, r.position.y, r.size.x, r.size.y)


func _draw_player_hud(i: int) -> void:
	var f: Dictionary = sim.state.fighters[i]
	var col: Color = Style.P1 if i == 0 else Style.P2
	var flip = i == 1
	# panneau principal
	var pr = _mirror(Rect2(24, 20, 478, 66), i)
	Style.panel(self, pr, Style.NIGHT_2, Style.INK, 4.0, 6.0, Style.SLANT, flip)
	# badge joueur
	var br = _mirror(Rect2(34, 26, 74, 54), i)
	Style.panel(self, br, col, Style.INK, 3.0, 0.0, Style.SLANT, flip)
	Style.text(self, Vector2(br.position.x, br.position.y + 42), "%dP" % (i + 1), 34, Style.INK, "display", HORIZONTAL_ALIGNMENT_CENTER, br.size.x, 1, -1.0)
	# nom
	var name_x = 122.0 if i == 0 else W - 122.0 - 260.0
	var align = HORIZONTAL_ALIGNMENT_LEFT if i == 0 else HORIZONTAL_ALIGNMENT_RIGHT
	Style.text(self, Vector2(name_x, 66), names[i], 38, Style.PAPER, "display", align, 260)
	# tokui-waza
	Style.label(self, Vector2(name_x, 82), "TOKUI : " + sim.tech_name(f.tokui).to_upper(), 12, Style.MUTED, "bold", align, 260)
	# waza-ari (2 cases) + ippon
	for k in 2:
		var wr = _mirror(Rect2(390 + k * 52, 30, 46, 22), i)
		var on: bool = f.waza > k or f.ippon > 0
		Style.panel(self, wr, Style.GOLD if on else Style.NIGHT, Style.INK, 3.0, 0.0, Style.SLANT, flip)
		Style.label(self, Vector2(wr.position.x, wr.position.y + 17), "W", 16, Style.INK if on else Style.MUTED, "black", HORIZONTAL_ALIGNMENT_CENTER, wr.size.x)
	# shidos (cartons jaunes)
	for k in cfg.shido_limit:
		var sr = _mirror(Rect2(398 + k * 30, 58, 20, 24), i)
		var on2: bool = f.shidos > k
		draw_rect(Rect2(sr.position + Vector2(2, 2), sr.size), Style.INK)
		draw_rect(sr, Style.P1 if on2 else Style.NIGHT)
		draw_rect(sr, Style.INK, false, 2.5)
	# endurance
	var ratio = float(f.stamina) / float(cfg.stamina_max)
	var gcol = Style.GOOD if ratio > 0.5 else (Style.P1 if ratio > 0.25 else Style.DANGER)
	var gr = _mirror(Rect2(30, 96, 330, 22), i)
	Style.gauge(self, gr, ratio, gcol, flip)
	Style.label(self, Vector2(gr.position.x + (14 if i == 0 else 0), gr.position.y + 16), "ENDURANCE", 12, Style.INK, "black",
		HORIZONTAL_ALIGNMENT_LEFT if i == 0 else HORIZONTAL_ALIGNMENT_RIGHT, gr.size.x - 14)
	# saisies
	for h in 2:
		var hand: Dictionary = f.hands[h]
		var cr = _mirror(Rect2(30 + h * 168, 126, 160, 28), i)
		var st: int = hand.state
		var fill = Style.NIGHT
		var tcol = Style.MUTED
		if st == Sim.HAND_GRIP:
			fill = col
			tcol = Style.INK
		elif st == Sim.HAND_REACH:
			fill = Style.NIGHT_3
			tcol = Style.PAPER
		Style.panel(self, cr, fill, Style.INK, 3.0, 3.0, Style.SLANT, flip)
		var side = "G" if h == 0 else "D"
		Style.label(self, Vector2(cr.position.x, cr.position.y + 20), "%s · %s" % [side, GRIP_LABELS[hand.target]], 14, tcol, "black", HORIZONTAL_ALIGNMENT_CENTER, cr.size.x)
	# radar de kuzushi
	var rc = Vector2(430.0 if i == 0 else W - 430.0, 152.0)
	if Settings.value("radar") and sim.state.phase != "newaza":
		_draw_radar(rc, f, col)


func _draw_radar(c: Vector2, f: Dictionary, col: Color) -> void:
	var r = 30.0
	draw_circle(c + Vector2(3, 3), r + 4, Style.INK)
	draw_circle(c, r + 4, Style.INK)
	draw_circle(c, r, Style.NIGHT)
	draw_arc(c, r * 0.5, 0, TAU, 24, Style.NIGHT_3, 2.0, true)
	draw_line(c - Vector2(r, 0), c + Vector2(r, 0), Style.NIGHT_3, 1.5)
	draw_line(c - Vector2(0, r), c + Vector2(0, r), Style.NIGHT_3, 1.5)
	var fc: int = f.facing
	Style.label(self, c + Vector2(fc * (r + 8) - (0 if fc > 0 else 18), 5), "AV", 11, Style.MUTED, "black")
	Style.label(self, c + Vector2(-fc * (r + 8) - (18 if fc > 0 else 0), 5), "AR", 11, Style.MUTED, "black")
	var v = Vector2(fc * float(f.bal_x), float(f.bal_y)) / float(cfg.balance_max)
	var mag = clampf(v.length(), 0.0, 1.0)
	var dot = c + v.limit_length(1.0) * r
	var dcol = Style.GOOD.lerp(Style.DANGER, mag)
	draw_line(c, dot, dcol, 3.0, true)
	draw_circle(dot, 7.0, Style.INK)
	draw_circle(dot, 5.0, dcol)
	if mag > 0.65:
		draw_arc(c, r + 4, 0, TAU, 32, Style.DANGER, 3.0, true)


func _draw_timer() -> void:
	var r = Rect2(552, 16, 176, 76)
	Style.panel(self, r, Style.INK, Style.HOT if sim.state.golden else Style.PAPER, 4.0, 6.0)
	var ticks: int = sim.state.clock
	var secs = int(ceil(ticks / 60.0)) if not sim.state.golden else ticks / 60
	var txt = "%d:%02d" % [secs / 60, secs % 60]
	if sim.state.golden:
		txt = "+" + txt
	Style.text(self, Vector2(r.position.x, r.position.y + 60), txt, 58, Style.HOT if sim.state.golden else Style.PAPER, "display", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 4, 0.0)
	if sim.state.golden:
		var gr = Rect2(562, 96, 156, 26)
		Style.panel(self, gr, Style.HOT, Style.INK, 3.0, 3.0)
		Style.label(self, Vector2(gr.position.x, gr.position.y + 19), "GOLDEN SCORE", 16, Style.INK, "black", HORIZONTAL_ALIGNMENT_CENTER, gr.size.x)


func _draw_popups() -> void:
	var stack = [0, 0]
	for p in popups:
		var f: Dictionary = sim.state.fighters[p.who]
		var x = wx(f.x)
		var y = FEET_Y - 250.0 - stack[p.who] * 30.0 - minf(p.t, 20) * 1.2
		stack[p.who] += 1
		var a = 1.0 if p.t < 50 else 1.0 - (p.t - 50) / 20.0
		var col: Color = p.color
		col.a = a
		var wdt = Style.text_width(p.text, 24) + 20
		Style.text(self, Vector2(x - wdt / 2, y), p.text, 24, col, "display", HORIZONTAL_ALIGNMENT_CENTER, wdt, 4, 2.0)


func _draw_announce() -> void:
	var t: int = sim.state.announce_t
	if t <= 0:
		return
	var txt: String = sim.state.announce
	var age = 90 - t
	var s = 1.0 + maxf(0.0, (8 - age) / 8.0) * 0.35
	var alpha = 1.0 if t > 15 else t / 15.0
	var c = Vector2(640, 300)
	var col = Style.PAPER
	var fsize = 96
	match txt:
		"OSAEKOMI":
			col = Style.INK
			var ob := Rect2(c.x - 300 * s, c.y - 66 * s, 600 * s, 110 * s)
			Style.panel(self, ob, Color(Style.GOLD, alpha), Style.INK, 5.0, 8.0)
			fsize = 84
		"IPPON !":
			col = Style.GOLD
			fsize = 132
			Style.speed_lines(self, c, 150, 420, 46, Color(1, 0.85, 0.2, 0.55 * alpha))
			Style.burst(self, c, 120 * s, 190 * s, 14, Color(Style.HOT, alpha), Style.INK, 11, age * 0.01)
		"WAZA-ARI":
			col = Style.PAPER
			fsize = 100
			Style.speed_lines(self, c, 130, 360, 36, Color(0.24, 0.9, 1, 0.45 * alpha))
			Style.burst(self, c, 100 * s, 150 * s, 12, Color(Style.P2_DEEP, alpha), Style.INK, 5)
		"SHIDO", "HANSOKU-MAKE":
			col = Style.INK if txt == "SHIDO" else Style.PAPER
			var card = Rect2(c.x - 230 * s, c.y - 70 * s, 460 * s, 120 * s)
			Style.panel(self, card, Color(Style.P1 if txt == "SHIDO" else Style.DANGER, alpha), Style.INK, 5.0, 8.0)
			fsize = 88
		_:
			var pc = Style.HOT if txt in ["HAJIME", "GOLDEN SCORE"] else Style.NIGHT_2
			if txt == "GOLDEN SCORE":
				pc = Style.GOLD
				col = Style.INK
			var band = Rect2(c.x - 300 * s, c.y - 66 * s, 600 * s, 110 * s)
			Style.panel(self, band, Color(pc, alpha), Style.INK, 5.0, 8.0)
			fsize = 84
	var tc = col
	tc.a = alpha
	Style.text(self, Vector2(0, c.y + fsize * 0.36), txt, int(fsize * s), tc, "display", HORIZONTAL_ALIGNMENT_CENTER, W, int(fsize * s / 10), 6.0)


func _draw_feed() -> void:
	var y = 662.0
	for k in range(feed.size() - 1, -1, -1):
		var e: Dictionary = feed[k]
		var a = 1.0 if e.t < 300 else maxf(0.0, 1.0 - (e.t - 300) / 60.0)
		if a <= 0.0:
			continue
		var wdt = Style.text_width(e.text, 15, "black") + 34
		var r = Rect2(24, y - 24, wdt, 26)
		Style.panel(self, r, Color(Style.INK, 0.85 * a), Color(e.color, a), 2.0, 0.0)
		Style.label(self, Vector2(r.position.x + 14, r.position.y + 19), e.text, 15, Color(e.color, a), "black")
		y -= 31.0


func _draw_hints() -> void:
	var y = 694.0
	var x = 28.0
	if sim.state.phase == "newaza":
		var nitems = [["A", "Contrôler"], ["X", "Clé de bras"], ["Y", "Étranglement"], ["B", "Se dégager"], ["R", "Stick gauche : gigoter (dessous)"]]
		for it in nitems:
			if it[0] == "R":
				Style.label(self, Vector2(x, y + 6), it[1], 15, Style.MUTED, "bold")
				continue
			Style.pad_button(self, Vector2(x + 12, y), it[0], 12.0)
			x += 34.0
			Style.label(self, Vector2(x, y + 6), it[1], 15, Style.MUTED, "bold")
			x += Style.text_width(it[1], 15, "bold") + 26
		return
	var items = [["LT", "RT", "Saisir"], ["LB", "RB", "Cible"], ["R", "", "Stick droit : kuzushi"], ["A", "", "Technique"],
		["X", "", "Jambe"], ["Y", "", "Tokui"], ["B", "", "Casser / contrer"]]
	for it in items:
		if it[0] == "R":
			Style.label(self, Vector2(x, y + 6), it[2], 15, Style.MUTED, "bold")
			x += Style.text_width(it[2], 15, "bold") + 26
			continue
		Style.pad_button(self, Vector2(x + 12, y), it[0], 12.0)
		x += 34.0 if it[0].length() == 1 else 40.0
		if it[1] != "":
			Style.pad_button(self, Vector2(x + 12, y), it[1], 12.0)
			x += 40.0
		Style.label(self, Vector2(x, y + 6), it[2], 15, Style.MUTED, "bold")
		x += Style.text_width(it[2], 15, "bold") + 26


func _draw_pause() -> void:
	draw_rect(Rect2(0, 0, W, H), Color(0.04, 0.03, 0.1, 0.72))
	Style.halftone(self, Rect2(0, 0, W, H), Color(1, 1, 1, 0.04), 18.0, 5.0, Vector2(1, 0))
	Style.text(self, Vector2(0, 200), "PAUSE", 96, Style.PAPER, "display", HORIZONTAL_ALIGNMENT_CENTER, W)
	for k in PAUSE_ITEMS.size():
		var sel = k == pause_index
		var r = Rect2(440 - (12 if sel else 0), 250 + k * 70, 400 + (24 if sel else 0), 56)
		Style.panel(self, r, Style.HOT if sel else Style.NIGHT_2, Style.INK, 4.0, 6.0)
		Style.text(self, Vector2(r.position.x, r.position.y + 41), PAUSE_ITEMS[k], 32, Style.INK if sel else Style.PAPER, "display", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 3, 0.0)
