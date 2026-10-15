#!/usr/bin/env python3
"""Choisir la fenêtre d'une technique, en lisant le suivi mis en cache.

    python3 tools/mocap/calibrer.py uchi_mata            # tableau des images utiles
    python3 tools/mocap/calibrer.py uchi_mata --chutes   # toutes les projections repérées

Pour chaque image autour d'une chute : l'écart entre les deux bassins **converti en
unités du jeu** (c'est le `d0` que `throw_anims.gd` utilise pour étirer la chorégraphie),
et l'état de chacun (debout / en train de tomber / au sol).

Un bon départ, c'est une image où les deux sont **debout** et l'écart vaut **45 à 60
unités** : c'est la distance de kumikata du jeu. En dessous de 30, l'animation s'ouvre au
milieu de la projection et le jeu l'étire démesurément.

S'appuie sur le cache écrit par auto_annot.py (rushes/.../.pistes/) : aucune détection
n'est relancée, chaque essai est instantané.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import auto_annot as A  # noqa: E402


def etat(sc):
    if sc >= 0.48:
        return "au sol"
    if sc >= 0.22:
        return "tombe "
    return "debout"


def table(tech, autour=3.2):
    video = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..",
                         "rushes", "efficientjudo", tech + ".mp4")
    suite, fps = A.prepare(video)
    sol, taille = A.sol_et_taille(suite)
    img, qui, _, _ = A.chute(suite, fps)
    if img is None:
        print("aucune chute repérée")
        return
    ech = 47.0 / taille
    print(f"{tech} — chute à {img / fps:.2f} s, uke = emplacement {qui}, "
          f"sol y={sol:.0f}, bassin debout {taille:.0f} px")
    print(f"{'temps':>7s} {'écart':>6s}  {'tori':6s} {'uke':6s}")
    debut = max(0, img - int(autour * fps))
    for i in range(debut, min(len(suite), img + int(0.6 * fps))):
        s = suite[i]
        if not s:
            continue
        sc = [A.score_chute(s[k], sol, taille) for k in (0, 1)]
        d = abs(s[0]["P"][0] - s[1]["P"][0]) * ech
        marque = "  ← chute" if i == img else ""
        print(f"{i / fps:7.2f} {d:6.0f}  {etat(sc[1 - qui]):6s} {etat(sc[qui]):6s}{marque}")


def chutes(tech):
    video = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..",
                         "rushes", "efficientjudo", tech + ".mp4")
    suite, fps = A.prepare(video)
    sol, taille = A.sol_et_taille(suite)
    ech = 47.0 / taille
    n = len(suite)
    for k in (0, 1):
        debout, creux = True, 1.0
        for i in range(n):
            if not suite[i]:
                continue
            v = A.score_chute(suite[i][k], sol, taille)
            if debout:
                if v < 0.28:
                    creux = v
                if v >= 0.48 and creux <= 0.28:
                    # on remonte à la dernière garde franche
                    a = A.depart(suite, i, fps, sol, taille)
                    d = abs(suite[a][0]["P"][0] - suite[a][1]["P"][0]) * ech
                    print(f"  chute à {i / fps:6.2f} s (emplacement {k}) : "
                          f"départ possible {a / fps:.2f} s, écart {d:.0f} unités")
                    debout = False
            elif v < 0.25:
                debout, creux = True, v


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if not args:
        sys.exit(__doc__)
    if "--chutes" in sys.argv:
        chutes(args[0])
    else:
        table(args[0])
