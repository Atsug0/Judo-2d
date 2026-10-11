extends RefCounted
## Contenu du dojo : tutoriel des fondamentaux, guide de chaque technique,
## enchaînements, contres et ne-waza. Chaque leçon = des étapes validées par le jeu.
##
## Étape : {"title", "text" (jetons {A} {B} {X} {Y} {LT} {RT} {LB} {RB} {LS} {RS}),
##   "goal": {"type": ..., paramètres}, "count": n, "partner": comportement,
##   "setup": "" | "gripped" | "newaza_top" | "newaza_bottom", "tip": conseil facultatif}
## Types d'objectif : voir dojo_session.gd (_check_goal).

const GameData := preload("res://scripts/game_data.gd")

const CATEGORIES := [
	{"id": "base", "name": "FONDAMENTAUX", "desc": "Tout le système de combat, pas à pas : distance, kumikata, kuzushi, projections, défense, sol."},
	{"id": "tech", "name": "TECHNIQUES", "desc": "Le guide de chaque technique : la bonne garde, la bonne direction de kuzushi, le placement."},
	{"id": "combo", "name": "ENCHAÎNEMENTS", "desc": "Faire réagir pour mieux projeter : la première technique ouvre la seconde."},
	{"id": "counter", "name": "CONTRES", "desc": "Punir une attaque mal préparée : le bon contre au bon moment."},
	{"id": "sol", "name": "NE-WAZA", "desc": "Le combat au sol : immobilisations, clés de bras, étranglements, sorties."},
]

const GRIP_FR := {"sleeve": "la manche", "lapel": "le revers", "collar": "le col haut", "belt": "la ceinture"}
const DIR_FR := {"avant": "vers l'avant", "arriere": "vers l'arrière", "cote": "sur le côté",
	"avant_cote": "vers l'avant-côté", "arriere_cote": "vers l'arrière-côté"}
## Stick droit pour chaque direction de kuzushi (vu du joueur 1, tourné vers la droite).
const DIR_STICK := {"avant": "tire {RS} vers toi (vers l'arrière)", "arriere": "pousse {RS} vers lui",
	"cote": "pousse {RS} vers le haut ou le bas", "avant_cote": "tire {RS} vers toi en diagonale",
	"arriere_cote": "pousse {RS} vers lui en diagonale"}

const TIPS := {
	"seoi_nage": "Tire sa manche haut et vers l'avant, pivote, ton épaule vient sous son aisselle.",
	"ippon_seoi_nage": "Une seule manche suffit : ton bras se glisse sous son aisselle. Parfait quand il refuse le revers.",
	"tai_otoshi": "Pas de hanche : ta jambe barre son tibia et tes mains le font tourner par-dessus.",
	"uchi_mata": "Gros kuzushi avant, ta jambe fauche l'intérieur de sa cuisse. Ippon assuré, mais le sukashi la punit.",
	"harai_goshi": "Col haut ou ceinture : colle ta hanche et balaye sa jambe. Lente mais dévastatrice.",
	"o_goshi": "La hanche de base : ton bras passe dans son dos (ceinture), il roule par-dessus ta hanche.",
	"o_soto_gari": "Kuzushi arrière, tu avances et tu fauches sa jambe d'appui par l'extérieur. Gare à l'o-soto-gaeshi.",
	"o_uchi_gari": "Fauchage intérieur vers l'arrière, rapide et peu risqué. Idéal pour ouvrir un enchaînement.",
	"ko_uchi_gari": "On accroche le talon, très vite. Elle marque rarement seule, mais fait toujours réagir.",
	"de_ashi_barai": "Balaye son pied avancé au moment où il pose le poids : quand il te suit, ses pieds sont légers.",
	"sasae_tsurikomi_ashi": "Ton pied bloque sa cheville, tes mains le font tourner vers l'avant-côté.",
	"tomoe_nage": "Sacrifice : tu tombes sur le dos, pied dans son ventre, il passe au-dessus. Raté, tu es dessous.",
	"sumi_gaeshi": "Sacrifice en coin : tu t'assois sous lui et tu le fais basculer avec ton crochet de jambe.",
}

