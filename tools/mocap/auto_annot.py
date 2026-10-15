#!/usr/bin/env python3
"""Rotoscopie automatique : vidéo de démonstration → annotation 2D de tori et d'uke.

    python3 tools/mocap/auto_annot.py rushes/efficientjudo/uchi_mata.mp4
    python3 tools/mocap/auto_annot.py rushes/efficientjudo/*.mp4 --jobs 3
    python3 tools/mocap/auto_annot.py rushes/.../o_soto_gari.mp4 --debut 24.6 --uke 0

Remplace l'annotation à la main (voir l'uchi-mata d'origine, 13 images pointées une par
une) : un détecteur de pose repère les articulations des deux judokas image par image, et
on écrit le même format, que `retarget.py` reporte ensuite sur le squelette du jeu.

Quatre points rendent l'automatisation possible sur ces vidéos :

- **un détecteur en deux temps.** MediaPipe fusionne les deux silhouettes dès qu'elles se
  saisissent : sur une démo d'uchi-mata, il ne voyait deux judokas que sur 63 images sur
  483. YOLO-pose détecte d'abord chaque personne, puis sa pose dans sa boîte — deux corps
  qui se tiennent restent deux corps.
- **le suivi d'identité** (ByteTrack, intégré) : sans lui, les deux judokas s'échangent
  dès qu'ils se croisent.
- **qui est uke se lit dans la chute.** Les deux partenaires alternent les rôles au fil de
  la démonstration : tori n'est pas toujours celui en judogi blanc. On repère donc la
  projection par la chute — buste à l'horizontale et bassin au sol — et celui qui tombe
  est uke, l'autre est tori.
- **le côté caméra** (`n` dans l'annotation, pour *near*) est pris sur la confiance des
  points : un membre masqué par le corps est moins sûr que celui qui est devant.

Les démos durent 30 à 45 secondes mais ne contiennent que deux secondes de projection
utiles, répétées plusieurs fois ; on garde la chute la plus franche.
"""
import json
import math
import os
import subprocess
import sys

import numpy as np

LARGEUR, HAUTEUR = 640, 360     # repère de l'annotation, comme la version faite à la main
FPS = 12                        # cadence d'échantillonnage (celle de l'annotation d'origine)
MODELE = "yolo11x-pose.pt"      # le plus précis ; yolo11l-pose.pt si la mémoire manque

# COCO : indices des 17 points du détecteur
NEZ = 0
OREILLE_G, OREILLE_D = 3, 4
EPAULE_G, EPAULE_D = 5, 6
POIGNET_G, POIGNET_D = 9, 10
HANCHE_G, HANCHE_D = 11, 12
GENOU_G, GENOU_D = 13, 14
CHEVILLE_G, CHEVILLE_D = 15, 16

POINTS = ("H", "N", "P", "Kn", "An", "Kf", "Af", "Wn", "Wf")


def fps_source(video):
    out = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0",
                          "-show_entries", "stream=r_frame_rate", "-of", "csv=p=0", video],
                         capture_output=True, text=True).stdout.strip()
    a, b = (out.split("/") + ["1"])[:2]
    return float(a) / float(b or 1)


def milieu(k, a, b):
    return ((k[a][0] + k[b][0]) * 0.5, (k[a][1] + k[b][1]) * 0.5)


def cote(conf, gauche, droite):
    """(près, loin) : le membre le plus sûr est celui qui n'est pas masqué par le corps."""
    return (gauche, droite) if conf[gauche] >= conf[droite] else (droite, gauche)


def personnage(k, conf):
    """Points d'un judoka au format de l'annotation, depuis les 17 points COCO."""
    gn, gf = cote(conf, GENOU_G, GENOU_D)
    an, af = cote(conf, CHEVILLE_G, CHEVILLE_D)
    pn, pf = cote(conf, POIGNET_G, POIGNET_D)
    tete = milieu(k, OREILLE_G, OREILLE_D)
    cou = milieu(k, EPAULE_G, EPAULE_D)
    bassin = milieu(k, HANCHE_G, HANCHE_D)
    ent = lambda p: [int(round(p[0])), int(round(p[1]))]
    return {
        "face": 1 if k[NEZ][0] > cou[0] else -1,   # le nez est devant la ligne des épaules
        "H": ent(tete), "N": ent(cou), "P": ent(bassin),
        "Kn": ent(k[gn]), "An": ent(k[an]),
        "Kf": ent(k[gf]), "Af": ent(k[af]),
        "Wn": ent(k[pn]), "Wf": ent(k[pf]),
    }


