extends RefCounted
## Lecture de la situation pour l'affichage (HUD, dojo) : ce que donnerait chaque
## bouton maintenant, sans rien modifier à la simulation.

const Sim := preload("res://scripts/sim/match_sim.gd")
const Style := preload("res://scripts/ui/style.gd")

const BUTTONS := [["A", Sim.BA], ["X", Sim.BX], ["Y", Sim.BY]]


## Technique et issue prévisible du bouton `btn` pour le combattant `i`.
## outcome : "ippon", "waza", "stoppe", "expose" ; counter_risk : l'adversaire a le contre équipé
## et la technique est mal préparée (il peut la contrer en appuyant sur B).
static func predict(sim, i: int, btn: int) -> Dictionary:
	var f: Dictionary = sim.state.fighters[i]
	var o: Dictionary = sim.state.fighters[1 - i]
	var cfg: Dictionary = sim.cfg
	var tech_id: String = sim.choose_tech(i, btn)
	var tech: Dictionary = sim.techs[tech_id]
	var combo: bool = f.combo_t > 0 and tech_id == f.combo_next
	var score: int = sim.attack_score(i, tech_id, false, combo)
	var outcome = "expose"
	if score >= cfg.score_ippon + f.mods.ippon_extra:
		outcome = "ippon"
	elif score >= cfg.score_waza:
		outcome = "waza"
	elif score >= cfg.score_stuffed:
		outcome = "stoppe"
	var risk: bool = tech.counter != "" and o.set.counters.has(tech.counter) and sim.dir_value(1 - i, tech.dir) < cfg.counter_threshold
	return {"tech": tech_id, "name": tech.name, "score": score, "outcome": outcome, "combo": combo, "counter_risk": risk}


static func outcome_label(outcome: String) -> String:
	return {"ippon": "IPPON", "waza": "WAZA-ARI", "stoppe": "STOPPÉ", "expose": "EXPOSÉ"}.get(outcome, "")


static func outcome_color(outcome: String) -> Color:
	return {"ippon": Style.GOLD, "waza": Style.GOOD, "stoppe": Style.MUTED, "expose": Style.DANGER}.get(outcome, Style.MUTED)


## Chance « lisible » (0..1) : où se situe le score entre l'exposition et l'ippon.
static func ratio(sim, score: int) -> float:
	var lo = 0.0
	var hi = float(sim.cfg.score_ippon)
	return clampf((float(score) - lo) / (hi - lo), 0.0, 1.0)
