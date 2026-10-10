#!/usr/bin/env bash
# Génère toutes les captures d'écran de référence dans screenshots/.
# Usage : tools/capture_all.sh [écran...]   (sans argument : tous les écrans)
# Nécessite Godot 4 dans le PATH ; sous Linux sans écran, lancer Xvfb (DISPLAY=:99).
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="$PWD/screenshots"
TMP="$PWD/captures"
mkdir -p "$OUT"
GODOT=${GODOT:-godot}
export DISPLAY=${DISPLAY:-:99}
# Sous Linux sans écran : démarre Xvfb s'il n'est pas déjà là.
if ! pgrep -x Xvfb >/dev/null 2>&1 && [ "$(uname)" = "Linux" ]; then
  if command -v Xvfb >/dev/null; then
    (Xvfb "$DISPLAY" -screen 0 1280x720x24 >/dev/null 2>&1 &)
    sleep 2
  fi
fi
run() {
  local log
  log=$(LIBGL_ALWAYS_SOFTWARE=1 timeout 240 "$GODOT" --path . --rendering-driver opengl3 -- "$@" 2>&1) || true
  echo "$log" | grep -E "SCRIPT ERROR|capture :" || true
  if ! echo "$log" | grep -q "capture :"; then
    echo "ÉCHEC de capture ($*) :" >&2
    echo "$log" | grep -E "ERROR|error" | grep -v -i alsa | head -5 >&2
    return 1
  fi
}
want() { [ $# -eq 0 ] || [[ " ${TARGETS} " == *" $1 "* ]]; }
TARGETS="${*:-}"

if [ -z "$TARGETS" ] || [[ " $TARGETS " == *" match "* ]]; then
  rm -rf "$TMP"
  run --screen=match --capture="$TMP" --attack --after=600 --max=1 --until=8000 --seed=5
  cp "$TMP"/match_*.png "$OUT/02_combat_attaque.png"
  rm -rf "$TMP"
  run --screen=match --capture="$TMP" --events --max=4 --until=20000 --seed=5
  files=("$TMP"/match_*.png)
  cp "${files[0]}" "$OUT/03_combat_projection.png"
  cp "${files[1]}" "$OUT/04_combat_waza_ari.png"
  cp "${files[-1]}" "$OUT/05_combat_fin.png"
  rm -rf "$TMP"
fi
if [ -z "$TARGETS" ] || [[ " $TARGETS " == *" ground "* ]]; then
  rm -rf "$TMP"
  run --screen=match --capture="$TMP" --ticks=340,470 --max=2 --until=600 --seed=1 --p1build=2 --p2build=1
  cp "$TMP"/match_00340.png "$OUT/14_sol_osaekomi.png"
  cp "$TMP"/match_00470.png "$OUT/15_sol_juji_gatame.png"
  rm -rf "$TMP"
fi
for s in title menu customize select tournament results options online pause art; do
  if [ -z "$TARGETS" ] || [[ " $TARGETS " == *" $s "* ]]; then
    case $s in
      title) run --screen=title --capture="$OUT" --name=00_titre --frames=40 ;;
      menu) run --screen=menu --capture="$OUT" --name=01_menu --frames=30 ;;
      customize)
        run --screen=customize --capture="$OUT" --name=06_personnalisation_techniques --frames=20 --nav=down
        run --screen=customize --capture="$OUT" --name=06b_personnalisation_style --frames=20 --nav=next,down
        run --screen=customize --capture="$OUT" --name=06c_personnalisation_physique --frames=20 --nav=next,next ;;
      select) run --screen=select --capture="$OUT" --name=07_selection --frames=20 ;;
      tournament)
        run --screen=tournament --capture="$OUT" --name=08_tournoi --frames=20
        run --screen=tournament --capture="$OUT" --name=08b_tournoi_demi --frames=20 --demo_round ;;
      results) run --screen=results --capture="$OUT" --name=09_resultats --frames=40 ;;
      options) run --screen=options --capture="$OUT" --name=10_options --frames=20 ;;
      online) run --screen=online --capture="$OUT" --name=11_en_ligne --frames=30 ;;
      art)
        run --screen=art --capture="$OUT" --name=13_planche_perso --frames=2
        run --screen=art --capture="$OUT" --name=13b_planche_gros_plan --frames=2 --zoom
        run --screen=art --capture="$OUT" --name=13c_planche_sol --frames=2 --ground ;;
      pause) run --screen=match --capture="$OUT" --name=12_pause --frames=900 --seed=5 --nav=start ;;
    esac
  fi
done
ls -1 "$OUT"