def dist(a, b):
    return math.hypot(a[0] - b[0], a[1] - b[1])


def suivre(video, fps=FPS):
    """Les deux judokas par image échantillonnée, et la cadence réellement obtenue.

    On échantillonne par saut d'images (`vid_stride`) : sur une source à 25 i/s, un saut
    de 2 donne 12,5 i/s et non 12. Un rien, mais cumulé sur quarante secondes ça décale
    d'une bonne seconde — assez pour que l'aperçu ne montre plus la même action que
    l'annotation. La cadence réelle est donc renvoyée et c'est elle qui fait foi.

    **On garde les images où un seul judoka est vu.** C'est le point décisif : pendant la
    projection les deux corps s'emmêlent et le détecteur n'en voit souvent plus qu'un. En
    exigeant les deux, on perdait exactement la seconde qui nous intéresse — sur une démo
    d'o-soto-gari, plus rien entre 23 et 27 secondes, c'est-à-dire toute la projection.
    Chaque judoka occupe donc un emplacement, suivi par continuité du bassin ; ce qui
    manque est comblé plus tard par interpolation.
    """
    from ultralytics import YOLO
    import torch
    src = fps_source(video)
    pas = max(1, int(round(src / fps)))
    reelle = src / pas
    modele = YOLO(MODELE)
    appareil = "mps" if torch.backends.mps.is_available() else "cpu"
    emplacements = [None, None]      # dernier bassin connu de chaque judoka
    suite = []
    for res in modele.track(source=video, stream=True, vid_stride=pas, persist=True,
                            device=appareil, classes=[0], verbose=False,
                            imgsz=960, conf=0.25, tracker="bytetrack.yaml"):
        gens = []
        if res.keypoints is not None and len(res.boxes) > 0:
            h, w = res.orig_shape
            kp = res.keypoints.xy.cpu().numpy()
            kc = res.keypoints.conf
            kc = kc.cpu().numpy() if kc is not None else np.ones(kp.shape[:2])
            xywh = res.boxes.xywh.cpu().numpy()
            aires = xywh[:, 2] * xywh[:, 3]
            for j in np.argsort(-aires)[:3]:     # on écarte les silhouettes lointaines
                k = [(float(x) * LARGEUR / w, float(y) * HAUTEUR / h) for x, y in kp[j]]
                if max(c for c in kc[j]) < 0.3:
                    continue
                gens.append(personnage(k, kc[j]))
        place = [None, None]
        libres = list(range(len(gens)))
        # chaque emplacement reprend la silhouette la plus proche de sa dernière position
        for e in (0, 1):
            if emplacements[e] is None or not libres:
                continue
            j = min(libres, key=lambda j: dist(gens[j]["P"], emplacements[e]))
            if dist(gens[j]["P"], emplacements[e]) < LARGEUR * 0.22:
                place[e] = gens[j]
                libres.remove(j)
        for e in (0, 1):                          # emplacements encore vides
            if place[e] is None and libres:
                place[e] = gens[libres.pop(0)]
        for e in (0, 1):
            if place[e] is not None:
                emplacements[e] = place[e]["P"]
        suite.append(place if any(p is not None for p in place) else None)
    return suite, reelle


def _combler_pistes(suite):
    """Comble, pour chaque emplacement, les images où il n'a pas été vu."""
    n = len(suite)
    for e in (0, 1):
        connues = [i for i in range(n) if suite[i] and suite[i][e]]
        if not connues:
            continue
        for i in range(n):
            if suite[i] is None:
                suite[i] = [None, None]
            if suite[i][e]:
                continue
            av = max([j for j in connues if j < i], default=None)
            ap = min([j for j in connues if j > i], default=None)
            if av is None or ap is None:
                suite[i][e] = dict(suite[av if av is not None else ap][e])
                continue
            t = (i - av) / (ap - av)
            g = {"face": suite[av][e]["face"]}
            for pt in POINTS:
                x0, y0 = suite[av][e][pt]
                x1, y1 = suite[ap][e][pt]
                g[pt] = [int(round(x0 + (x1 - x0) * t)), int(round(y0 + (y1 - y0) * t))]
            suite[i][e] = g
    return [s if s and s[0] and s[1] else None for s in suite]


