# CLAUDE.md — Judo 2D

Contexte complet pour reprendre le projet (Claude Code en local ou dans le cloud).
À lire en entier avant de toucher au code. Garder ce fichier à jour quand l'architecture,
les outils ou les conventions changent.

---

## 1. Le projet et la façon de travailler

**Jeu de combat de judo en 2D pour PC, 100 % manette**, fait avec **Godot 4.4.1** (moteur GL Compatibility).
Pas de barre de vie : on gagne par le **kumikata** (saisies), le **kuzushi** (déséquilibre), le **timing**,
et au sol par le **ne-waza** (immobilisations, clés, étranglements). Format **BO3** façon jeu de combat.
Direction artistique inspirée de **2XKO** (panneaux inclinés, encre épaisse, couleurs saturées, cel-shading).

- Porteur du projet : **Hugo** (pseudo GitHub Atsug0), judoka en compétition. **Toujours répondre en français.**
- Dépôt : `https://github.com/Atsug0/Judo-2d`, branche **`main`** (on travaille et on pousse directement sur main).
  Le message « This repository moved » au push est sans conséquence.
- **Game Design Document** (doc Claude) : https://claude.ai/code/artifact/29beb0d2-f496-4822-b4f0-bcb6c0574a01
  (projet Claude Docs `29beb0d2-f496-4822-b4f0-bcb6c0574a01`, nœud `82e1757c-f40c`). Hugo veut que **toutes
  les décisions y soient centralisées** : le mettre à jour quand une mécanique, un réglage ou un pipeline change.
  Il n'y a pas encore de section sur le pipeline 3D (sections 6 à 8 ci-dessous) : à ajouter.

