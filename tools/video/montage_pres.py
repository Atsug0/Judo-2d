#!/usr/bin/env python3
"""Montage de la vidéo de présentation, segment par segment (mémoire limitée) :
chaque segment est coupé dans les rushes, reçoit ses légendes PNG et de courts fondus
(image et son), puis tout est mis bout à bout.

    python3 tools/video/montage_pres.py <dossier_rushes> <dossier_legendes> <segments.json> <sortie.mp4>

segments.json : [[fichier, début, fin, [[légende.png, apparition, "top"?], ...]], ...]
Un fichier .png est une carte fixe (son muet).
"""
import json
import os
import subprocess
import sys

RUSH, CAP, SEGS, OUT = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
FADE = 0.25        # fondu au noir entre deux segments (s)
CAP_DUR = 3.4      # durée d'affichage d'une légende (s)
CAP_SCALE = 0.6    # taille des légendes


def render(k, seg, tmp):
    f, a, b, caps = seg[0], seg[1], seg[2], seg[3] if len(seg) > 3 else []
    d = b - a
    last = k == NSEG - 1
    inputs = []
    if f.endswith(".png"):
        inputs += ["-loop", "1", "-framerate", "60", "-t", str(d), "-i", f"{CAP}/{f}",
                   "-f", "lavfi", "-t", str(d), "-i", "anullsrc=r=48000:cl=stereo"]
        audio = "[1:a]"
        first_cap = 2
    else:
        inputs += ["-ss", str(a), "-t", str(d), "-i", f"{RUSH}/{f}"]
        audio = "[0:a]"
        first_cap = 1
    chains = [f"[0:v]fps=60,scale=1280:720,setsar=1,format=yuv420p,setpts=PTS-STARTPTS[b0]"]
    cur = "b0"
    for j, cap in enumerate(caps):
        png, ct = cap[0], cap[1]
        # « top » : sous le HUD ; « mid » : sous les jauges du sol ; sinon en bas à gauche
        pos = cap[2] if len(cap) > 2 else "bottom"
        y = {"top": "190", "mid": "300"}.get(pos, "H-h-112")
        inputs += ["-loop", "1", "-t", str(d), "-i", f"{CAP}/{png}"]
        chains.append(f"[{first_cap + j}:v]format=rgba,scale=iw*{CAP_SCALE}:-1,fade=in:st={ct}:d=0.3:alpha=1,fade=out:st={ct + CAP_DUR}:d=0.4:alpha=1[c{j}]")
        chains.append(f"[{cur}][c{j}]overlay=x=20:y={y}:enable='between(t,{ct},{ct + CAP_DUR + 0.4})',format=yuv420p[o{j}]")
        cur = f"o{j}"
    fo = 1.2 if last else FADE
    chains.append(f"[{cur}]fade=in:st=0:d={FADE},fade=out:st={d - fo:.3f}:d={fo}[vo]")
    chains.append(f"{audio}aresample=48000,aformat=channel_layouts=stereo,asetpts=PTS-STARTPTS,"
                  f"afade=in:st=0:d={FADE},afade=out:st={d - fo:.3f}:d={fo},atrim=0:{d}[ao]")
    out = os.path.join(tmp, f"seg_{k:02d}.mp4")
    cmd = ["ffmpeg", "-loglevel", "error", "-y"] + inputs + ["-filter_complex", ";".join(chains),
           "-map", "[vo]", "-map", "[ao]", "-t", str(d), "-c:v", "libx264", "-crf", "18", "-preset", "fast",
           "-pix_fmt", "yuv420p", "-r", "60", "-c:a", "aac", "-b:a", "160k", "-ar", "48000", out]
    subprocess.run(cmd, check=True)
    return out


SEGMENTS = json.load(open(SEGS))
NSEG = len(SEGMENTS)


def main():
    tmp = os.path.splitext(OUT)[0] + "_segs"
    os.makedirs(tmp, exist_ok=True)
    parts = []
    for k, seg in enumerate(SEGMENTS):
        parts.append(render(k, seg, tmp))
        print(f"segment {k + 1}/{NSEG}", flush=True)
    lst = os.path.join(tmp, "list.txt")
    with open(lst, "w") as fh:
        for p in parts:
            fh.write(f"file '{os.path.abspath(p)}'\n")
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-f", "concat", "-safe", "0", "-i", lst,
                    "-c", "copy", "-movflags", "+faststart", OUT], check=True)
    total = sum(s[2] - s[1] for s in SEGMENTS)
    print("vidéo :", OUT, f"({total:.1f} s)")


main()