def sol_et_taille(suite):
    """Niveau du tatami (px) et hauteur de bassin debout (px), sur toute la séquence."""
    chevilles, hauteurs = [], []
    for s in suite:
        if s:
            for g in s:
                chevilles += [g["An"][1], g["Af"][1]]
    sol = float(np.percentile(chevilles, 92)) if chevilles else HAUTEUR * 0.9
    for s in suite:
        if s:
            for g in s:
                h = sol - g["P"][1]
                if h > 0:
                    hauteurs.append(h)
    return sol, (float(np.percentile(hauteurs, 85)) if hauteurs else 140.0)


def score_chute(g, sol, taille):
    """À quel point ce judoka est en train de tomber : buste à plat et bassin au sol."""
    dx = abs(g["N"][0] - g["P"][0])
    dy = abs(g["N"][1] - g["P"][1])
    plat = dx / max(1.0, dx + dy)                      # 1 = buste horizontal
    bas = 1.0 - min(1.0, max(0.0, (sol - g["P"][1]) / max(1.0, taille)))
    return plat * bas


def hauteur_debout(g, sol):
    """Hauteur du cou au-dessus du sol : sert à repérer les plans rapprochés."""
    return sol - g["N"][1]


def chute(suite, fps=FPS, avant=1.1):
    """Image du **premier contact** de la projection la plus franche, et qui tombe.

    Deux pièges, tous deux rencontrés sur ces vidéos :

    - prendre l'image la plus « tombée » amène sur le plan de fin, où uke est au sol
      depuis longtemps et où plus rien ne bouge ;
    - prendre le maximum du score amène une seconde trop tard, le score continuant de
      monter pendant qu'uke s'écrase.

    On suit donc l'état de chaque judoka — debout, puis au sol — et on retient l'image où
    il bascule. Les plans dont l'échelle s'écarte du reste de la vidéo sont écartés.
    """
    sol, taille = sol_et_taille(suite)
    n = len(suite)
    scores = [[None, None] for _ in range(n)]
    tailles = []
    for i, s in enumerate(suite):
        if not s:
            continue
        for k in (0, 1):
            scores[i][k] = score_chute(s[k], sol, taille)
            tailles.append(hauteur_debout(s[k], sol))
    if not tailles:
        return None, 0, sol, taille
    ref = float(np.median(tailles))
    besoin = int(avant * fps)
    best, img, qui = 0.0, None, 0
    for k in (0, 1):
        debout = True
        creux = 1.0
        for i in range(n):
            sc = scores[i][k]
            if sc is None:
                continue
            if debout:
                creux = min(creux, sc)
                if sc < 0.25:
                    creux = sc
                if sc >= 0.55 and creux <= 0.25:
                    # bascule : on tient le premier contact
                    ech = [hauteur_debout(suite[j][k], sol)
                           for j in range(max(0, i - besoin), i + 1) if suite[j]]
                    bonne_echelle = (ech and abs(float(np.median(ech)) - ref) <= ref * 0.35)
                    if bonne_echelle and (sc - creux) > best:
                        best, img, qui = sc - creux, i, k
                    debout = False
            elif sc < 0.25:
                debout, creux = True, sc
    if img is None:                           # repli : l'image la plus tombée
        for i, s in enumerate(suite):
            if not s:
                continue
            for k in (0, 1):
                if scores[i][k] and scores[i][k] > best:
                    best, img, qui = scores[i][k], i, k
    return img, qui, sol, taille