Préférences d'Hugo (à respecter sans qu'il ait à le redire) :
- **Pousser régulièrement** sur GitHub (commit par étape cohérente, message en français, détaillé).
- **Envoyer des captures d'écran** et un **récap court** après chaque changement visible.
- **Ne pas faire de vidéo tant qu'il ne l'a pas demandé** explicitement.
- Noms des légendes **fictifs** (droit à l'image) ; ne jamais copier un personnage protégé.
- La vidéo YouTube d'uchi-mata (« Uchi-mata - Demo ») est utilisée **avec l'accord de son auteur**.
- Il préfère que je fasse le maximum en autonomie puis que je présente le résultat, plutôt que de poser des questions.
- **Direction visuelle (13/10/2026)** : Hugo n'aime pas le rendu des modèles 3D. On garde **ses artworks dessinés**
  (fiches ChatGPT) en **2D façon Street Fighter**, animés par **découpage** (§5.0). La 3D reste dans le dépôt,
  désactivée (`--models3d` pour la voir). Prochaine étape possible : remplacer les moments clés par de vraies
  images dessinées (sprites) quand il y en aura.

---

## 2. Démarrage rapide

```bash
godot --path .                      # lancer le jeu (ou ouvrir le dossier dans l'éditeur, F5)
godot --headless --path . -s tools/smoke_test.gd          # parcours des écrans (échoue au 1er écart)
godot --headless --path . -s tools/sim_test.gd -- --matches=24 --level=2   # déterminisme + stats IA
godot --headless --path . -s tools/legends_rr.gd -- --matches=4 --level=2  # toutes rondes des légendes
godot --headless --path . -s tools/challenge_test.gd -- --tries=6          # faisabilité des défis
```

Sans manette, les combats se jouent IA contre IA (démo) ; flèches + Entrée / Échap pour les menus.
**Avant de pousser** : `smoke_test` et `sim_test` doivent passer (le déterminisme est vérifié par checksum).
Le mode headless n'affiche pas la 3D : tout changement de rendu se vérifie avec une capture (section 10).

Dépendances outils Python : `python3` ≥ 3.10, `numpy`, `scipy`, `Pillow` ; `ffmpeg`/`ffprobe` pour la vidéo ;
Blender 4.x seulement pour les scripts `tools/blender/` (facultatifs).

---

## 3. Arborescence

```
project.godot          autoload Sound ; fenêtre 1280×720 ; warning integer_division désactivé
scenes/main.tscn       scène unique → scripts/main.gd (gestion des écrans)
data/                  réglages et contenu (JSON, entiers → convertis en int au chargement)
  config.json          ~170 réglages de la simulation (tick_rate 60, throw_ticks 42, portées, coûts…)
  techniques.json      13 techniques debout + _counters, _combos, _newaza, _default_set
  catalog.json         coûts du build : budget 15, slots, gardes, styles, physique
  legends.json         10 judokas pré-configurés (noms fictifs) : mur, lame, seoi, tempete, eclair,
                       ours, sambiste, kesa, tacticienne, professeur (look.body3d = 1 → modèle femme)
  challenges.json      défis
  shotlist.json        liste de tournage au dojo (48 plans) générée depuis les techniques
  anims/<tech>.json    chorégraphies filmées (rotoscopie) ; existe : uchi_mata.json
scripts/
  main.gd              entrée, navigation manette, arguments CLI, mode capture / démo
  sim/match_sim.gd     SIMULATION déterministe (voir §4)
  sim/ai_controller.gd IA (entrées manette générées, PRNG à graine, niveaux 1..3)
  build.gd             build d'un judoka (techniques, garde, style, physique, look) → user://builds.json
  game_data.gd         chargement des JSON (int !)
  settings.gd          réglages joueur → user://settings.json (format bo3, durée, golden, volume…)
  records.gd           palmarès → user://records.json
  tournament.gd        tournoi 8 joueurs vs IA (déterministe)
  challenges.gd        défis (progression user://challenges.json)
  pad_reader.gd        manette → tableau d'entrées de la sim (mapping du GDD, notation Xbox)
  audio/sound.gd       autoload Sound (sons synthétisés par tools/audio/gen_audio.py), cosmétique
  dojo/                leçons guidées (lessons.gd, 23 leçons), partenaire, session, progression
  screens/             un script par écran : title, menu, match (≈2100 l), customize, select, vs,
                       tournament, results, options, online (maquette), dojo, challenges,
                       + outils : art (planches), lineup (légendes), bake (cuisson des placeholders)
  ui/style.gd          design system 2XKO (palette, polices Inter, panneaux inclinés)
  ui/rich.gd           texte avec boutons de manette {A} {B} {LT}…
  view/fighter_art.gd  squelette 2D du judoka, dessin placeholder, accès aux sprites 3D de menu
  view/throw_anims.gd  chorégraphies des projections (clés tori / uke)
  view/models3d.gd     judokas 3D en combat (SubViewport + caméra ortho calée sur la 2D)
  view/rig_pose.gd     pose d'un modèle riggé à partir d'articulations 3D
  view/sprite_library.gd  sprites 2D (format manifest) — pipeline sprites, actuellement non utilisé
  view/readout.gd      lecture « que donnerait chaque bouton » pour le HUD
assets/judokas/<modèle>/   modèles 3D du jeu : rig.glb, joints.json, poses/{garde,victoire}.png + poses.json
art/personnages/       fiches personnages (ChatGPT) : fiche, face, profil, dos, trois_quarts, pose_t
art/modeles3d/         modèles 3D BRUTS (TRELLIS) = sources des rigs (.gdignore : Godot ne les importe pas)
audio/                 musique et bruitages générés (tools/audio/gen_audio.py)
docs/                  PIPELINE_ANIMATION.md, GUIDE_TOURNAGE.md, AUDIO.md
screenshots/           captures de référence (tools/capture_all.sh)
tools/                 voir §9
rushes/                (ignoré par git) vidéos sources, sprites IA de test — n'existe pas sur une machine neuve
```

Les fichiers `*.gd.uid` **doivent être commités** avec leur script (Godot 4.4).

---

## 4. Simulation (scripts/sim/match_sim.gd) — règles d'or

- **Entiers uniquement, aucun aléatoire**, tick fixe **60/s** : mêmes entrées ⇒ même résultat.
  Les valeurs « fractionnaires » sont en fixe ×10000 (ex. qualité de prise `q`, `fat`).
- **L'affichage lit `sim.state`, il ne l'écrit jamais.** Tout ce qui est visuel (lissage, demi-tours 3D,
  tremblements, son) vit côté vue/écran.
- État complet copiable (`get_state` / `set_state`) + **checksum** : base du futur netcode **rollback** (phase 8 du GDD).
- Phases : `intro`, `fight`, `throw`, `score`, `matte`, `newaza`, `ended`. Un combat = manches de 2 min
  (réglage), golden score 1 min, BO3 par défaut (`settings.format`).
- Mains : `HAND_FREE / HAND_REACH / HAND_GRIP`, cibles `grip_targets` (manche, revers, col haut, ceinture).
- Toute nouvelle mécanique : réglages dans `data/config.json`, test dans `tools/sim_test.gd`, IA mise à jour
  (`ai_controller.gd` exploite le build : techniques équipées, combos, contres, ne-waza).

---

## 5. Rendu du combat

### 5.0 Judokas dessinés par découpage (rendu par défaut)
`scripts/view/cutout.gd` pose les morceaux de l'artwork (tête, buste, jupe de veste, bras, avant-bras,
main ouverte ou poing qui tient le judogi, cuisse, tibia, pied) entre les articulations du squelette 2D (§5.1).
Branché dans `fighter_art.gd` : `draw_fighter` (debout, kumikata, projections), `draw_figure` (ne-waza),
`draw_body` (menus, `next_pose = "victoire"` → bras levés), `draw_model_bust` (portraits = tête dessinée) ;
`draw_arm` ne fait rien quand le judoka est découpé (les bras sont déjà dessinés).
`pal.cutout` = `homme_blanc` (P1) / `homme_bleu` (P2). `--dessin` revient aux judokas vectoriels d'origine.
- Chaque morceau a deux articulations A (pivot) et B ; il est posé de A→B sur P→Q du squelette (longueur ajustée,
  largeur fixe `wu/wpx`, ou échelle uniforme `scale` pour tête, poing, pied, jupe).
