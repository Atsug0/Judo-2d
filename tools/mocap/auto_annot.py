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
    """Points d'un judoka au format de l'annotation, depuis les 17 points COCO.

    On garde aussi `_profil` : l'écartement horizontal des épaules et des hanches, rapporté
    à la hauteur du buste. En vue de profil — le seul plan que le jeu sait reproduire — les
    deux épaules se superposent et cet écart est petit. De face ou de trois quarts il
    double, et le report sur le squelette 2D du jeu donne n'importe quoi.
    """
    gn, gf = cote(conf, GENOU_G, GENOU_D)
    an, af = cote(conf, CHEVILLE_G, CHEVILLE_D)
    pn, pf = cote(conf, POIGNET_G, POIGNET_D)
    tete = milieu(k, OREILLE_G, OREILLE_D)
    cou = milieu(k, EPAULE_G, EPAULE_D)
    bassin = milieu(k, HANCHE_G, HANCHE_D)
    ent = lambda p: [int(round(p[0])), int(round(p[1]))]
    buste = max(1.0, abs(cou[1] - bassin[1]))
    largeur = (abs(k[EPAULE_G][0] - k[EPAULE_D][0]) +
               abs(k[HANCHE_G][0] - k[HANCHE_D][0])) * 0.5
    return {
        "_profil": round(largeur / buste, 3),
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


def stabiliser(suite):
    """Empêche les membres « près » et « loin » de s'échanger d'une image à l'autre.

    Le côté caméra était choisi image par image sur la confiance des points. Résultat :
    sur une projection de quinze images, les jambes s'échangeaient trois à cinq fois —
    de la bouillie à l'écran. On impose la continuité : à chaque image on garde
    l'affectation qui déplace le moins les membres par rapport à l'image précédente.
    """
    paires = (("Kn", "Kf"), ("An", "Af"), ("Wn", "Wf"))
    for e in (0, 1):
        prec = None
        for s in suite:
            if not s or not s[e]:
                continue
            g = s[e]
            if prec is not None:
                direct = sum(dist(g[a], prec[a]) + dist(g[b], prec[b]) for a, b in paires)
                croise = sum(dist(g[b], prec[a]) + dist(g[a], prec[b]) for a, b in paires)
                if croise < direct:
                    for a, b in paires:
                        g[a], g[b] = g[b], g[a]
            prec = g
    return suite


def _med(xs):
    xs = sorted(xs)
    return xs[len(xs) // 2] if xs else 0.0


def rigidifier(suite, sol, taille):
    """Impose à chaque judoka des **longueurs de membres constantes**.

    C'est la correction décisive. Les détecteurs de pose sont entraînés sur des gens
    debout : sur un judoka en l'air, à l'envers et enchevêtré avec son partenaire, ils
    placent les articulations n'importe où. D'une image à l'autre une cuisse passe du
    simple au double et le judoka devient un pantin disloqué — ce qu'on voyait à l'écran.

    On mesure donc les longueurs sur les images où le judoka est **debout** (là où la
    détection est fiable), puis on reconstruit chaque image en gardant les **directions**
    détectées et en réimposant ces longueurs. L'orientation vient de la vidéo, les
    proportions du judoka.
    """
    membres = (("N", "P"), ("H", "N"), ("Kn", "P"), ("An", "Kn"),
               ("Kf", "P"), ("Af", "Kf"), ("Wn", "N"), ("Wf", "N"))
    for e in (0, 1):
        debout = [s[e] for s in suite
                  if s and s[e] and score_chute(s[e], sol, taille) < 0.2]
        if len(debout) < 5:
            continue
        L = {a: _med([dist(g[a], g[b]) for g in debout]) for a, b in membres}
        for s in suite:
            if not s or not s[e]:
                continue
            g = s[e]
            for a, b in membres:
                vx, vy = g[a][0] - g[b][0], g[a][1] - g[b][1]
                n = math.hypot(vx, vy)
                if n < 1e-6 or L[a] <= 0:
                    continue
                g[a] = [g[b][0] + vx / n * L[a], g[b][1] + vy / n * L[a]]
    return suite


def lisser(suite, fen=2):
    """Lissage temporel des points : la détection tremble, le jeu pas."""
    pts = list(POINTS)
    n = len(suite)
    copie = [[dict(g) if g else None for g in (s or [None, None])] for s in suite]
    for e in (0, 1):
        for i in range(n):
            if not suite[i] or not suite[i][e]:
                continue
            for k in pts:
                xs, ys, poids = 0.0, 0.0, 0.0
                for j in range(max(0, i - fen), min(n, i + fen + 1)):
                    if not copie[j] or not copie[j][e]:
                        continue
                    w = 1.0 / (1 + abs(i - j))
                    xs += copie[j][e][k][0] * w
                    ys += copie[j][e][k][1] * w
                    poids += w
                if poids > 0:
                    suite[i][e][k] = [xs / poids, ys / poids]
    return suite


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


def chutes(suite, fps=FPS):
    """Toutes les projections repérées : (image du premier contact, qui tombe).

    On suit l'état de chaque judoka — debout, puis au sol — et on retient l'image où il
    bascule. Prendre l'image la plus « tombée » amènerait sur le plan de fin, où uke est
    au sol depuis longtemps et où plus rien ne bouge ; prendre le maximum du score
    arriverait une seconde trop tard, le score montant encore pendant qu'il s'écrase.
    """
    sol, taille = sol_et_taille(suite)
    n = len(suite)
    out = []
    for k in (0, 1):
        debout, creux = True, 1.0
        for i in range(n):
            if not suite[i]:
                continue
            v = score_chute(suite[i][k], sol, taille)
            if debout:
                if v < 0.25:
                    creux = v
                if v >= 0.48 and creux <= 0.28:
                    out.append((i, k))
                    debout = False
            elif v < 0.25:
                debout, creux = True, v
    return out, sol, taille


def profil(suite, a, b):
    """À quel point le passage [a, b] est filmé **de profil** (0 = de face, 1 = de profil).

    Le squelette du jeu est une vue de côté : un côté près de la caméra, un côté loin, et
    rien d'autre. Reporter dessus un plan de trois quarts ou de face ne peut rien donner
    de bon. On lit l'écartement horizontal des épaules et des hanches rapporté à la
    hauteur du buste : superposées de profil, écartées de face.
    """
    vals = []
    for i in range(a, b + 1):
        if i >= len(suite) or not suite[i]:
            continue
        for g in suite[i]:
            if not g or "_profil" not in g:
                continue
            # `_profil` a été mesuré en divisant par la **hauteur** du buste, qui tend
            # vers zéro quand le judoka passe à l'horizontale : la valeur explosait.
            # On revient à l'écartement brut, qu'on rapporte à la **longueur** du buste.
            dy = abs(g["N"][1] - g["P"][1])
            L = dist(g["N"], g["P"])
            if L < 1e-6:
                continue
            vals.append(float(g["_profil"]) * dy / L)
    if not vals:
        return 0.5
    vals.sort()
    moy = vals[len(vals) // 2]           # médiane : insensible aux images ratées
    # ≈0,10 vu de profil, ≈0,40 vu de face sur ces vidéos
    return max(0.0, min(1.0, (0.40 - moy) / 0.30))


def chute(suite, fps=FPS, recul=2.6):
    """La projection à retenir : celle dont **la garde qui la précède est la meilleure**.

    Choisir d'abord la chute puis chercher une garde avant donnait des départs à écart
    nul — l'animation s'ouvrait avec uke déjà chargé sur la hanche, et `throw_anims.gd`,
    qui étire les abscisses par d / d0, envoyait tout hors de l'écran. On classe donc les
    projections par la qualité de leur kumikata.
    """
    cand, sol, taille = chutes(suite, fps)
    if not cand:
        return None, 0, sol, taille
    best = None
    for i, k in cand:
        a = depart(suite, i, fps, sol, taille, recul)
        ecart = abs(suite[a][0]["P"][0] - suite[a][1]["P"][0]) if suite[a] else 0.0
        # l'échelle du plan doit rester celle du reste de la vidéo
        ech = [hauteur_debout(suite[j][k], sol)
               for j in range(a, i + 1) if suite[j]]
        ref = float(np.median([hauteur_debout(g, sol) for s in suite if s for g in s]))
        if ech and abs(float(np.median(ech)) - ref) > ref * 0.35:
            continue
        # une garde large filmée de face vaut moins qu'une garde correcte vue de profil
        note = ecart * (0.25 + 0.75 * profil(suite, a, i))
        if best is None or note > best[0]:
            best = (note, i, k)
    if best is None:
        i, k = cand[0]
        return i, k, sol, taille
    return best[1], best[2], sol, taille


def depart(suite, img_chute, fps, sol, taille, recul_max=2.6):
    """Image où commencer : la dernière, avant la chute, où les deux sont debout et
    **séparés d'une vraie distance de kumikata**.

    Partir d'un temps fixe avant la chute donnait n'importe quoi : sur le harai-goshi, la
    fenêtre s'ouvrait avec uke déjà chargé sur la hanche (distance de départ nulle), sur
    l'o-uchi-gari avec les deux judokas croisés (distance négative). Le jeu part d'un
    kumikata établi : l'animation doit s'ouvrir là, pas au milieu de la projection.
    """
    # On ne vise pas un seuil fixe : l'écart de kumikata dépend de la technique et du
    # cadrage (36 à 45 unités de jeu sur ces vidéos, ce qui correspond au min_gap de la
    # simulation). On prend donc la **meilleure garde disponible** avant la chute, et
    # parmi les images équivalentes la plus tardive — au plus près de l'attaque.
    # il faut de quoi raconter l'entrée : au moins neuf dixièmes de seconde avant la chute
    fin = max(0, img_chute - int(0.9 * fps))
    debut = max(0, img_chute - int(recul_max * fps))
    debouts = []
    for i in range(debut, fin + 1):
        s = suite[i]
        if not s:
            continue
        if max(score_chute(s[0], sol, taille), score_chute(s[1], sol, taille)) > 0.22:
            continue
        debouts.append((i, abs(s[0]["P"][0] - s[1]["P"][0])))
    if not debouts:
        return debut
    meilleur = max(e for _, e in debouts)
    for i, e in reversed(debouts):
        if e >= meilleur * 0.9:
            return i
    return debouts[-1][0]


def miroir(g):
    """Retourne un judoka horizontalement."""
    out = {"face": -g["face"]} if "face" in g else {}
    if "_profil" in g:
        out["_profil"] = g["_profil"]
    for k, v in g.items():
        if k in POINTS:
            out[k] = [LARGEUR - v[0], v[1]]
        elif k not in ("face",):
            out[k] = v
    return out


def coucher(g, sol, taille, rot_prec):
    """Encode un judoka au sol : pose couchée du jeu, pas un squelette debout tordu.

    C'est ce qui manquait le plus aux chutes. `retarget.py` sait poser un judoka couché
    (pose LYING) à partir de son orientation et de la hauteur de son bassin ; sans ce
    marquage, il tentait de plier un squelette debout dans une position impossible.
    """
    dx = g["N"][0] - g["P"][0]
    dy = g["N"][1] - g["P"][1]
    rot = math.atan2(dx, -dy)
    if rot_prec is not None:
        while rot - rot_prec > math.pi:
            rot -= 2 * math.pi
        while rot - rot_prec < -math.pi:
            rot += 2 * math.pi
    y = (g["P"][1] - sol) * (47.0 / max(1.0, taille))
    return {"lying": True, "rot": round(rot, 2), "x_px": int(g["P"][0]),
            "y_units": round(max(-22.0, min(-4.0, y)), 1)}


def pistes(video, fps=FPS, cache=True):
    """Suivi des deux judokas, gardé en cache à côté de la vidéo.

    La détection coûte une minute et demie par vidéo ; le réglage de la fenêtre, lui, se
    reprend plusieurs fois par technique. Sans ce cache, chaque essai relançait tout.
    """
    dos = os.path.join(os.path.dirname(video), ".pistes")
    f = os.path.join(dos, os.path.splitext(os.path.basename(video))[0] + ".json")
    if cache and os.path.exists(f):
        d = json.load(open(f))
        return d["suite"], d["fps"]
    suite, reelle = suivre(video, fps)
    suite = _combler_pistes(suite)
    if cache:
        os.makedirs(dos, exist_ok=True)
        json.dump({"suite": suite, "fps": reelle}, open(f, "w"))
    return suite, reelle


def prepare(video, fps=FPS):
    """Suivi + stabilisation + lissage + longueurs rigides : l'état sur lequel tout le
    reste raisonne. `calibrer.py` passe par ici aussi, sinon ses lectures ne
    correspondent pas à ce que l'annotation produit."""
    suite, fps = pistes(video, fps)
    suite = stabiliser(suite)
    sol0, taille0 = sol_et_taille(suite)
    return rigidifier(lisser(suite), sol0, taille0), fps


def annoter(video, tech, fps=FPS, apres=0.35, debut=None, uke=None, recul=4.5,
            attaque=1.35):
    """`debut` (secondes) force la fenêtre, `uke` (0 ou 1) force les rôles."""
    suite, fps = prepare(video, fps)
    sol, taille = sol_et_taille(suite)
    if debut is not None:
        a = max(0, int(debut * fps))
        # la première projection qui suit le départ demandé, prise dans la même liste que
        # le mode automatique : un simple seuil sur le score attrapait une chute bien plus
        # tardive, et l'animation mélangeait deux répétitions
        cand = [i for i, _ in chutes(suite, fps)[0] if i > a]
        img_chute = cand[0] if cand else min(len(suite) - 1, a + int(2.0 * fps))
        i_uke = uke if uke is not None else chute(suite, fps, recul)[1]
    else:
        img_chute, i_uke, sol, taille = chute(suite, fps, recul)
        if img_chute is None:
            return None, "aucun judoka détecté"
        if uke is not None:
            i_uke = uke
        a = depart(suite, img_chute, fps, sol, taille, recul)
    b = min(len(suite) - 1, img_chute + int(apres * fps))
    if b - a < 8:
        return None, f"fenêtre trop courte ({b - a} images)"
    # La première image **doit** être un vrai kumikata : c'est elle qui fixe d0, et
    # `throw_anims.gd` étire toute la chorégraphie par d / d0. Mais une garde parfois
    # située trois secondes avant la chute donnerait une fenêtre que le jeu comprimerait
    # en sept dixièmes de seconde — illisible. On garde donc la garde comme première
    # image, puis on saute directement à l'entrée : c'est d'ailleurs ce que fait le jeu,
    # qui déclenche la projection depuis un kumikata établi.
    # L'entrée ne dure pas pareil d'une technique à l'autre : un de-ashi-barai part en
    # deux dixièmes de seconde, un harai-goshi en une bonne demi-seconde. On la cale donc
    # sur le moment où **uke quitte sa garde** — son bassin descend sous la hauteur de
    # repos — plutôt que sur un délai fixe, sans quoi la moitié de l'animation est du
    # temps mort avec uke déjà au sol.
    debout_min = taille * 0.78
    quitte = img_chute
    for i in range(img_chute, max(a, img_chute - int(attaque * fps)) - 1, -1):
        if suite[i] and (sol - suite[i][i_uke]["P"][1]) >= debout_min:
            quitte = i
            break
    entree = max(a, quitte - int(0.2 * fps))
    if entree > a + 1:
        # quelques images entre la garde et l'entrée, sinon le passage de l'une à l'autre
        # est un saut sec : le jeu interpole en ligne droite entre deux clés
        pont = [a + round((entree - a) * k / 4.0) for k in range(4)]
        retenues = sorted(set(pont)) + list(range(entree, b + 1))
    else:
        retenues = list(range(a, b + 1))
    # `throw_anims.gd` étire les abscisses par d / d0, d0 étant l'écart de départ entre
    # tori et uke. Il doit donc être positif et valoir un vrai kumikata : si uke est à
    # gauche de tori dans la vidéo, on retourne toute la séquence. Un d0 nul ou négatif
    # donnait un facteur d'étirement de 55 et envoyait les judokas hors de l'écran.
    i_tori = 1 - i_uke
    if suite[a][i_uke]["P"][0] < suite[a][i_tori]["P"][0]:
        for i in range(len(suite)):
            if suite[i]:
                suite[i] = [miroir(suite[i][0]), miroir(suite[i][1])]
    # un judoka tombé reste au sol jusqu'à la fin de la fenêtre
    au_sol = [None, None]
    rot_prec = [None, None]
    frames = []
    for n_i, i in enumerate(retenues):
        s = suite[i]
        if not s:
            continue
        acteurs = {}
        for k in (0, 1):
            # seul uke est « couché » : dans un sacrifice (tomoe-nage, sumi-gaeshi) tori
            # descend au sol volontairement, et c'est une posture de technique, pas une
            # chute — lui imposer la pose couchée la ferait disparaître
            if k == i_uke and au_sol[k] is None and score_chute(s[k], sol, taille) >= 0.48:
                au_sol[k] = i
            if au_sol[k] is not None:
                g = coucher(s[k], sol, taille, rot_prec[k])
                rot_prec[k] = g["rot"]
            else:
                g = dict(s[k])
            acteurs["uke" if k == i_uke else "tori"] = g
        p = n_i / max(1, len(retenues) - 1)
        frames.append({"f": i, "p": round(p, 3), **acteurs})
    if len(frames) < 8:
        return None, f"seulement {len(frames)} images exploitables"
    ecart = (suite[a][i_uke]["P"][0] - suite[a][i_tori]["P"][0]) * 47.0 / max(1.0, taille)
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
    }, (f"{len(frames)} images, {a / fps:.1f}→{b / fps:.1f} s, "
        f"d0 = {ecart:.0f} unités, profil {profil(suite, a, b):.2f}")


def _une(args):
    video, tech, racine, debut, uke, recul = args
    try:
        d, info = annoter(video, tech, debut=debut, uke=uke, recul=recul)
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
        if a in ("--jobs", "--debut", "--uke", "--recul"):
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
    recul = float(opts.get("--recul", 4.5))
    taches = [(v, os.path.splitext(os.path.basename(v))[0], racine, debut, uke, recul)
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