static var _techs := {}


static func techs() -> Dictionary:
	if _techs.is_empty():
		_techs = GameData.load_json("res://data/techniques.json")
	return _techs


## Build compact : tokui + techniques + enchaînements + contres + sol.
static func build(bname: String, tokui: String, main: Array = [], combo: Array = [], counter: Array = [], ground: Array = [],
		style: String = "classique", garde: String = "droitier", sol: int = 5) -> Dictionary:
	return {"name": bname, "garde": garde, "style": style,
		"slots": {"tokui": [tokui], "main": main, "combo": combo, "counter": counter, "ground": ground},
		"physique": {"explosivite": 5, "endurance": 5, "poigne": 5, "sol": sol}}


static func player_default() -> Dictionary:
	return build("TOI", "seoi_nage", ["o_soto_gari", "o_uchi_gari", "ko_uchi_gari", "de_ashi_barai"], [], [], ["kesa_gatame"])


static func partner_default() -> Dictionary:
	return build("UKE", "o_soto_gari", ["o_uchi_gari", "uchi_mata"], [], [], ["kesa_gatame"], "classique", "droitier")


static func _s(title: String, text: String, goal: Dictionary, partner: String = "garde", count: int = 1, setup: String = "", tip: String = "") -> Dictionary:
	return {"title": title, "text": text, "goal": goal, "partner": partner, "count": count, "setup": setup, "tip": tip}


# =============================================================================
# Leçons
# =============================================================================

static var _all: Array = []


static func all() -> Array:
	if _all.is_empty():
		_all = _fundamentals() + _technique_guides() + _combo_lessons() + _counter_lessons() + _ground_lessons()
	return _all


static func by_id(id: String) -> Dictionary:
	for l in all():
		if l.id == id:
			return l
	return {}


static func in_category(cat: String) -> Array:
	var out = []
	for l in all():
		if l.cat == cat:
			out.append(l)
	return out


static func next_of(id: String) -> String:
	var list = all()
	for k in list.size():
		if list[k].id == id and k + 1 < list.size():
			return list[k + 1].id
	return ""