- Ordre : bras loin (teinté `FAR_TINT`), jambe loin, jambe près, jupe, tête, buste, bras près.
  Bras : avant-bras puis main, manche par-dessus (cache le raccord du coude). Jambe : pied, tibia, cuisse.
- Épaule = emmanchure du buste dessiné (`points.shoulder`), bras allongés de `ARM_K` pour garder la portée.
- La jupe de la veste suit à moitié les cuisses (sinon elle reste raide quand le buste se penche).
- Pendant une projection, les mains qui tiennent sont fermées sans anneau de force (grip = 2.0).

Pipeline (voir aussi §6 bis) :
```
art/personnages/<j>/decoupe.png (planche de morceaux ChatGPT, profil vers la droite, fond gris uni)
  → tools/cutout/<j>.json (annotation : box, clip, A, B, échelle, plugs = ouvertures grises à boucher)
  → python3 tools/cutout/cut_parts.py tools/cutout/homme_blanc.json assets/cutout/homme_blanc --bleu assets/cutout/homme_bleu
  → assets/cutout/<j>/<morceau>.png + parts.json (la variante bleue est recolorée automatiquement)
```
Prompts ChatGPT qui ont donné la planche : « CUT-OUT PUPPET PARTS SHEET » (tête, buste sans bras avec ceinture,
bras dans la manche, avant-bras avec main, main ouverte, main qui serre un morceau de judogi, cuisse, tibia, pied,
tous de profil vers la droite, même échelle, séparés, fond gris #BDBDBD), avec la fiche du personnage en référence.
`profil_ecarte.png` (profil bras tendus, jambes écartées) sert de référence de proportions.
Contrôle : `godot --path . -- --screen=art` (garde, kuzushi) et `--screen=art --anim=<tech>` (projection).

### 5.1 Squelette 2D (la référence de toutes les poses)
`fighter_art.gd` : repère local **pieds en (0,0), avant = +x, haut = −y**, 100 unités = un judoka (1,80 m).
Constantes : `HIP0 (0,-47)`, `NECK0 (1,-86)`, `HEAD_CENTER (1,-98)`, `SHOULDER_FRONT/BACK`, `ARM_UPPER 20`,
`ARM_FORE 21.5`, `THIGH 23.5`, `SHIN 21.5`, `REST_HANDS`, `GRIP_POINTS` (points de saisie sur le buste).
Une **pose** est un dictionnaire : `hip` (bassin), `bow` (inclinaison du buste, rad), `tilt` (tête),
`fb`/`ff` (pied arrière/avant), `kb`/`kf` (genoux, sinon IK), `hb`/`hf` (mains), option `fist`.
`b` = côté loin de la caméra, `f` = côté caméra. Poses au sol : `Art.ground_poses` (hip, neck, head, knee_*, foot_*, elbow_*, hand_*).

### 5.2 Projections (`throw_anims.gd`)
Clés `{p, tori, uke}` avec pour chaque acteur `pos` (bassin), `rot`, `face` (+1/−1), `pose`.
Familles : `hanche` (seoi-nage, o-goshi, harai-goshi, uchi-mata, tai-otoshi : tori se retourne),
`fauche` (o-soto, o-uchi, ko-uchi), `balaye` (de-ashi-barai, sasae), `sacrifice` (tomoe-nage, sumi-gaeshi).
`ENTRY = 0.3`. Si `data/anims/<tech>.json` existe, la **chorégraphie filmée remplace** la dessinée.
Pendant une projection, les mains viennent de `match_screen._hands_world` : tori tient manche + revers,
uke garde la manche de tori jusqu'à p = 0.8 puis la main libre fait l'ukemi.

### 5.3 Judokas 3D (désactivés, `--models3d` pour les voir)
`match_screen._use_models3d` et `Art.use_3d()` : 3D seulement avec `--models3d` (et pas en headless). **P1 = judogi blanc, P2 = bleu** ; homme/femme selon `look.body3d` (0/1) →
`Models3D.who_for(look, player)` → `homme_blanc|homme_bleu|femme_blanc|femme_bleu`.

`models3d.gd` :
- SubViewport transparent 1280×720, lumières (clé chaude, contre-jours rose et cyan), caméra **orthographique**
  synchronisée sur la caméra 2D (`update_camera`), `ppm = K / (1.8/100)`.
- `pose_rig(i, xf, pose, hands, ground, shift_in, grips)` : convertit la pose 2D en **repère anatomique**
  (a = avant, y = haut, r = droite, en m, profondeur gauche/droite `HALF`), puis la place dans la scène avec
  l'orientation `phi` du judoka. **Demi-tour progressif** : quand `face` s'inverse, `phi` tourne en
  `TURN_FRAMES` (9) images en passant face caméra, et les articulations passent en fondu (`BLEND_FRAMES`).
  L'horloge est `m3d.clock = frame` du combat (pas l'horloge moteur : le mode capture ne dessine pas
  entre les ticks). `instant_turn = true` pour les outils image par image.
