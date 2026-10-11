#!/usr/bin/env python3
"""Montage de la vidéo de démo v3 : segments coupés dans les rushes, légendes PNG,
fondus enchaînés (image et son), fondu final.

    python3 tools/video/montage_v3.py <dossier_rushes> <dossier_legendes> <sortie.mp4>

Rushes attendus : menus.avi, select.avi, fight.avi, dojo.avi (Movie Maker de Godot, 60 i/s).
"""
import subprocess
import sys

RUSH, CAP, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
X = 0.45  # durée des fondus enchaînés (s)

# (fichier, début, fin, légende ou None, apparition de la légende après le début du segment)
SEGMENTS = [
    ("menus.avi", 2.0, 9.0, None, 0),
    ("menus.avi", 9.0, 29.5, "c1.png", 0.6),
    ("select.avi", 0.5, 12.5, "c2.png", 0.6),
    ("fight2.avi", 0.0, 19.5, "c3.png", 3.4),
    ("fight2.avi", 21.0, 30.0, None, 0),
    ("fight2.avi", 53.0, 66.0, None, 0),
    ("fight2.avi", 66.0, 77.5, "c5.png", 0.8),
    ("fight2.avi", 94.0, 102.0, None, 0),
    ("fight2.avi", 140.0, 163.0, "c6.png", 9.0),
    ("dojo.avi", 2.5, 23.0, "c7.png", 2.5),
    ("end_card.png", 0.0, 4.0, None, 0),
]


def main():
    inputs = []
    chains = []
    for k, (f, a, b, cap, ct) in enumerate(SEGMENTS):
        if f.endswith(".png"):
            inputs += ["-loop", "1", "-framerate", "60", "-t", str(b - a), "-i", f"{CAP}/{f}"]
        else:
            inputs += ["-ss", str(a), "-t", str(b - a), "-i", f"{RUSH}/{f}"]
    ncap = 0
    cap_index = {}
    for k, seg in enumerate(SEGMENTS):
        if seg[3]:
            cap_index[k] = len(SEGMENTS) + ncap
            inputs += ["-loop", "1", "-t", str(seg[2] - seg[1]), "-i", f"{CAP}/{seg[3]}"]
            ncap += 1
    for k, (f, a, b, cap, ct) in enumerate(SEGMENTS):
        v = f"[{k}:v]fps=60,scale=1280:720,setsar=1,format=yuv420p,settb=AVTB,setpts=PTS-STARTPTS"
        if cap:
            c = cap_index[k]
            dur = 3.6
            chains.append(f"[{c}:v]format=rgba,fade=in:st={ct}:d=0.3:alpha=1,fade=out:st={ct + dur}:d=0.4:alpha=1[cap{k}]")
            chains.append(f"{v}[base{k}]")
            chains.append(f"[base{k}][cap{k}]overlay=x=24:y=H-h-70:enable='between(t,{ct},{ct + dur + 0.4})',format=yuv420p[v{k}]")
        else:
            chains.append(f"{v}[v{k}]")
        if f.endswith(".png"):
            chains.append(f"anullsrc=r=48000:cl=stereo,atrim=0:{b - a}[a{k}]")
        else:
            chains.append(f"[{k}:a]aresample=48000,aformat=channel_layouts=stereo,asetpts=PTS-STARTPTS[a{k}]")
    # fondus enchaînés
    last_v, last_a = "v0", "a0"
    t = SEGMENTS[0][2] - SEGMENTS[0][1]
    for k in range(1, len(SEGMENTS)):
        off = t - X
        trans = "fadeblack" if SEGMENTS[k][0] != SEGMENTS[k - 1][0] else "slideleft"
        chains.append(f"[{last_v}][v{k}]xfade=transition={trans}:duration={X}:offset={off:.3f}[xv{k}]")
        chains.append(f"[{last_a}][a{k}]acrossfade=d={X}[xa{k}]")
        last_v, last_a = f"xv{k}", f"xa{k}"
        t = off + (SEGMENTS[k][2] - SEGMENTS[k][1])
    chains.append(f"[{last_v}]fade=out:st={t - 1.2:.3f}:d=1.2[vo]")
    chains.append(f"[{last_a}]afade=out:st={t - 1.5:.3f}:d=1.5[ao]")
    cmd = ["ffmpeg", "-loglevel", "error", "-y"] + inputs + ["-filter_complex", ";".join(chains),
           "-map", "[vo]", "-map", "[ao]", "-c:v", "libx264", "-crf", "20", "-preset", "medium",
           "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "160k", "-movflags", "+faststart", OUT]
    subprocess.run(cmd, check=True)
    print("vidéo :", OUT, f"({t:.1f} s)")


main()