def annoter(video, tech, fps=FPS, avant=1.1, apres=0.35, debut=None, uke=None):
    """`debut` (secondes) force la fenêtre, `uke` (0 ou 1) force les rôles.

    La détection automatique de la bonne répétition se trompe sur certaines démos — celles
    où les partenaires enchaînent sans se relever, ou filmées de plus près. Plutôt que de
    tordre l'heuristique jusqu'à ce qu'elle couvre tous les cas, on garde la possibilité
    de donner la seconde à la main : c'est un repérage de cinq secondes par vidéo, à
    comparer aux treize images à pointer une par une de la méthode précédente.
    """
    suite, fps = suivre(video, fps)
    suite = _combler_pistes(suite)
    if debut is not None:
        img_chute = min(len(suite) - 1, int((debut + avant) * fps))
        sol, taille = sol_et_taille(suite)
        i_uke = uke if uke is not None else chute(suite, fps, avant)[1]
    else:
        img_chute, i_uke, sol, taille = chute(suite, fps, avant)
        if uke is not None:
            i_uke = uke
    if img_chute is None:
        return None, "aucun judoka détecté"
    a = max(0, img_chute - int(avant * fps))
    b = min(len(suite) - 1, img_chute + int(apres * fps))
    frames = []
    for i in range(a, b + 1):
        s = suite[i]
        if not s:
            continue
        frames.append({"f": i, "p": round((i - a) / max(1, b - a), 3),
                       "tori": dict(s[1 - i_uke]), "uke": dict(s[i_uke])})
    if len(frames) < 8:
        return None, f"seulement {len(frames)} images exploitables autour de la chute"
    trous = (b - a + 1) - sum(1 for i in range(a, b + 1) if suite[i])
    vus = sum(1 for s in suite if s)
    return {
        "_doc": (f"Rotoscopie automatique de {tech} (chaîne Efficient Judo, utilisée avec "
                 f"l'accord de son auteur) : points YOLO-pose, uke reconnu à sa chute, "
                 f"{fps} i/s, coordonnées en pixels de l'image {LARGEUR}×{HAUTEUR}. "
                 f"Généré par tools/mocap/auto_annot.py."),
        "source": os.path.relpath(video),
        "start_s": round(a / fps, 2),
        "fps": round(fps, 4),
        "floor_y": int(round(sol)),
        "hip_height_px": int(round(taille)),
        "tech": tech,
        "frames": frames,
    }, (f"{len(frames)} images ({trous} comblées), chute à {img_chute / fps:.1f} s, "
        f"{vus}/{len(suite)} images suivies")


def _une(args):
    video, tech, racine, debut, uke = args
    try:
        d, info = annoter(video, tech, debut=debut, uke=uke)
    except Exception as e:                     # une vidéo ratée ne doit pas tout arrêter
        return tech, False, f"erreur : {e}"
    if d is None:
        return tech, False, info
    with open(os.path.join(racine, "tools/mocap", f"{tech}_annot.json"), "w") as f:
        json.dump(d, f, ensure_ascii=False, indent=1)
    return tech, True, info


if __name__ == "__main__":
    # les options à valeur (--jobs 3, --debut 12.5) consomment l'argument suivant :
    # sans ça leur valeur était prise pour un fichier vidéo
    opts, args, i = {}, [], 1
    while i < len(sys.argv):
        a = sys.argv[i]
        if a in ("--jobs", "--debut", "--uke"):
            opts[a] = sys.argv[i + 1]
            i += 2
            continue
        if not a.startswith("--"):
            args.append(a)
        i += 1
    if not args:
        sys.exit(__doc__)
    jobs = int(opts.get("--jobs", 1))
    racine = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
    debut = float(opts["--debut"]) if "--debut" in opts else None
    uke = int(opts["--uke"]) if "--uke" in opts else None
    taches = [(v, os.path.splitext(os.path.basename(v))[0], racine, debut, uke)
              for v in args]
    if jobs > 1:
        import multiprocessing as mp
        with mp.get_context("spawn").Pool(jobs) as pool:
            resultats = pool.map(_une, taches)
    else:
        resultats = [_une(t) for t in taches]
    ok = 0
    for tech, bon, info in resultats:
        print(f"{'✓' if bon else '✗'} {tech:24s} {info}")
        ok += bon
    print(f"\n{ok}/{len(resultats)} annotations écrites")
