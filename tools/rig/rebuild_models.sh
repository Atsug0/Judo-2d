#!/usr/bin/env bash
# Reconstruit les judokas 3D du jeu depuis les modèles bruts de art/modeles3d/ :
#   normalize.py (1,90 m, PNG) → autorig.py (squelette + poids) → decimate.py (temps réel)
#   → assets/judokas/<judoka>/{rig.glb, joints.json}, puis rendu des poses de menu.
# Usage : tools/rig/rebuild_models.sh [homme_blanc homme_bleu femme_bleu]   (défaut : tous)
# Nécessite python3 + numpy + scipy + Pillow, et godot dans le PATH pour les poses de menu
# (sous Linux sans écran : Xvfb sur DISPLAY=:99, voir CLAUDE.md).
set -euo pipefail
cd "$(dirname "$0")/../.."
TMP="${TMPDIR:-/tmp}/judo_rig"
mkdir -p "$TMP"
declare -A JOINTS=(
  [homme_blanc]=tools/rig/judoka_ia_joints.json
  [homme_bleu]=tools/rig/judoka_ia_bleu_joints.json
  [femme_bleu]=tools/rig/judokate_ia_joints.json
)
WHO=("$@")
[ ${#WHO[@]} -eq 0 ] && WHO=(homme_blanc homme_bleu femme_bleu)
for w in "${WHO[@]}"; do
  j="${JOINTS[$w]}"
  echo "== $w"
  python3 tools/rig/normalize.py "art/modeles3d/$w.glb" "$TMP/${w}_norm.glb"
  python3 tools/rig/autorig.py "$TMP/${w}_norm.glb" "$j" "$TMP/${w}_rig.glb" | tail -n 2
  mkdir -p "assets/judokas/$w"
  python3 tools/rig/decimate.py "$TMP/${w}_rig.glb" "assets/judokas/$w/rig.glb" --voxel 0.012 --uvq 48 --tex 1024
  cp "$j" "assets/judokas/$w/joints.json"
done
if command -v godot >/dev/null; then
  godot --path . -s tools/rig/render_poses.gd 2>&1 | grep -E "rendu|échec" || true
else
  echo "godot introuvable : poses de menu non régénérées (godot --path . -s tools/rig/render_poses.gd)"
fi
