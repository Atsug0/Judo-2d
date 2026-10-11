#!/usr/bin/env bash
# Captures de contrôle des textes (dojo, leçons, cartes de technique) dans le dossier donné.
# Usage : tools/capture_texts.sh <dossier>
set -uo pipefail
cd "$(dirname "$0")/.."
OUT=${1:?dossier}
mkdir -p "$OUT"
export DISPLAY=${DISPLAY:-:99}
pgrep -x Xvfb >/dev/null 2>&1 || { (Xvfb "$DISPLAY" -screen 0 1280x720x24 >/dev/null 2>&1 &); sleep 2; }
G() { LIBGL_ALWAYS_SOFTWARE=1 timeout 90 godot --path . --rendering-driver opengl3 -- "$@" 2>&1 | grep -E "SCRIPT ERROR" | head -3; }
G --screen=dojo --capture="$OUT" --frames=10 --dojo_focus=1 --dojo_lesson=5 --name=dojo_base
for n in 1 2 3 4 5; do
  nav=$(printf 'down,%.0s' $(seq $n)); G --screen=dojo --capture="$OUT" --frames=10 --nav=${nav}right --name=dojo_cat$n
done
for l in ${LESSONS:-t_tomoe_nage b6_reaction b3_mains b10_sol c_ko_uchi_seoi k_ura_nage n_sortie}; do
  G --lesson=$l --capture="$OUT" --frames=30 --name=intro_$l
  G --lesson=$l --capture="$OUT" --frames=30 --nav=accept --name=step_$l
done
G --training --capture="$OUT" --frames=30 --name=training
G --screen=customize --capture="$OUT" --frames=10 --nav=next,down,down --name=custom_tech