static func _fundamentals() -> Array:
	var P = player_default()
	var U = partner_default()
	var L = []
	L.append({"id": "b1_distance", "cat": "base", "title": "Distance et dash", "player": P, "partner_build": U,
		"intro": "Au judo, tout commence par la distance. Hors de portée, tu es en sécurité. À portée de bras, la bataille de mains commence.",
		"steps": [
			_s("Approche", "Avance avec {LS} jusqu'à la distance de garde : à portée de bras.", {"type": "range"}, "static"),
			_s("Recule", "Reviens hors de portée avec {LS}.", {"type": "away"}, "static"),
			_s("Dash avant", "Pichenette franche de {LS} vers lui : un dash. Repars du neutre à chaque fois.", {"type": "dash", "dir": "in"}, "static", 2,
				"", "Le dash avant rend tes mains plus rapides pendant un court instant : idéal pour saisir le premier."),
			_s("Dash arrière", "Pichenette de {LS} vers l'arrière : tu sors de portée d'un coup.", {"type": "dash", "dir": "out"}, "static", 2),
		]})
	L.append({"id": "b2_saisir", "cat": "base", "title": "Kumikata : saisir", "player": P, "partner_build": U,
		"intro": "Chaque gâchette commande une main. Une main tend vers sa cible, puis saisit, puis s'enfonce : une prise profonde tire plus fort et domine.",
		"steps": [
			_s("Main gauche", "À portée, maintiens {LT} : ta main gauche saisit la manche.", {"type": "grip", "hand": 0}, "static"),
			_s("Main droite", "Maintiens aussi {RT} : ta main droite saisit le revers.", {"type": "grip_pair"}, "static"),
			_s("Prise profonde", "Serre fort les deux gâchettes : la barre sous chaque main se remplit, ta prise devient profonde.", {"type": "settled"}, "static", 1, "",
				"Serrer à fond chauffe l'avant-bras (la main clignote en rouge). Desserre un peu pour récupérer, sinon ta main finit par lâcher."),
			_s("Change de cible", "Appuie sur {RB} : ta main droite monte au col haut. Le col domine, mais fatigue vite.", {"type": "grip", "target": "collar"}, "static"),
		]})
	L.append({"id": "b3_mains", "cat": "base", "title": "Bataille de mains", "player": P, "partner_build": U,
		"intro": "La bataille de mains ne s'arrête jamais : une main qui arrive se chasse, une prise posée s'arrache, et il faut la reprendre aussitôt.",
		"steps": [
			_s("Chasse sa main", "Il tend la main vers toi : appuie sur {B} pendant qu'elle arrive pour la chasser.", {"type": "parry"}, "reach", 3, "",
				"Une main chassée est bloquée un instant : profites-en pour saisir le premier."),
			_s("Esquive", "Quand sa main arrive, dash arrière ({LS} en pichenette) : elle part dans le vide.", {"type": "whiff"}, "reach", 1),
			_s("Arrache sa prise", "Il te tient : {B} en tirant {RS} vers toi arrache sa prise la plus profonde. Insiste si elle tient.", {"type": "break"}, "garde", 2, "",
				"Une prise fraîche part du premier coup, une prise profonde en demande plusieurs."),
			_s("Deux mains", "Lâche tes gâchettes, puis {B} : tes deux mains attaquent sa prise, bien plus fort.", {"type": "break", "how": "deux_mains"}, "garde", 1, "",
				"Sans aucune prise, tu ne peux pas attaquer : arrache, puis reprends la garde avant lui."),
			_s("Prends le dessus", "Saisis le premier et installe ta garde : remplis la jauge de domination de ton côté.", {"type": "dom", "min": 5000}, "reach", 1, "",
				"Le dominant déséquilibre plus fort et ses techniques passent mieux. Le dominé se fait courber."),
		]})
	L.append({"id": "b4_mener", "cat": "base", "title": "Mener le couple", "player": P, "partner_build": U,
		"intro": "En garde, le couple se déplace d'un bloc. Celui qui domine le kumikata l'emmène où il veut ; l'autre suit ou résiste.",
		"steps": [
			_s("Pousse-le", "En garde, avance avec {LS} : tu l'emmènes en arrière sur le tapis.", {"type": "drive", "dir": "in", "px": 160}, "garde", 1, "gripped"),
			_s("Tire-le", "Recule avec {LS} : il est obligé de te suivre.", {"type": "drive", "dir": "out", "px": 160}, "garde", 1, "gripped",
				"Reculer en tirant, c'est aussi le tsukuri des techniques vers l'avant."),
			_s("Malgré lui", "Il résiste à tes tractions. Domine la garde (prises profondes) et emmène-le quand même.", {"type": "drive", "dir": "in", "px": 120}, "resiste", 1, "gripped",
				"Attention au bord : celui qui sort du tapis prend un shido."),
		]})
	L.append({"id": "b4_kuzushi", "cat": "base", "title": "Kuzushi", "player": P, "partner_build": U,
		"intro": "Kuzushi : casser l'équilibre. Avec ta garde, le stick droit tire ou pousse ton partenaire. Le radar sous sa jauge montre son déséquilibre.",
		"steps": [
			_s("Vers l'avant", "Avec ta garde, tire {RS} vers toi : il bascule vers l'avant.", {"type": "kuzushi", "dir": "avant", "min": 5000}, "static", 1, "gripped"),
			_s("Vers l'arrière", "Pousse {RS} vers lui : il bascule vers l'arrière.", {"type": "kuzushi", "dir": "arriere", "min": 5000}, "static", 1, "gripped"),
			_s("Sur le côté", "Pousse {RS} vers le haut ou le bas : il bascule sur le côté.", {"type": "kuzushi", "dir": "cote", "min": 5000}, "static", 1, "gripped"),
			_s("Tsukuri", "Recule avec {LS} tout en tirant {RS} vers toi : le déséquilibre est bien plus fort.", {"type": "tsukuri", "min": 7500}, "static", 1, "gripped",
				"Reculer en tirant amplifie l'avant ; avancer en poussant amplifie l'arrière."),
		]})
	L.append({"id": "b5_projeter", "cat": "base", "title": "Projeter", "player": P, "partner_build": U,
		"intro": "{A} lance la technique de ton set qui colle le mieux au déséquilibre du moment, {X} une technique de jambe, {Y} ta tokui-waza. Plus le kuzushi est fort, plus le score est grand.",
		"steps": [
			_s("Projection avant", "Kuzushi vers l'avant, puis {A} : seoi-nage.", {"type": "throw", "dir": "avant"}, "garde", 1, "gripped"),
			_s("Projection arrière", "Kuzushi vers l'arrière, puis {X} : une technique de jambe.", {"type": "throw", "dir": "arriere"}, "garde", 1, "gripped"),
			_s("Tokui-waza", "{Y} lance toujours ta technique favorite, avec un bonus. Prépare-la et marque.", {"type": "throw", "tech": "seoi_nage"}, "garde", 1, "gripped"),
			_s("Ippon", "Un ippon demande un kuzushi énorme et une garde complète. Vas-y.", {"type": "throw", "result": "ippon"}, "garde", 1, "gripped",
				"Garde installée + tsukuri + technique dans la bonne direction = ippon."),
		]})
	L.append({"id": "b6_reaction", "cat": "base", "title": "Action-réaction", "player": P, "partner_build": U,
		"intro": "Quand tu tires, il réagit. S'il résiste, il s'appuie dans l'autre sens : emmène-le de ce côté. S'il suit, ses pieds sont légers : balaye-les.",
		"steps": [
			_s("Il résiste", "Tire-le vers l'avant : il recule pour résister. Puis pousse-le d'un coup vers l'arrière.", {"type": "reaction"}, "resiste", 1, "gripped",
				"« ACTION-RÉACTION ! » : son propre appui l'emmène. Son appui retombe vite, sois vif."),
			_s("Contre-pied", "Même principe, et cette fois projette dans le sens de sa réaction avec {X}.", {"type": "throw", "dir": "arriere"}, "resiste", 1, "gripped"),
			_s("Il suit", "Tire-le : il te suit en marchant. Balaye son pied pendant qu'il avance ({X}).", {"type": "throw", "sweep": true}, "suit", 1, "gripped",
				"De-ashi-barai sur le pas : le timing compte plus que la force."),
			_s("Changement de rythme", "En saisie, un dash arrière donne un coup sec qui l'arrache vers l'avant. Enchaîne {A}.", {"type": "throw", "dir": "avant"}, "garde", 1, "gripped"),
		]})
	L.append({"id": "b7_feinte", "cat": "base", "title": "Feintes", "player": P, "partner_build": U,
		"intro": "Un simple tap sur un bouton de technique, relâché aussitôt, est une feinte : il se raidit dans l'autre sens. Trois feintes trop rapprochées donnent un shido.",
		"steps": [
			_s("Feinte", "Tape {A} très brièvement (relâche tout de suite) : feinte vers l'avant.", {"type": "feint"}, "garde", 2, "gripped"),
			_s("Feinte puis attaque", "Feinte vers l'avant, il recule : attaque vers l'arrière ({X}) dans la foulée.", {"type": "feint_throw"}, "garde", 1, "gripped"),
		]})
	L.append({"id": "b8_defense", "cat": "base", "title": "Se défendre", "player": P, "partner_build": build("UKE", "seoi_nage", ["o_soto_gari"]),
		"intro": "{B} pendant l'entrée adverse : tu bloques. Une attaque bloquée perd beaucoup de sa force.",
		"steps": [
			_s("Bloque", "Il va attaquer : appuie sur {B} pendant son entrée.", {"type": "block"}, "attaque", 3, "gripped",
				"Regarde la jauge au-dessus de sa tête : c'est le temps d'entrée de sa technique."),
		]})
	L.append({"id": "b9_contre", "cat": "base", "title": "Contrer", "player": build("TOI", "seoi_nage", ["o_soto_gari", "o_uchi_gari"], [], ["ura_nage"], ["kesa_gatame"]),
		"partner_build": build("UKE", "seoi_nage", ["o_soto_gari"]),
		"intro": "Si l'attaque adverse est mal préparée (pas de kuzushi sur toi), {B} déclenche le contre équipé au lieu du blocage. Une attaque ratée l'expose aussi.",
		"steps": [
			_s("Ura-nage", "Il attaque en seoi-nage sans te déséquilibrer : {B} pendant son entrée pour l'ura-nage.", {"type": "counter"}, "attaque", 2, "gripped",
				"Tu ne contres que ce que ton set permet : chaque contre se choisit en personnalisation."),
		]})
	L.append({"id": "b10_sol", "cat": "base", "title": "Le sol", "player": P, "partner_build": U,
		"intro": "Après un waza-ari, le combat continue au sol. Dessus, tu contrôles ; dessous, tu te dégages.",
		"steps": [
			_s("Contrôle", "Dessus : maintiens {A} pour monter la jauge de contrôle jusqu'à l'osaekomi.", {"type": "osaekomi"}, "sol_passif", 1, "newaza_top"),
			_s("Tiens 10 secondes", "Osaekomi ! Appuie sur {A} quand ton curseur passe dans ta zone colorée. 10 s = waza-ari, 20 s = ippon.", {"type": "osae_time", "ticks": 600}, "sol_resiste", 1, "newaza_top",
				"Centre doré = coup parfait. Un raté bloque ta main un instant. Chaque coup réussi rétrécit sa zone à lui."),
			_s("Dessous : sors", "Dessous : {B} en rafale fait baisser son contrôle. S'il immobilise, vise ta zone avec {B} pour remplir la jauge de sortie.", {"type": "escape"}, "sol_dessus", 1, "newaza_bottom",
				"Fatigué, ton curseur va plus vite : garde de l'endurance pour le sol."),
		]})
	L.append({"id": "b11_regles", "cat": "base", "title": "Les règles", "player": P, "partner_build": U,
		"intro": "Combat de 4 minutes. Ippon = victoire. Deux waza-ari = ippon. Égalité à la fin : golden score, le premier qui marque gagne.",
		"steps": [
			_s("Shidos", "Pénalités : passivité, fausses attaques, sortie de tapis, refus de kumikata. 3 shidos = hansoku-make (défaite). Appuie sur {A}.", {"type": "read"}, "static"),
			_s("Refus de kumikata", "Rester à portée sans jamais saisir est sanctionné. Casser et chasser, oui, mais saisis aussi ! Appuie sur {A}.", {"type": "read"}, "static"),
			_s("Endurance", "Serrer, tirer, dasher, casser : tout fatigue. Épuisé, tes mains lâchent et tes techniques perdent en force. Appuie sur {A}.", {"type": "read"}, "static"),
		]})
	return L


