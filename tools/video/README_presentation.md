# Vidéo de présentation

Données utilisateur vierges avant chaque enregistrement (sauvegarder puis vider `user://`).
Movie Maker de Godot, 60 i/s, sous Xvfb (`DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1 --rendering-driver opengl3`).

1. Chercher un combat épique en deux manches gagnantes (feintes, arrachages, osaekomi aux curseurs,
   toketa, retournement par la garde, clés, fin sur projection) :
   `godot --headless --path . -s tools/video/find_epic_bo3.gd -- --a=lame --b=sambiste --from=1 --to=60 --level=3`
2. Enregistrer les rushes :
   - combat : `godot --path . --write-movie fight.avi --fixed-fps 60 -- --screen=vs --p1build=lame --p2build=sambiste --seed=14 --level=3 --eventlog=fight_events.tsv --quit_results=300`
     (`fight_events.tsv` : image, manche, tick, événement → placer les coupes et légendes)
   - menus : `-- --demo=tools/video/pres_intro.json`
   - tournoi : `-- --screen=menu --demo=tools/video/pres_tour.json`
   - leçons : `-- --lesson=b3_mains --demo=tools/video/pres_lesson.json` (aussi b7_feinte, b6_reaction, b9_contre)
   - `--skip=N` avance un combat de N images sans son avant d'enregistrer.
3. Légendes : `python3 tools/video/make_caption.py "TITRE" "sous-titre" out.png hot|p1|p2|gold`
4. Montage : `python3 tools/video/montage_pres.py <rushes> <légendes> tools/video/presentation_segments.json sortie.mp4`
