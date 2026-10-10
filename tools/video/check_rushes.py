#!/usr/bin/env python3
"""Vérifie les rushes filmés au dojo par rapport à la liste de tournage.

Usage :
    python3 tools/video/check_rushes.py [dossier_rushes]

Convention de nommage : <id>_<cote>_prise<N>.<mp4|mov|mkv>
    ex. tech_seoi_nage_droitier_prise3.mp4, salut_face_prise1.mov

Écrit un rapport lisible dans <dossier_rushes>/RAPPORT.md et l'affiche.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
VIDEO_EXT = {".mp4", ".mov", ".mkv", ".avi", ".m4v"}
NAME_RE = re.compile(r"^(?P<id>.+)_(?P<side>droitier|gaucher|face)_prise(?P<take>\d+)$", re.IGNORECASE)


def main() -> int:
    rush_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "rushes"
    shotlist = json.loads((ROOT / "data" / "shotlist.json").read_text(encoding="utf-8"))
    shots = {s["id"]: s for s in shotlist["shots"]}
    if not rush_dir.exists():
        rush_dir.mkdir(parents=True)
        print(f"Dossier créé : {rush_dir} (vide). Dépose tes vidéos dedans.")
    found: dict[tuple[str, str], list[int]] = {}
    unknown: list[str] = []
    for f in sorted(rush_dir.iterdir()):
        if f.suffix.lower() not in VIDEO_EXT:
            continue
        m = NAME_RE.match(f.stem)
        if not m or m["id"] not in shots:
            unknown.append(f.name)
            continue
        found.setdefault((m["id"], m["side"].lower()), []).append(int(m["take"]))

    lines = ["# Rapport des rushes", ""]
    total_need = total_have = 0
    missing_lines = []
    for sid, s in shots.items():
        for side in s["sides"]:
            need = s["takes"]
            have = len(found.get((sid, side), []))
            total_need += need
            total_have += min(have, need)
            status = "OK" if have >= need else ("PARTIEL" if have else "MANQUANT")
            if status != "OK":
                missing_lines.append(f"- [{status}] {sid} ({side}) : {have}/{need} prises — {s['label']}")
    pct = 100 * total_have // max(1, total_need)
    lines.append(f"Progression : {total_have}/{total_need} prises ({pct} %)")
    lines.append("")
    if missing_lines:
        lines.append("## À filmer")
        lines.extend(missing_lines)
        lines.append("")
    if unknown:
        lines.append("## Fichiers non reconnus (vérifie le nom)")
        lines.extend(f"- {u}" for u in unknown)
        lines.append("")
        lines.append("Format attendu : <id>_<droitier|gaucher|face>_prise<N>.mp4")
    report = "\n".join(lines) + "\n"
    (rush_dir / "RAPPORT.md").write_text(report, encoding="utf-8")
    print(report)
    return 0


if __name__ == "__main__":
    sys.exit(main())