static func _technique_guides() -> Array:
	var L = []
	var T = techs()
	for id in ["seoi_nage", "ippon_seoi_nage", "tai_otoshi", "uchi_mata", "harai_goshi", "o_goshi", "o_soto_gari",
			"o_uchi_gari", "ko_uchi_gari", "de_ashi_barai", "sasae_tsurikomi_ashi", "tomoe_nage", "sumi_gaeshi"]:
		var t: Dictionary = T[id]
		var grips: Array = t.grips[0]
		var gtxt = " et ".join(grips.map(func(g): return GRIP_FR[g]))
		var gsteps = []
		# saisies nécessaires (LB/RB pour changer de cible)
		var need_collar: bool = grips.has("collar")
		var need_belt: bool = grips.has("belt")
		var grip_text = "Prends ta garde : %s." % gtxt
		if need_collar:
			grip_text += " Main droite au col : {RB} pour changer de cible."
		elif need_belt:
			grip_text += " Main droite à la ceinture : {RB} jusqu'à « CEINTURE »."
		elif grips == ["lapel", "lapel"]:
			grip_text += " Main gauche au revers : {LB} pour changer de cible."
		gsteps.append(_s("La garde", grip_text, {"type": "grip_set", "targets": grips}, "static"))
		gsteps.append(_s("Le kuzushi", "Déséquilibre-le %s : %s." % [DIR_FR[t.dir], DIR_STICK[t.dir]],
			{"type": "kuzushi", "dir": t.dir, "min": 6000}, "static", 1, "gripped"))
		gsteps.append(_s("La projection", "Kuzushi %s, puis {Y} : %s." % [DIR_FR[t.dir], t.name], {"type": "throw", "tech": id}, "garde", 2, "gripped", TIPS.get(id, "")))
		gsteps.append(_s("Ippon", "Marque ippon avec %s." % t.name, {"type": "throw", "tech": id, "result": "ippon"}, "garde", 1, "gripped"))
		var info = "%s · famille %s · direction %s · vitesse %d · puissance %d." % [t.name, t.family, DIR_FR[t.dir], t.speed, t.power]
		if t.counter != "":
			info += " Contrée par %s." % T._counters[t.counter].name
		if t.get("sutemi", false):
			info += " Sacrifice : raté, tu te retrouves au sol dessous."
		L.append({"id": "t_" + id, "cat": "tech", "title": t.name, "tech": id,
			"player": build("TOI", id, [], [], [], ["kesa_gatame"]), "partner_build": partner_default(),
			"intro": info + " " + TIPS.get(id, ""), "steps": gsteps})
	return L


