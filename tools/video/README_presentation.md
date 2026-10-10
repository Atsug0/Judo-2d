# Vidéo de présentation

1. Choisir une graine de combat spectaculaire :
   `godot --headless --path . -s tools/video/find_seed.gd -- --from=1 --to=400 --builds=0,1 --level=2`
2. Enregistrer la vidéo du jeu, menus pilotés par `presentation.json` (Movie Maker de Godot, image et son) :
   `godot --path . --write-movie pres.avi --fixed-fps 60 -- --demo=tools/video/presentation.json --seed=123`
   Partir de données utilisateur vierges (builds par défaut), sinon le combat diffère.
3. Créer les légendes : `python3 tools/video/make_caption.py "KUMIKATA" "bataille de mains · saisies · domination" k.png hot`
4. Monter avec ffmpeg : couper le sol trop long, fondu enchaîné, légendes en bas à droite, fondu final.
