#!/usr/bin/env python3
"""Récupère les démonstrations de la chaîne Efficient Judo pour la rotoscopie.

    python3 tools/video/fetch_efficientjudo.py --liste        # ce que la chaîne contient
    python3 tools/video/fetch_efficientjudo.py --jeu          # les 13 techniques du jeu
    python3 tools/video/fetch_efficientjudo.py uchi_mata seoi_nage

**Droits** : Hugo a obtenu l'autorisation de l'auteur de la chaîne pour utiliser ces
vidéos comme référence d'animation. Elles vont dans `rushes/` (ignoré par git) : on ne
versionne que les annotations qui en sortent, pas les vidéos.

La chaîne publie une démonstration par technique, de 25 à 45 secondes, filmée **de
profil** sur fond neutre — exactement le point de vue du jeu — et répète la projection
plusieurs fois. C'est la matière idéale pour `tools/mocap/auto_annot.py`.

Les noms ne se recoupent pas d'eux-mêmes avec ceux du jeu : la chaîne écrit « Osoto-gari »
là où le jeu dit `o_soto_gari`, « Kouchi-gari » pour `ko_uchi_gari`. D'où la table ALIAS.
"""
import json
import os
import re
import subprocess
import sys

CHAINE = "https://www.youtube.com/@EfficientJudo/videos"

# technique du jeu → écritures possibles dans les titres de la chaîne
ALIAS = {
    "de_ashi_barai": ["de ashi barai", "deashi barai"],
    "harai_goshi": ["harai goshi"],
    "ippon_seoi_nage": ["ippon seoi nage"],
    "ko_uchi_gari": ["kouchi gari", "ko uchi gari"],
    "o_goshi": ["o goshi"],
    "o_soto_gari": ["osoto gari"],
    "o_uchi_gari": ["ouchi gari"],
    "sasae_tsurikomi_ashi": ["sasae tsurikomi ashi", "sasae tsuri komi ashi"],
    "seoi_nage": ["seoi nage"],
    "sumi_gaeshi": ["sumi gaeshi"],
    "tai_otoshi": ["tai otoshi"],
    "tomoe_nage": ["tomoe nage"],
    "uchi_mata": ["uchi mata"],
}


def norme(t):
    return re.sub(r"\s+", " ", t.lower().replace("-", " ").replace("_", " ")).strip()


def catalogue():
    """[(durée, titre, identifiant)] de toute la chaîne."""
    out = subprocess.run(["yt-dlp", "--flat-playlist", "--print",
                          "%(duration)s|%(title)s|%(id)s", CHAINE],
                         capture_output=True, text=True).stdout
    lignes = []
    for l in out.splitlines():
        p = l.strip().split("|")
        if len(p) == 3 and p[0].isdigit():
            lignes.append((int(p[0]), p[1], p[2]))
    return lignes


def canonique(lignes, tech):
    """La démonstration la plus « pure » d'une technique : titre le plus court, sans
    variante ni enchaînement (« Duck Under Tai-otoshi », « ... - Combination demo »)."""
    al = ALIAS[tech]
    cand = [l for l in lignes
            if any(a in norme(l[1]) for a in al) and "combination" not in norme(l[1])]
    exact = [l for l in cand if norme(l[1]).replace(" demo", "").strip() in al]
    pool = sorted(exact or cand, key=lambda l: len(l[1]))
    return pool[0] if pool else None


def telecharger(ident, dest):
    if os.path.exists(dest):
        return False
    subprocess.run(["yt-dlp", "-q", "--no-warnings", "-f",
                    "bv*[height<=1080][ext=mp4]+ba[ext=m4a]/b[height<=1080]",
                    "-o", dest, f"https://www.youtube.com/watch?v={ident}"], check=True)
    return True


if __name__ == "__main__":
    racine = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")
    dossier = os.path.join(racine, "rushes", "efficientjudo")
    lignes = catalogue()
    if "--liste" in sys.argv:
        solo = [l for l in lignes if "combination" not in norme(l[1])]
        print(f"{len(lignes)} vidéos ({len(lignes) - len(solo)} enchaînements)")
        for t in ALIAS:
            n = len([l for l in solo if any(a in norme(l[1]) for a in ALIAS[t])])
            print(f"  {t:24s} {n:3d} démonstration(s)")
        hors = [l for l in solo
                if not any(a in norme(l[1]) for al in ALIAS.values() for a in al)]
        print(f"\n{len(hors)} techniques absentes du jeu, par exemple :")
        for l in hors[:15]:
            print("   ", l[1].replace(" - Demo", ""))
        sys.exit(0)

    voulues = [a for a in sys.argv[1:] if not a.startswith("--")]
    if "--jeu" in sys.argv or not voulues:
        voulues = list(ALIAS)
    os.makedirs(dossier, exist_ok=True)
    for tech in voulues:
        if tech not in ALIAS:
            print(f"✗ {tech:24s} technique inconnue")
            continue
        c = canonique(lignes, tech)
        if c is None:
            print(f"✗ {tech:24s} aucune démonstration trouvée")
            continue
        dest = os.path.join(dossier, f"{tech}.mp4")
        neuf = telecharger(c[2], dest)
        print(f"{'↓' if neuf else '=' } {tech:24s} {c[0]:3d}s  {c[1]}")