static func _combo_lessons() -> Array:
	var L = []
	var T = techs()
	for cid in T._combos:
		var c: Array = T._combos[cid]
		var a: Dictionary = T[c[0]]
		var b: Dictionary = T[c[1]]
		var p = build("TOI", c[1], [c[0]], [cid], [], ["kesa_gatame"])
		var first_btn = "{X}" if a.family == "ashi" else "{A}"
		var second_btn = "{Y}"
		L.append({"id": "c_" + cid, "cat": "combo", "title": "%s → %s" % [a.name, b.name], "player": p, "partner_build": partner_default(),
			"intro": "%s le fait réagir %s ; il résiste à l'opposé, et %s part dans le sens de sa réaction. La fenêtre d'enchaînement est courte !" % [a.name, DIR_FR[a.dir], b.name],
			"steps": [
				_s("Ouvre", "Lance %s (%s) avec un kuzushi moyen : il se fait stopper, c'est voulu. « ENCHAÎNE ! » s'affiche." % [a.name, first_btn],
					{"type": "combo_open"}, "garde", 2, "gripped", "Trop de kuzushi et la première marque directement : c'est bien aussi, mais ce n'est pas l'exercice."),
				_s("Enchaîne", "Pendant « ENCHAÎNE ! », lance tout de suite %s (%s)." % [b.name, second_btn],
					{"type": "combo_throw"}, "garde", 2, "gripped", "La seconde technique entre plus vite et avec un bonus de score."),
			]})
	return L