- `pose_ground` pour le ne-waza (mains fermées sur le judogi).
- `grips` : −1 = pas de prise (main entrouverte 0.3), sinon 0.8 + 0.2·force.

`rig_pose.gd` → `pose(M, ground, shift_in, grips)` (M = articulations 3D : bassin, cou, tete, haut (vertical
du corps), hanche/genou/pied/epaule/coude/main `.L/.R`) :
- **Colonne courbée** : courbe de Bézier entre le bassin (qui reste proche de la verticale du corps) et la
  poitrine (dans l'axe du buste), répartie sur hips / spine / spine2 / chest ; vrille répartie des hanches aux épaules.
- **Membres par plan de flexion** : bras et jambes orientés avec la normale (segment1 × segment2) pour que coude
  et genou plient comme une charnière (repos : normale −Y bras gauche, +Y bras droit, +X jambes).
  Membre tendu ⇒ on garde l'orientation de repos portée par le parent.
- Clavicule qui se lève/avance avec le bras ; doigts (2 phalanges) et pouce fermés selon `grips`.
- Pied à plat quand il est bas (< 0.16 m), orteils à plat un peu plus longtemps (talon décollé).
- Calage au sol : la semelle / les orteils les plus bas posés à y = 0 ; en l'air, `shift_in` imposé (uke suit tori).

### 5.4 Menus
Les écrans de menu n'affichent pas de 3D en direct : ils utilisent des **sprites pré-rendus**
`assets/judokas/<modèle>/poses/<garde|victoire>.png` (+ `poses.json`) via `Art.draw_model` /
`Art.draw_model_bust` (`Art.next_pose = "victoire"` pour la prochaine silhouette).
À régénérer après tout changement de rig ou de pose : `godot --path . -s tools/rig/render_poses.gd`.

---

## 6. Pipeline des modèles 3D (TRELLIS → jeu) — en sommeil (rendu écarté par Hugo)

```
art/personnages/<j>/pose_t.png ──TRELLIS (HF, démo officielle microsoft/TRELLIS, gratuit)──► art/modeles3d/<j>.glb
   └─► tools/rig/rebuild_models.sh <j> :
         normalize.py   1,90 m, pieds à y = −0,95, textures WebP → PNG, couleur de base seule, non métallique
         autorig.py     squelette (tools/rig/<…>_joints.json) + poids de peau par diffusion harmonique sur la surface
         decimate.py    --voxel 0.012 --uvq 48 --tex 1024 (~9,5 Mo par modèle)
         → assets/judokas/<j>/rig.glb + joints.json, puis render_poses.gd (sprites de menu)
```
La chaîne est **déterministe** (relancer donne des fichiers identiques). ~45 s par modèle.

Modèles : `homme_blanc` ← `judoka_ia_joints.json`, `homme_bleu` ← `judoka_ia_bleu_joints.json`,
`femme_bleu` ← `judokate_ia_joints.json`. **`femme_blanc` est provisoire** : `modele.json` emprunte le rig
de `femme_bleu` + `texture.png` repeinte (`tools/rig/gi_blanc.py`). Hugo doit fournir le vrai GLB.

Format des joints (`*_joints.json`) — repère du modèle : mètres, **Y haut, tourné vers +Z, sa gauche vers +X, pose T** :
- `joints` : bassin, dos, milieu, poitrine, cou, tete, sommet ; et par côté `.L/.R` : clavicule, epaule, coude,
  poignet, jointure, doigt_mi, doigt_bout, doigts, pouce_base, pouce_bout, hanche, genou, cheville, plante, orteils.
- `bones` : `[nom, articulation tête, articulation queue, parent, rayon de graine]` — **28 os** :
  hips, spine, spine2, chest, neck, head ; shoulder, upper_arm, forearm, hand, fingers1, fingers2, thumb (×2) ;
  thigh, shin, foot, toes (×2).
- Options autorig facultatives : `fold_cut`, `protect` (skin_ok…), `belt_free`, `drop_bridges`.
- Pour ajouter un os : ajouter l'articulation et l'os dans les 3 JSON, relancer `rebuild_models.sh`,
  puis le piloter dans `rig_pose.gd` (un os non piloté suit son parent).

Conseils génération : fiches « style jeu de combat, cel-shading », judogi **judo** (pas karaté : mains ouvertes,
revers croisé, ceinture), vue de face en pose T fond blanc pour TRELLIS. Les modèles réalistes (scan) ont été
**rejetés** par Hugo : on garde ce style stylisé.

Contrôle visuel : `tools/rig/compare_anim.gd` (dessin 2D en haut, 3D en bas, par avancement) :
```
godot --path . -s tools/rig/compare_anim.gd -- --tech=seoi_nage --out=/tmp/cmp --steps=0,0.3,0.45,0.6,0.8,1 \
      [--zoom=2 --cx=700 --cy=470 --crop=340,140,600,560 --cw=420] [--who=homme_blanc,homme_bleu]
```

---

## 7. Animations depuis une vidéo (rotoscopie)

Méthode utilisée pour l'uchi-mata (13 images clés) :
1. Hugo envoie un **mp4** (pas de lien YouTube : le réseau du cloud bloque YouTube) — en pièce jointe, ou
   déposé dans un dossier `videos/` poussé sur GitHub (< 100 Mo). Il précise tori et l'intervalle utile.
2. Extraire les images : `python3 tools/video/extract_frames.py video.mp4 --start 2 --end 19 --fps 12`.
3. Annoter à la main (en pixels) tête, cou, bassin, genoux, chevilles, poignets de tori et uke, côté
   caméra / opposé, sens du regard → modèle : `tools/mocap/uchi_mata_annot.json`.
4. `python3 tools/mocap/retarget.py tools/mocap/<tech>_annot.json` → `data/anims/<tech>.json`
   (garde les angles, réapplique les longueurs du squelette du jeu). Le jeu l'utilise automatiquement.
5. Contrôle : `godot --path . -- --screen=art --anim=<tech>` et `compare_anim.gd`.

C'est le **meilleur levier de qualité** : les chorégraphies dessinées (`throw_anims.gd`) restent raides
(uke « en planche »), la 3D les suit fidèlement. Prochaines techniques à filmer : seoi-nage, o-soto-gari,
tai-otoshi, harai-goshi, tomoe-nage, et les contres.

Autres pistes conservées : `tools/blender/` (scène toon + rendu de sprites depuis Blender),
`tools/sprites_ia/prepare.py` (sprites générés par IA → manifest), `docs/PIPELINE_ANIMATION.md` (tournage au dojo).

---

## 8. Arguments du jeu (après `--`)

| Argument | Effet |
| --- | --- |
| `--screen=title\|menu\|match\|customize\|select\|vs\|tournament\|results\|options\|online\|dojo\|challenges\|art\|lineup\|bake` | écran de départ |
| `--p1build=<id> --p2build=<id>` | judokas (id de légende : lame, mur, seoi, kesa…) |
| `--seed=<n> --level=1..3` | graine et niveau IA |
| `--capture=<dossier>` | mode capture (quitte à la fin) ; combat : `--ticks=a,b,c --max=n --until=t --events --settle=n` ; menus : `--frames=n --nav=down,accept --name=x` |
| `--skip=N` / `--skip_to=<tick>` | avance rapide du combat avant d'enregistrer |
| `--eventlog=f.tsv` | journal image / manche / tick / événement (montage vidéo) |
| `--quit_results=N` | quitte N images après les résultats |
| `--demo=f.json` | pilotage scripté des menus (vidéos) |
| `--lesson=<id>` / `--training --partner=garde` | leçon du dojo / entraînement libre |
| `--dessin` | judokas vectoriels d'origine au lieu de l'artwork découpé |
| `--models3d[=<dossier>] --models3d_who=a,b` | active les judokas 3D (désactivés par défaut) |
| `--anim=<tech>` (`--zoom`, `--ground`, `--count`) | (écran art) planche d'une chorégraphie |
| `--bo3`, `--replay`, `--demo_round=n`, `--readout`, `--cursor`, `--dojo_lesson=n` | options de capture / démo |

---

## 9. Catalogue des outils (`tools/`)

Découpage : `cutout/cut_parts.py` + `cutout/<judoka>.json` (annotation de la planche de morceaux).
Tests : `smoke_test.gd`, `sim_test.gd`, `legends_rr.gd`, `challenge_test.gd`, `list_lessons.gd`.
Captures : `capture_all.sh [écran…]` (régénère `screenshots/`), `capture_texts.sh <dossier>`.
3D / rig : `rig/rebuild_models.sh`, `normalize.py`, `autorig.py`, `decimate.py`, `glb_io.py`,
`gi_bleu.py` / `gi_blanc.py` (recoloration de texture), `render_poses.gd`, `compare_anim.gd`,
`pose_model.gd` + `mocap_to_rig.py` (rendu d'une chorégraphie filmée avec les modèles),
`judoka_joints.json` (ancien squelette, modèles réalistes abandonnés).
Mocap : `mocap/retarget.py`, `uchi_mata_annot.json`, `export_joints.py` + `preview3d.gd` (mannequins),
`view_model.gd` (vues d'un .glb), `web/uchi_mata_3d.html` (visionneuse three.js).
Vidéo : `video/find_seed.gd`, `find_epic.gd`, `find_epic_bo3.gd`, `find_kumikata_seed.gd`, `find_moments.gd`
(chercher de beaux combats), `make_caption.py` (bandeaux de légende DA), `montage_pres.py` (montage segment
par segment), `montage_v3.py`, `extract_frames.py`, `check_rushes.py`, JSON de démo (`pres_*.json`, `demo_*.json`),
`README_presentation.md` (recette complète de la vidéo de présentation).
Audio : `audio/gen_audio.py` (tout le son par synthèse, sans licence).
Blender : `blender/setup_scene.py`, `import_mocap.py`, `render_sprites.py`, `batch_render.py`.

---

## 10. Rendu sans écran (Linux / cloud) et pièges connus

```bash
(setsid nohup Xvfb :99 -screen 0 1280x720x24 >/dev/null 2>&1 < /dev/null &)   # si "Unable to create DisplayServer"
export DISPLAY=:99 LIBGL_ALWAYS_SOFTWARE=1
godot --rendering-driver opengl3 --path . -- --screen=match --capture=/tmp/c --p1build=seoi --p2build=kesa --seed=8 --level=3 --ticks=4040,4052 --max=2 --until=4060
godot --rendering-driver opengl3 --path . --write-movie x.avi --fixed-fps 60 --quit-after 600 -- --screen=vs ...   # Movie Maker
```
- **Données utilisateur** (`~/.local/share/godot/app_userdata/Judo 2D/*.json`) : les sauvegarder avant un
  enregistrement / une capture qui joue des combats, et les restaurer après (sinon palmarès et builds pollués).
- Tâches longues : `setsid nohup … &` + fichier témoin `done` (les commandes ont un délai max).
- Vidéo : monter **segment par segment** (un gros graphe ffmpeg tue la mémoire) ; x264 en CRF + maxrate (le 2-passes plantait).
- Réseau du cloud : pas de YouTube, pas de huggingface.co, pas de pip (sauf registre), pas de raw.githubusercontent ;
  `git push` fonctionne. Demander les fichiers à Hugo.
- `godot --import` réécrit `project.godot` (supprime des valeurs par défaut) : ne pas l'utiliser, ou annuler le diff.
- Les .glb sont chargés **à l'exécution** (`GLTFDocument`), pas via l'import Godot ; les `rig_*.png` extraits
  par l'éditeur sont ignorés par git.
- Le mode capture enchaîne des ticks **sans dessiner** : tout effet visuel temporel doit suivre l'horloge
  du combat (`frame`), pas `Engine.get_process_frames()`.
- Polygones 2D : passer par `_fill` (enveloppe convexe sûre) dans `fighter_art.gd` (échecs de triangulation sinon).
- Mode headless : pas de 3D (`Art.use_3d()` faux) → les tests headless ne valident pas le rendu 3D.

---

## 11. Conventions de code

- Code, commentaires, textes du jeu et commits **en français** ; scripts commençant par un commentaire `##`
  qui dit à quoi ils servent et comment les lancer.
- GDScript typé quand c'est utile ; attention aux inférences `:=` sur des valeurs de `Dictionary` (Variant) :
  typer explicitement (`var x: float = d.k`).
- La simulation reste pure (entiers, pas d'aléatoire, pas de rendu) ; la vue ne modifie jamais `state`.
- Réglages de gameplay dans `data/*.json`, pas en dur.
- Commits : message en français, titre clair + liste de ce qui change, puis
  `Co-Authored-By: …` selon l'outil utilisé.

---

## 12. État au 12/10/2026 et suite

Fait (13/10) : judokas dessinés par découpage à partir de l'artwork d'Hugo (homme blanc, bleu recoloré),
partout (combat, sol, projections, menus, portraits) ; la 3D est désactivée.

Fait avant : jeu jouable de bout en bout (titre → menu → tournoi / versus / dojo / défis → combat debout et sol →
résultats), BO3, 10 légendes, personnalisation complète, son, judokas 3D partout (combat, dojo, menus),
mains articulées, squelette 28 os avec colonne courbée et demi-tours progressifs, uchi-mata filmé,
vidéos de présentation.

À faire / pistes :
- Planches de morceaux pour les autres judokas (homme bleu dédié, femmes blanche et bleue) : même prompt,
  nouvelle annotation `tools/cutout/<j>.json`, puis `pal.cutout` selon `look.body3d` (homme / femme).
  Aujourd'hui les légendes féminines s'affichent avec l'homme.
- Arbitre encore en vectoriel : lui faire une planche aussi.
- Images dessinées pour les moments clés (garde, chute d'uke, ippon) en complément du découpage.
- Modèle **femme en judogi blanc** dédié (attendre le GLB d'Hugo → `art/modeles3d/femme_blanc.glb`).
- Plus de **techniques filmées** (§7) : c'est ce qui rendra les projections naturelles.
- Retoucher les chorégraphies dessinées les plus raides (uke en planche dans `hanche`, bras d'uke).
- Orientation de la main vers la prise (poignet), vrille d'avant-bras.
- Tester le **versus à deux manettes** en vrai.
- **En ligne** : rollback prêt côté simulation, réseau à brancher (phase 8 du GDD).
- Mettre à jour le GDD avec le pipeline 3D.
