# CLAUDE.md — Judo 2D

Contexte complet pour reprendre le projet (Claude Code en local ou dans le cloud).
À lire en entier avant de toucher au code. Garder ce fichier à jour quand l'architecture,
les outils ou les conventions changent.

---

## 1. Le projet et la façon de travailler

**Jeu de combat de judo en 2D pour PC**, manette **ou clavier** (§5.5), fait avec **Godot** (4.4.1 à l'origine, vérifié sur 4.7.2), moteur **Forward+** (il était en GL Compatibility jusqu'au 15/10/2026 : ce moteur ne sait rendre ni les ombres portées ni l'occlusion ambiante, et les judokas y restaient plats).
Pas de barre de vie : on gagne par le **kumikata** (saisies), le **kuzushi** (déséquilibre), le **timing**,
et au sol par le **ne-waza** (immobilisations, clés, étranglements). Format **BO3** façon jeu de combat.
Direction artistique inspirée de **2XKO** (panneaux inclinés, encre épaisse, couleurs saturées, cel-shading).

- Porteur du projet : **Hugo** (pseudo GitHub Atsug0), judoka en compétition. **Toujours répondre en français.**
- Dépôt : `https://github.com/Atsug0/Judo-2d`, branche **`main`** (on travaille et on pousse directement sur main).
  Le message « This repository moved » au push est sans conséquence.
- **Game Design Document** (doc Claude) : https://claude.ai/code/artifact/29beb0d2-f496-4822-b4f0-bcb6c0574a01
  (projet Claude Docs `29beb0d2-f496-4822-b4f0-bcb6c0574a01`, nœud `82e1757c-f40c`). Hugo veut que **toutes
  les décisions y soient centralisées** : le mettre à jour quand une mécanique, un réglage ou un pipeline change.
  Sections « Rendu des judokas » et « Animations des projections » ajoutées le 20/10 (avant « Plan d'action »).

Préférences d'Hugo (à respecter sans qu'il ait à le redire) :
- **Pousser régulièrement** sur GitHub (commit par étape cohérente, message en français, détaillé).
- **Envoyer des captures d'écran** et un **récap court** après chaque changement visible.
- **Ne pas faire de vidéo tant qu'il ne l'a pas demandé** explicitement.
- Noms des légendes **fictifs** (droit à l'image) ; ne jamais copier un personnage protégé.
- La vidéo YouTube d'uchi-mata (« Uchi-mata - Demo ») est utilisée **avec l'accord de son auteur**.
- Il préfère que je fasse le maximum en autonomie puis que je présente le résultat, plutôt que de poser des questions.
- **Direction visuelle (15/10/2026)** : retour à la **3D**, avec un nouveau casting généré sur **Tripo**
  (14 modèles, §6). Les judokas 3D sont **affichés par défaut** ; `--dessin` (ou `--decoupe`) repasse à
  l'artwork découpé (§5.0), conservé comme solution de repli. L'ancien lot (TRELLIS, 13/10) avait été
  écarté par Hugo faute de qualité.

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
  skins.json           catalogue des 12 personnages 3D : dossier de modèle par couleur de judogi
  stages.json          décors de combat (images de stage/) : horizon et bandeau LED
  shotlist.json        liste de tournage au dojo (48 plans) générée depuis les techniques
  anims/<tech>.json    chorégraphies filmées des 13 techniques (pointées à la main, §7.0)
scripts/
  main.gd              entrée, navigation manette, arguments CLI, mode capture / démo
  sim/match_sim.gd     SIMULATION déterministe (voir §4)
  sim/ai_controller.gd IA (entrées manette générées, PRNG à graine, niveaux 1..3)
  build.gd             build d'un judoka (techniques, garde, style, physique, look) → user://builds.json
  skins.gd             catalogue des skins : look.modele → dossier assets/judokas/ + texture
  stages.gd            décors : image du haut de la scène, calée par son horizon
  key_reader.gd        clavier → entrées de la sim (rampes en ticks, voir §5.5)
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

### 5.0 Judokas dessinés par découpage (solution de repli : `--dessin` / `--decoupe`)
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
Les 5 contres n'ont pas de vidéo : `MOCAP_ALIAS` leur prête la chorégraphie filmée la plus proche
(o-soto-gaeshi → o-soto-gari, utsuri-goshi → o-goshi, tsubame-gaeshi → de-ashi-barai,
uchi-mata-sukashi → tai-otoshi, ura-nage → sumi-gaeshi).
En combat, `_throw_frame` décale la chorégraphie pour qu'elle tienne sur le tapis (bord de l'arène),
et la caméra suit les judokas dessinés (`_throw_center`). Au sol, la caméra vise `NEWAZA_CAM_Y` pour que
la barre du mini-jeu passe sous les corps. `models3d` fait un fondu de 10 images entre pose debout et
pose au sol (`_cut_blend`).
Pendant une projection, les mains viennent de `match_screen._hands_world` : tori tient manche + revers,
uke garde la manche de tori jusqu'à p = 0.8 puis la main libre fait l'ukemi.

### 5.3 Judokas 3D (affichage par défaut)
`match_screen._use_models3d` et `Art.use_3d()` : 3D dès que les modèles sont là (et pas en headless) ;
`--dessin` / `--decoupe` repassent au découpage. **P1 = judogi blanc, P2 = bleu** ; le personnage vient du
skin choisi → `Models3D.who_for(look, player)` → `Skins.dir_for(look.modele, player)`. Quand un skin n'existe
qu'en une couleur, il la garde : `Skins.texture_for` ne renvoie aucune texture de remplacement.

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
- **Saisies** (`targets`, 20/10) : `pose(…, targets)` envoie la paume d'une main sur un point de la scène par
  cinématique inverse à deux segments, avec les **vraies longueurs de bras du modèle** (30 unités, contre 41
  pour le bras 2D : sans ça les mains s'arrêtaient à 30 cm du judogi). Le coude du jeu ne sert plus qu'à
  choisir le plan du bras. `grip_point(kind, côté, depuis)` donne le point du judogi adverse — revers,
  manche (sous le coude), col (dans le dos), ceinture — sur sa **dernière pose**, l'épaisseur du buste étant
  mesurée sur le maillage (`_measure`). Face à face, ma droite prend sa gauche.

### 5.3 bis Kumikata et ne-waza en 3D (20/10/2026)
Hugo : « ça ne s'attrape pas, c'est giga rigide, au sol les corps sont à l'envers ». Ce qui a été fait :
- `_hands_world` renvoie, en plus des mains 2D, des **cibles 3D** `{opp, pt, w, off}` (w : main en route
  → posée ; off : une part du tiraillement). `models3d.pose_rig(…, targets)` les résout sur le judogi 3D.
  L'adversaire doit avoir une pose récente (`is_stale`) : en mode capture, `match_screen` le pose d'abord.
- **Écart affiché** (`_gap_target`) : dans la portée de saisie de la sim (≈ 80 unités), il est ramené à
  `GRIP_GAP_NEAR`→`GRIP_GAP_FAR` (36 → 50), puis rejoint l'écart réel ×0,76 ; chaque main qui tient
  resserre, un judoka dominé (courbé) garde de la place. La projection part de cet écart, figé (`_tg`).
- **Posture** (`kumi_amt`, lissé) : pieds serrés, genoux fléchis, buste penché ; transfert de poids,
  `pose.twist` (vrille des épaules avec la main qui tire), mains libres qui suivent le buste.
- **Garde** (`pose.lead`) : en 3D, la jambe et la main avant sont celles de la garde (droitier = droite),
  plus forcément le côté caméra ; un changement de garde passe en fondu (`_turn_blend`).
- **Ne-waza** : une silhouette couchée de profil ne dit pas si elle est sur le dos ou sur le ventre. Les
  poses de `ground_poses` donnent `chest` (direction de la poitrine) et `pose_ground` choisit le côté
  caméra qui la respecte — avant, tout corps allongé tête en avant tombait à plat ventre. `z` / `z_up`
  (m) placent tori sur le flanc loin d'uke (kesa, yoko-shiho, transition) au lieu de le traverser.
- `_smooth` repart de la cible si la pose mémorisée date de plus de 2 images (captures périmées sinon).
- Bancs d'essai : `--screen=demo --kumikata[=sleeve,lapel] --lead=R,L --gap=38 --zoom=5` et
  `--screen=demo --sol=osaekomi:kesa_gatame`, avec `--capture=<dossier> --frames=60`.

### 5.5 Clavier (`scripts/key_reader.gd`)
Le jeu se joue à la manette **ou entièrement au clavier** (Options → COMMANDES : périphérique
et réassignation des 15 touches). `key_reader.gd` produit le même tableau d'entiers que
`pad_reader.gd` : la simulation ignore le périphérique et le déterminisme est intact.

Trois signaux analogiques manquent au clavier, et le piège est le **dash** : la sim le lit
quand `|MX|` passe de moins de 85 à plus de 85 en moins de `dash_flick_ticks` (3) ticks. Une
touche, qui saute de 0 à 100, en déclencherait un à chaque appui. Les directions montent donc
par paliers de 20 (85 franchi au 5ᵉ tick, trop tard pour la pichenette) et le dash a sa propre
touche, qui force un tick au neutre puis 100. Idem pour la force des saisies. **Les rampes se
comptent en ticks de simulation**, jamais en temps réel : les replays en dépendent.

`Style.clavier` (posé par `main.gd`) fait afficher les touches à la place des jetons de manette
`{A}` `{LT}` `{RS}` dans les aides, le HUD et les 23 leçons du dojo — aucun texte n'a été réécrit.

### 5.5 bis Rendu des modèles
Objectif : se rapprocher du rendu de l'aperçu Tripo, que les aplats écrasaient complètement
(Hugo, 15/10/2026, captures comparées à l'appui). Quatre choses s'additionnent :
- l'import garde la **normal map** (tissage, surpiqûres, plis) ;
- **éclairage doux** (`DIFFUSE_BURLEY`) au lieu de `DIFFUSE_TOON`, qui quantifiait tout en
  une seule bande : le judogi devenait un aplat blanc même avec la normal map ;
- **trois points façon studio** dans `models3d.gd` : clé chaude qui **porte des ombres**,
  déboucheuse froide sans ombre, contre-jour qui détache du décor ; ambiante à 0,22 ;
- **SSAO** (`ssao_enabled`) qui creuse les emmanchures, le dessous du menton et les plis,
  plus un léger spéculaire — d'où le passage en Forward+.
Le **contour d'encre** est gardé mais affiné (0,012 → 0,007) : il marque la silhouette sans
écraser le modelé. C'est lui qui donne le trait « jeu de combat », pas l'aplat.

### 5.5 ter Arbitre 3D
`models3d.setup_arbitre()` charge un **troisième acteur** (`assets/judokas/arbitre`) et
`match_screen._draw_referee` le pose comme un judoka. Deux pièges : `rig_pose` ne fait que
tourner les os, il ne redimensionne pas le modèle — l'échelle est donc portée par le nœud,
et l'abscisse passée à `pose_rig` doit être divisée par cette échelle ; et l'arbitre se
tenant au fond du tatami (`REF_FEET_Y`), le nœud le remonte de l'écart de pieds, sinon il
flotte au-dessus du tapis.

### 5.6 Cadrage
La caméra serre sur les judokas (zoom 1,7 à 2,0 en combat, jusqu'à 2,35 sur un ippon) : les
modèles 3D sont détaillés, les voir de loin n'a pas de sens. `_camera_target()` vise y = 464
pour que le judoka tienne entre le HUD et la barre d'aide. L'arbitre est redescendu à
`REF_SCALE` 0,52 : à ce zoom il devenait envahissant.

### 5.7 Décors (`scripts/stages.gd`, `data/stages.json`)
Un décor est une **image** (`stage/*.png`, générée sur Tripo) qui ne couvre que le haut de la
scène : le tatami reste dessiné par le jeu, ses bords étant ceux de la simulation. L'image est
posée pour que son `horizon` tombe sur `MAT_BACK`, puis agrandie pour couvrir la largeur — une
image **16:9 se cadre mieux qu'une carrée**, qui se fait rogner par le haut. `led` affiche le
bandeau publicitaire animé (salles de compétition, pas les dojos).

### 5.4 Menus
Les écrans de menu n'affichent pas de 3D en direct : ils utilisent des **sprites pré-rendus**
`assets/judokas/<modèle>/poses/<garde|victoire>.png` (+ `poses.json`) via `Art.draw_model` /
`Art.draw_model_bust` (`Art.next_pose = "victoire"` pour la prochaine silhouette).
À régénérer après tout changement de rig ou de pose : `godot --path . -s tools/rig/render_poses.gd`.

---

## 6. Pipeline des modèles 3D (Tripo → jeu)

Les personnages sont générés sur **Tripo** : maillage, texture et squelette **Mixamo** (65 os,
identique sur tous les modèles — un seul retargeting pour tout le casting, présent et à venir).

```
new asset/<perso>.glb       dépôt brut (non versionné, voir .gitignore)
  ├─ python3 tools/rig/check_tripo.py "new asset"/*.glb       contrôle AVANT import
  ├─ python3 tools/rig/import_tripo.py "new asset"/*.glb --tous --reparer
  │     → assets/judokas/<perso>/{rig.glb, joints.json}
  └─ godot --path . -s tools/rig/render_poses.gd              vignettes de menu
```

`import_tripo.py` redresse le modèle (repère du jeu : +Z devant, sa gauche en +X), le normalise à
1,90 m (pieds à −0,95), réduit le squelette aux **28 os du jeu** (les quatre doigts Mixamo fondus dans
fingers1/fingers2), laisse les **os au repos sans rotation** pour que `rig_pose.gd` les pilote sans
changement, et ne garde que la couleur de base (9,5 Mo → 3,5 Mo par modèle).

**Les exports Tripo sont souvent défectueux**, et le défaut ne se voit pas dans un visualiseur, qui
affiche le modèle au repos. `check_tripo.py` détecte les trois cas (bon export : `os=65 bassin%≈5`) :
- *squelette plat* : les os n'ont aucune transformation, tout est tassé à l'origine ;
- *peau morte* : 68 à 100 % des sommets accrochés au seul bassin ;
- *fichier tronqué* : la fin du binaire est écrasée par du texte — **seul cas irrécupérable**, retélécharger.

`--reparer` rattrape les deux premiers : la pose de repos survit dans les *inverse bind matrices*, on la
relit là, puis **`tools/rig/autorig.py` recalcule les poids** (diffusion harmonique sur la surface). Sur
ces exports le squelette des matrices est en plus **tourné d'un quart de tour par rapport au maillage** :
`align_to_mesh()` essaie les quatre quarts de tour, garde celui qui place les extrémités dans la matière,
et tranche l'avant/arrière avec le sens des pieds (une silhouette debout est presque symétrique).

**On ne reteint pas les judogis.** Le blanc/bleu de compétition ne vaut que pour les quatre modèles
« basic », qui existent vraiment dans les deux couleurs ; les personnages nommés gardent le judogi
avec lequel ils ont été générés (`gi` dans skins.json). Une teinte automatique écrase les détails de
l'artwork, qui est justement ce qui fait la valeur des modèles (décision d'Hugo, 15/10/2026).
Pour un nouveau personnage, demander un **judogi blanc uni** à Tripo.

`tools/rig/preview.py` rend un judoka posé en PNG **sans Godot** (Python pur, ni numpy ni Pillow) :
`--pose garde|repos|torsion`, `--vue cote|face|dos`, `--planche` pour tout le casting.

Les outils TRELLIS (`normalize.py`, `decimate.py`, `rebuild_models.sh`, `gi_bleu.py`, `gi_blanc.py`)
restent pour les quatre modèles historiques (`homme_blanc`, `homme_bleu`, `femme_blanc`, `femme_bleu`).

## 7. Animations depuis une vidéo (rotoscopie)

C'est **le meilleur levier de qualité** : les chorégraphies dessinées (`throw_anims.gd`)
restent raides (uke « en planche »), alors qu'une projection relevée sur une vraie vidéo
donne tout de suite un mouvement juste.

### 7.1 La source : la chaîne Efficient Judo
Hugo a obtenu l'**autorisation de l'auteur** de https://www.youtube.com/@EfficientJudo
pour s'en servir de référence d'animation. 242 vidéos, une technique par vidéo, 25 à 45 s,
filmées **de profil sur fond neutre** — exactement le point de vue du jeu — et répétant la
projection plusieurs fois. Les **13 techniques du jeu y sont toutes couvertes** (99 démos
solo), et 109 vidéos portent sur des techniques qui n'y sont pas encore.

```bash
python3 tools/video/fetch_efficientjudo.py --liste    # ce que la chaîne contient
python3 tools/video/fetch_efficientjudo.py --jeu      # les 13 techniques, dans rushes/
```
Les vidéos vont dans `rushes/` (ignoré par git) : on ne versionne que les annotations.

`python3 tools/video/decouper.py` ouvre une découpe visuelle : lecture, avance image par
image, marqueurs début et fin, export du clip dans `rushes/clips/`. C'est **ffmpeg** qui
coupe (H.264, au cadre près) et non le navigateur, dont le WebM ré-encodé est refusé par
la plupart des services de mocap en ligne. Le serveur n'écoute qu'en local et ne sert que
le dossier des rushes.

### 7.0 Les 13 projections du jeu : pointées à la main (17/10/2026)
L'annotation automatique (§7.2) donnait des mouvements approximatifs ; Hugo a découpé un clip
par technique (`clips/<tech>.mp4`, uke en bleu à droite, tori en blanc) et **les 13 techniques
ont été repointées à la main**, comme le premier uchi-mata. Ce sont elles qui sont en jeu :
`tools/mocap/main/<tech>.json` → `retarget.py` → `data/anims/<tech>.json`.
Les annotations automatiques (`tools/mocap/<tech>_annot.json`) restent pour mémoire.

Méthode (outils dans `tools/mocap/`) :
```bash
ROTO=/tmp/roto tools/mocap/images_clip.sh seoi_nage      # images retournées (tori à gauche) 960×540 + planche numérotée
python3 tools/mocap/grille.py /tmp/roto/seoi_nage 240,40,780,540 1.0 20 25   # images quadrillées pour lire les pixels
#   → écrire tools/mocap/main/<tech>.json (aide : tools/mocap/main/aide.py, fonctions J, LY, write, shift)
python3 tools/mocap/superposition.py tools/mocap/main/seoi_nage.json /tmp/roto/seoi_nage /tmp/ov.png 0.42   # ← À REGARDER
python3 tools/mocap/retarget.py tools/mocap/main/seoi_nage.json
godot --path . -- --screen=demo --anim=seoi_nage          # contrôle en 3D, en mouvement
```
- 7 à 15 images clés : garde (fixe d0, viser 35–60 unités), entrée, rotation, chargement, envol,
  réception ; **on s'arrête à l'impact**, uke couché (`LY(x, rot, -9)`), tori reste debout.
- Pieds du côté loin ramenés sur le sol du côté caméra (la perspective les remonte de 30 à 60 px).
- Uke couché sur le dos **tête à gauche** : `rot = -1.57` et `"face": 1` (sinon il atterrit à plat
  ventre) ; tête à droite : `rot = 1.57`, `face -1`. `retarget.py` lit ce `face`, applique le demi-tour
  sur les 2 dernières clés en vol (`uke_twist`) et prend le tour le plus court vers la pose couchée.
- Caméra qui suit (sasae) : `shift(a, dx, dy)` recale chaque image sur le sol de la première.
- Lire les grilles avec soin : x = x0 + position_dans_l'image / échelle. Une erreur de lecture se
  voit tout de suite sur la superposition — c'est elle qu'il faut regarder, pas les chiffres.

### 7.2 La chaîne
```
rushes/efficientjudo/<tech>.mp4
  → python3 tools/mocap/auto_annot.py rushes/efficientjudo/*.mp4 --jobs 3
      → tools/mocap/<tech>_annot.json     (points 2D de tori et d'uke, image par image)
  → python3 tools/mocap/apercu.py tools/mocap/<tech>_annot.json /tmp/x.png   ← À REGARDER
  → python3 tools/mocap/retarget.py tools/mocap/<tech>_annot.json
      → data/anims/<tech>.json            (lu automatiquement par throw_anims.gd)
  → godot --path . -- --screen=art --anim=<tech>      contrôle dans le jeu
```

`auto_annot.py` remplace le pointage à la main (13 images par technique). Sept obstacles
l'ont rendu possible, chacun trouvé en regardant un ratage — et presque tous invisibles
sur une planche d'images fixes :

- **un détecteur en deux temps** (YOLO-pose). MediaPipe fusionne les deux silhouettes dès
  qu'elles se saisissent : il ne voyait deux judokas que sur 63 images sur 483.
- **garder les images où un seul judoka est vu.** En exigeant les deux, on perdait
  exactement la seconde qui nous intéresse — sur l'o-soto-gari, plus rien entre 23 et 27 s,
  c'est-à-dire toute la projection. Chaque judoka occupe un emplacement suivi par
  continuité du bassin, le manquant est comblé par interpolation : 558 images sur 558.
- **des longueurs de membres constantes** (`rigidifier`). La correction décisive : les
  détecteurs sont entraînés sur des gens debout, et sur un judoka en l'air, à l'envers et
  enchevêtré, une cuisse passe du simple au double d'une image à l'autre — uke arrivait à
  l'écran en pantin disloqué. On mesure les longueurs sur les images debout, puis on
  reconstruit chaque image en gardant les **directions** et en réimposant ces longueurs.
- **la continuité près/loin** (`stabiliser`). Le côté caméra était choisi image par image
  sur la confiance des points : les jambes s'échangeaient trois à cinq fois par projection.
- **le plan de profil** (`profil`). Le squelette du jeu est une vue de côté, rien d'autre ;
  un plan de trois quarts ne peut rien donner de bon. On mesure l'écartement des épaules
  et des hanches rapporté à la **longueur** du buste — superposées de profil, écartées de
  face — et la note de chaque répétition en tient compte. (Rapporter à la *hauteur* du
  buste faisait exploser la mesure dès qu'un judoka passait à l'horizontale.)
- **la projection retenue est celle dont le kumikata qui la précède est le meilleur**, et
  sa première image est cette garde : c'est elle qui fixe `d0`, et `throw_anims.gd` étire
  toute la chorégraphie par `d / d0`. Des fenêtres ouvertes au milieu de la projection
  donnaient `d0` nul ou négatif, donc un facteur d'étirement de 55 : les judokas partaient
  hors de l'écran. d0 doit valoir 36 à 70 unités.
- **on s'arrête à l'impact.** L'instructeur suit sa projection au sol pour contrôler uke ;
  en gardant la suite, tori finissait couché sur lui à chaque technique.

Et un piège de calibrage : le seuil « le pied touche le tatami » vaut 15 % de la hauteur
de bassin, soit `7.05 / s` dans retarget.py (`s` = 47 / hauteur_px). Écrit `0.15 / s`, il
tombait à un demi-pixel : plus personne n'était jamais au sol et le couple entier flottait
à l'horizontale au-dessus du tapis.

**Toujours regarder le résultat avant de le montrer** (`apercu.py --toutes` pour les
annotations, `--screen=demo` pour l'animation en mouvement, et une capture en **pleine
résolution** : c'est la seule qui a révélé le pantin disloqué et le couple flottant).
`--debut <secondes>`, `--uke 0|1` et `--recul` forcent la fenêtre à la main.

Le suivi vidéo est mis en cache (`rushes/.../.pistes/`) : la détection coûte une minute
trente par vidéo quand le réglage de la fenêtre se reprend dix fois. `calibrer.py` affiche
image par image l'écart entre les judokas en unités de jeu, leur état et le profil.

Autres pistes conservées : `tools/blender/` (scène toon), `tools/sprites_ia/prepare.py`,
`docs/PIPELINE_ANIMATION.md` (tournage au dojo).

## 8. Arguments du jeu (après `--`)

| Argument | Effet |
| --- | --- |
| `--screen=title\|menu\|match\|customize\|select\|vs\|tournament\|results\|options\|online\|dojo\|challenges\|art\|demo\|lineup\|bake` | écran de départ |
| `--p1build=<id> --p2build=<id>` | judokas (id de légende : lame, mur, seoi, kesa…) |
| `--seed=<n> --level=1..3` | graine et niveau IA |
| `--capture=<dossier>` | mode capture (quitte à la fin) ; combat : `--ticks=a,b,c --max=n --until=t --events --settle=n` ; menus : `--frames=n --nav=down,accept --name=x` |
| `--skip=N` / `--skip_to=<tick>` | avance rapide du combat avant d'enregistrer |
| `--eventlog=f.tsv` | journal image / manche / tick / événement (montage vidéo) |
| `--quit_results=N` | quitte N images après les résultats |
| `--demo=f.json` | pilotage scripté des menus (vidéos) |
| `--lesson=<id>` / `--training --partner=garde` | leçon du dojo / entraînement libre |
| `--dessin` / `--decoupe` | artwork découpé au lieu des judokas 3D (affichés par défaut) |
| `--decor=<id>` | décor imposé (`arena`, `dojo`, `crepuscule`, `dessin`) |
| `--ia` | combat IA contre IA (démonstration à regarder) |
| `--models3d=<dossier> --models3d_who=a,b` | autre dossier / autres modèles 3D (la 3D est affichée par défaut) |
| `--anim=<tech>` (`--zoom`, `--ground`, `--count`) | (écran art) planche d'une chorégraphie |
| `--screen=demo [--anim=<tech>]` | démonstration animée des projections, en 3D, défilement automatique |
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

## 12. État au 20/10/2026 et suite

Fait (20/10) : kumikata et ne-waza 3D repris (§5.3 bis) — mains posées sur le judogi par cinématique
inverse, couple resserré à portée de bras, posture de combat, garde droitier / gaucher, vrille des
épaules ; au sol, corps sur le dos et tori sur le flanc d'uke. Vidéo de combat (7 combats, 10 légendes)
envoyée à Hugo ; caméra qui garde uke dans le champ après une projection près du bord.
Fait (17/10) : les 13 projections repointées à la main sur les clips d'Hugo (§7.0), réception d'uke
corrigée (plus de redressement ni de tête sous le tapis), projections près du bord gardées dans le champ.
Fait (18/10, nuit) : uke se retourne en vol (et non à l'impact), contres animés par chorégraphie filmée,
ne-waza lisible (barre sous les corps), fondu debout ↔ sol, `smoke_test` compile tous les scripts
(une erreur dans models3d.gd bloquait les captures sans message), captures de référence régénérées.

Fait (15/10) : retour à la 3D avec le casting Tripo (§6), décors en image, jeu au clavier, arbitre 3D.

Fait (13/10) : judokas dessinés par découpage à partir de l'artwork d'Hugo (aujourd'hui solution de repli).

Fait avant : jeu jouable de bout en bout (titre → menu → tournoi / versus / dojo / défis → combat debout et sol →
résultats), BO3, 10 légendes, personnalisation complète, son, judokas 3D partout (combat, dojo, menus),
mains articulées, squelette 28 os avec colonne courbée et demi-tours progressifs, uchi-mata filmé,
vidéos de présentation.

À faire / pistes :
- Une vidéo dédiée pour chacun des 5 contres (aujourd'hui `MOCAP_ALIAS`), puis la rotoscopier (§7.0).
- Repli dessiné (`--decoupe`) : seule la planche de l'homme existe ; les légendes féminines y
  s'affichent avec l'homme. Il faudrait une planche de morceaux femme (même prompt, §5.0).
- Orientation de la main vers la prise (poignet), vrille d'avant-bras.
- Ne-waza : poses encore figées (une par technique) ; transitions entre elles et lutte au sol à animer.
- Tester le **versus à deux manettes** en vrai.
- **En ligne** : rollback prêt côté simulation, réseau à brancher (phase 8 du GDD).