static func _counter_lessons() -> Array:
	var L = []
	var T = techs()
	var pairs = {"ura_nage": "seoi_nage", "utsuri_goshi": "harai_goshi", "uchi_mata_sukashi": "uchi_mata",
		"o_soto_gaeshi": "o_soto_gari", "tsubame_gaeshi": "de_ashi_barai"}
	for cid in pairs:
		var att: String = pairs[cid]
		var cn: Dictionary = T._counters[cid]
		L.append({"id": "k_" + cid, "cat": "counter", "title": cn.name, "player": build("TOI", "seoi_nage", ["o_soto_gari"], [], [cid], ["kesa_gatame"]),
			"partner_build": build("UKE", att, []),
			"intro": "%s répond à %s. Ton partenaire va l'attaquer sans préparation : sens l'entrée et contre." % [cn.name, T[att].name],
			"steps": [
				_s("Sens l'entrée", "Il va attaquer : appuie sur {B} pendant son entrée (la jauge au-dessus de sa tête).", {"type": "block_or_counter"}, "attaque", 1, "gripped"),
				_s("Contre", "Il attaque sans kuzushi : {B} pendant son entrée déclenche %s." % cn.name, {"type": "counter", "tech": cid}, "attaque", 2, "gripped",
					"Le contre ne part que si sa technique est mal préparée. Bien préparée, {B} ne fait que bloquer."),
			]})
	return L


