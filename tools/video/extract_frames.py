#!/usr/bin/env python3
"""Extrait les images d'un rush (ou d'un lot de rushes) pour l'animation.

Usage simple :
    python3 tools/video/extract_frames.py rushes/tech_seoi_nage_droitier_prise3.mp4 \\
        --start 1.20 --end 2.90 --fps 12

Lot (fichier de découpes JSON) :
    python3 tools/video/extract_frames.py --cuts rushes/decoupes.json

    decoupes.json = [
      {"video": "tech_seoi_nage_droitier_prise3.mp4", "start": 1.2, "end": 2.9, "anim": "throw/seoi_nage"},
      ...
    ]

Sortie : animations/_frames/<anim ou nom du rush>/
    0001.png, 0002.png, ...      images à la cadence du jeu (12 i/s par défaut)
    planche.png                  planche-contact pour relire le mouvement d'un coup d'œil
    info.json                    source, découpe, cadence, nombre d'images

Options utiles :
    --mirror        retourne l'image (fabrique un côté gaucher à partir d'un droitier)
    --crop W:H:X:Y  recadre (pixels de la vidéo source)
    --width 960     largeur de sortie (hauteur proportionnelle)

Nécessite ffmpeg et ffprobe dans le PATH.
"""
import argparse
import json
import math
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUT = ROOT / "animations" / "_frames"


def probe(video: Path) -> dict:
    out = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                          "stream=width,height,r_frame_rate:format=duration", "-of", "json", str(video)],
                         capture_output=True, text=True, check=True).stdout
    data = json.loads(out)
    st = data["streams"][0]
    num, den = st["r_frame_rate"].split("/")
    return {"width": int(st["width"]), "height": int(st["height"]),
            "fps": float(num) / float(den), "duration": float(data["format"]["duration"])}


def extract(video: Path, out_dir: Path, start: float, end: float | None, fps: int, width: int,
            mirror: bool, crop: str | None, contact: bool = True) -> dict:
    if not video.exists():
        raise SystemExit(f"Vidéo introuvable : {video}")
    info = probe(video)
    if end is None or end > info["duration"]:
        end = info["duration"]
    if end <= start:
        raise SystemExit(f"Découpe vide ({start} → {end}) pour {video.name}")
    if out_dir.exists():
        shutil.rmtree(out_dir)
    out_dir.mkdir(parents=True)
    filters = []
    if crop:
        filters.append(f"crop={crop}")
    filters.append(f"fps={fps}")
    filters.append(f"scale={width}:-2:flags=lanczos")
    if mirror:
        filters.append("hflip")
    cmd = ["ffmpeg", "-v", "error", "-y", "-ss", f"{start:.3f}", "-to", f"{end:.3f}", "-i", str(video),
           "-vf", ",".join(filters), str(out_dir / "%04d.png")]
    subprocess.run(cmd, check=True)
    frames = sorted(out_dir.glob("[0-9][0-9][0-9][0-9].png"))
    if contact and frames:
        cols = min(6, len(frames))
        rows = math.ceil(len(frames) / cols)
        thumb_w = 240
        cmd = ["ffmpeg", "-v", "error", "-y", "-framerate", "1", "-i", str(out_dir / "%04d.png"),
               "-vf", f"scale={thumb_w}:-2,tile={cols}x{rows}:padding=4:margin=4:color=0x161131",
               "-frames:v", "1", str(out_dir / "planche.png")]
        subprocess.run(cmd, check=True)
    meta = {"source": str(video), "start": start, "end": end, "fps": fps, "frames": len(frames),
            "source_fps": round(info["fps"], 3), "source_size": [info["width"], info["height"]],
            "mirror": mirror, "crop": crop}
    (out_dir / "info.json").write_text(json.dumps(meta, indent=2, ensure_ascii=False), encoding="utf-8")
    return meta


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("video", nargs="?", help="rush à extraire")
    ap.add_argument("--start", type=float, default=0.0, help="début en secondes")
    ap.add_argument("--end", type=float, default=None, help="fin en secondes")
    ap.add_argument("--fps", type=int, default=12, help="cadence de sortie (12 = cadence d'animation du jeu)")
    ap.add_argument("--width", type=int, default=960, help="largeur des images extraites")
    ap.add_argument("--mirror", action="store_true", help="retourner horizontalement")
    ap.add_argument("--crop", default=None, help="recadrage W:H:X:Y")
    ap.add_argument("--out", default=None, help="dossier de sortie")
    ap.add_argument("--cuts", default=None, help="fichier JSON de découpes (traitement par lot)")
    ap.add_argument("--rushes", default=str(ROOT / "rushes"), help="dossier des rushes (pour --cuts)")
    args = ap.parse_args()
    if not shutil.which("ffmpeg") or not shutil.which("ffprobe"):
        print("ffmpeg et ffprobe sont nécessaires (https://ffmpeg.org).", file=sys.stderr)
        return 1
    if args.cuts:
        cuts = json.loads(Path(args.cuts).read_text(encoding="utf-8"))
        for c in cuts:
            name = c.get("anim", Path(c["video"]).stem).replace("/", "__")
            meta = extract(Path(args.rushes) / c["video"], DEFAULT_OUT / name, float(c.get("start", 0)),
                           c.get("end"), int(c.get("fps", args.fps)), int(c.get("width", args.width)),
                           bool(c.get("mirror", False)), c.get("crop"))
            print(f"{name} : {meta['frames']} images")
        return 0
    if not args.video:
        ap.print_help()
        return 1
    video = Path(args.video)
    out = Path(args.out) if args.out else DEFAULT_OUT / video.stem
    meta = extract(video, out, args.start, args.end, args.fps, args.width, args.mirror, args.crop)
    print(f"{meta['frames']} images → {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