static func _ground_lessons() -> Array:
	var L = []
	var T = techs()
	for gid in T._newaza:
		var g: Dictionary = T._newaza[gid]
		var p = build("TOI", "seoi_nage", ["o_soto_gari"], [], [], [gid], "classique", "droitier", 7)
		var steps = []
		match g.kind:
			"osaekomi":
				steps.append(_s("Contrôle", "Dessus, maintiens {A} : la jauge de contrôle monte jusqu'à %s." % g.name, {"type": "osaekomi"}, "sol_passif", 1, "newaza_top"))
				steps.append(_s("Tiens", "Vise ta zone avec {A} à chaque passage du curseur : tiens 10 secondes malgré ses efforts.", {"type": "osae_time", "ticks": 600}, "sol_resiste", 1, "newaza_top"))
				steps.append(_s("Ippon", "Tiens 20 secondes : ippon. Vise le centre doré pour l'étouffer.", {"type": "osae_time", "ticks": 1200}, "sol_resiste", 1, "newaza_top"))
			"kansetsu":
				steps.append(_s("Contrôle", "Maintiens {A} pour monter le contrôle au-dessus de la ligne.", {"type": "control", "min": 7600}, "sol_passif", 1, "newaza_top"))
				steps.append(_s("La clé", "Contrôle haut, appuie sur {X} : %s. Puis garde {X} enfoncé pendant le bras de fer." % g.name,
					{"type": "submission", "tech": gid}, "sol_resiste", 1, "newaza_top", "Il se débat avec {B} : ton niveau au sol décide de qui gagne le bras de fer."))
			"shime":
				steps.append(_s("Contrôle", "Maintiens {A} pour monter le contrôle au-dessus de la ligne.", {"type": "control", "min": 7600}, "sol_passif", 1, "newaza_top"))
				steps.append(_s("L'étranglement", "Contrôle haut, appuie sur {Y} : %s. Puis garde {Y} enfoncé." % g.name,
					{"type": "submission", "tech": gid}, "sol_resiste", 1, "newaza_top"))
		L.append({"id": "n_" + gid, "cat": "sol", "title": g.name, "player": p, "partner_build": partner_default(),
			"intro": "%s (%s). Au sol, ta caractéristique « sol » compte : contrôle plus rapide, bras de fer plus solide." % [g.name,
				{"osaekomi": "immobilisation", "kansetsu": "clé de bras", "shime": "étranglement"}[g.kind]], "steps": steps})
	L.append({"id": "n_garde", "cat": "sol", "title": "Attaquer depuis la garde", "player": build("TOI", "seoi_nage", ["o_soto_gari"], [], [], ["juji_gatame", "sankaku_jime"], "classique", "droitier", 7),
		"partner_build": partner_default(),
		"intro": "Dessous, tu n'es pas perdu : si son contrôle est faible, une clé ou un étranglement équipé retourne la situation.",
		"steps": [
			_s("Retournement", "Dessous, quand sa jauge de contrôle est basse : {X} pour juji-gatame depuis la garde.", {"type": "reversal"}, "sol_passif", 1, "newaza_bottom",
				"Possible seulement avant l'osaekomi. Chaque {B} fait baisser son contrôle d'abord."),
			_s("Jusqu'à l'abandon", "Retourne-le avec {X}, puis garde {X} enfoncé : gagne le bras de fer jusqu'à l'abandon.", {"type": "submission"}, "sol_passif", 1, "newaza_bottom"),
		]})
	L.append({"id": "n_sortie", "cat": "sol", "title": "Sortir par-dessous", "player": player_default(), "partner_build": partner_default(),
		"intro": "Avant l'osaekomi, chaque {B} fait baisser son contrôle. Pendant l'osaekomi, vise ta zone avec {B} : jauge de sortie pleine = toketa.",
		"steps": [
			_s("Toketa ou sortie", "Dessous : sors avant l'osaekomi, ou vise ta zone avec {B} jusqu'à toketa.", {"type": "escape"}, "sol_dessus", 2, "newaza_bottom",
				"Un raté te bloque un instant et fait reculer ta jauge de sortie : vise juste plutôt que vite."),
		]})
	return L
