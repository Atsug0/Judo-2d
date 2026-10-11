# Pipeline animation : des vidéos du dojo aux sprites du jeu

Ce guide te mène de la vidéo filmée au dojo jusqu'au judoka animé dans le combat.
Tout est déjà branché dans le jeu : il suffit de remplir le dossier `animations/`.

```
vidéo dojo ──► rushes/ ──► Blender (scène toon calée sur la vidéo) ──► animations/<perso>/ ──► jeu
                 │                                                          ▲
                 └── extract_frames.py (images de référence) ───────────────┘ (option rotoscopie)
```

## 0. Ce qu'il te faut

| Outil | Rôle | Version |
| --- | --- | --- |
| Godot | Le jeu | 4.4 |
| Blender | Animation 3D et rendu toon | 4.2 ou plus |
| ffmpeg | Découpe des vidéos | n'importe quelle version récente |
| Python 3 | Scripts d'outillage | 3.10 ou plus |

## 1. Tourner

La liste complète des plans est dans `data/shotlist.json` (48 plans, 247 prises).
Elle est générée à partir des techniques du jeu : chaque plan indique les animations qu'il produit.

Règles de tournage :

- Caméra **fixe sur trépied**, **parfaitement de profil**, objectif à hauteur de hanche.
- **60 i/s**, 1080p minimum. Bonne lumière, fond dégagé.
- Les deux judokas **entiers dans le cadre, chute comprise**.
- Judogis **blanc et bleu** (le jeu distingue tori et uke par la couleur).
- Repère au sol au scotch : on part toujours du même endroit.
- Pour chaque technique : 1 entrée lente, puis vitesse réelle, des deux côtés ;
  plus 1 prise ratée (uke résiste) et 1 waza-ari (chute sur le côté).

Nommage des fichiers : `<id>_<droitier|gaucher|face>_prise<N>.mp4`
(ex. `tech_seoi_nage_droitier_prise3.mp4`). Les `id` sont ceux de `shotlist.json`.

## 2. Vérifier les rushes

Dépose les vidéos dans `rushes/` puis :

```
python3 tools/video/check_rushes.py rushes
```

Le script écrit `rushes/RAPPORT.md` : progression, plans manquants, fichiers mal nommés.

## 3. (Option) Extraire des images de référence

Pour relire un mouvement image par image ou dessiner par-dessus :

```
python3 tools/video/extract_frames.py rushes/tech_seoi_nage_droitier_prise3.mp4 --start 1.2 --end 2.9
```

Sortie dans `animations/_frames/…` : les images à 12 i/s + `planche.png` (planche-contact).
`--mirror` fabrique un côté gaucher à partir d'un droitier.

## 4. Animer dans Blender

1. Ouvre Blender avec ton modèle de judoka riggé (Rigify ou Mixamo).
   Range les objets de tori dans la collection `TORI` et ceux d'uke dans `UKE`
   (noms d'objets commençant par `tori…` / `uke…`).
2. Prépare la scène :

   ```
   blender scenes/seoi_nage.blend --python tools/blender/setup_scene.py -- --video rushes/tech_seoi_nage_droitier_prise3.mp4
   ```

   Le script crée la caméra orthographique de profil (cadrage identique au jeu),
   l'éclairage, les matériaux toon (`TOON_gi_blanc`, `TOON_gi_bleu`, `TOON_peau_*`, `TOON_ceinture`),
   les contours d'encre, et met la vidéo en fond de caméra.
3. Assigne les matériaux toon à tes maillages.
4. Anime en calant sur la vidéo (la mocap IA peut dégrossir tori ; uke se fait plutôt à la main).
   **Tori regarde vers +X au début**, ses pieds à l'origine (repère `PIEDS_TORI`).
5. Enregistre le `.blend` dans `scenes/`.

Échelle : 1,80 m dans Blender = 100 unités de jeu = 400 px dans les sprites.

## 5. Rendre les sprites

Une animation :

```
blender scenes/seoi_nage.blend --background --python tools/blender/render_sprites.py -- \
    --anim throw/seoi_nage --character hugo_blanc --uke-character kenji_bleu --start 30 --end 110 --frames 12
```

Toutes d'un coup (liste dans `tools/blender/render_list.json`) :

```
python3 tools/blender/batch_render.py
```

Tori et uke sont rendus séparément, **avec la même caméra**, pour que la projection reste synchronisée.
Le `manifest.json` de chaque personnage est mis à jour automatiquement.

## 6. Voir le résultat dans le jeu

```
godot --path . -- --screen=match --sprites=hugo_blanc
```

Si une animation manque (par exemple une technique pas encore tournée), le jeu retombe
automatiquement sur le dessin placeholder pour celle-là : tu peux avancer technique par technique.

Pour tester la chaîne sans Blender, des sprites placeholder peuvent être « cuits » :

```
godot --path . -- --screen=bake --capture=/tmp/x
godot --path . -- --screen=match --sprites=placeholder
```

## Raccourci : une vidéo → la technique animée dans le jeu (sans Blender)

Première technique faite ainsi : **uchi-mata** (vidéo « Uchi-mata - Demo », utilisée avec accord).

1. Repérer la technique dans la vidéo et extraire les images à 12 i/s.
2. Rotoscopie : pour chaque image clé, noter en pixels la tête, la base du cou, le bassin,
   genoux, chevilles et poignets de tori et d'uke (côté caméra / côté opposé), et le sens du regard.
   Exemple complet : `tools/mocap/uchi_mata_annot.json`.
3. Reporter sur le squelette du jeu (on garde les angles, pas les longueurs, pour respecter
   les proportions du dessin) :

   ```
   python3 tools/mocap/retarget.py tools/mocap/uchi_mata_annot.json
   ```

   Écrit `data/anims/uchi_mata.json`. Le jeu l'utilise automatiquement à la place de la
   chorégraphie dessinée (`scripts/view/throw_anims.gd`). Planche de contrôle :
   `godot --path . -- --screen=art --anim=uchi_mata`.
4. Pour la 3D : `blender --python tools/blender/import_mocap.py -- --anim data/anims/uchi_mata.json`
   crée deux mannequins articulés animés (collections TORI / UKE), avec une armature par
   judoka à reprendre sur un vrai modèle riggé, puis `render_sprites.py` comme ci-dessus.

## Noms des animations attendues

| Animation | Contenu | Images |
| --- | --- | --- |
| `idle` | garde, en boucle | 8 |
| `walk_fwd` | déplacement avant, en boucle | 8 |
| `entry/<technique>` | entrée de la technique (tori seul) | 6 |
| `throw/<technique>/tori` | projection, tori | 12 |
| `throw/<technique>/uke` | projection, uke (même caméra) | 12 |
| `throw/<contre>/tori` et `/uke` | contres (ura_nage, o_soto_gaeshi…) | 12 |

Identifiants des techniques : `data/techniques.json`.

## Format d'un personnage

```
animations/hugo_blanc/
  manifest.json
  idle/0001.png …
  throw__seoi_nage__tori/0001.png …
```

```json
{
  "character": "hugo_blanc",
  "unit_px": 4.0,
  "fps": 12,
  "anims": {
    "idle": {"dir": "idle", "count": 8, "loop": true, "pivot": [560, 650], "anchor": "self"},
    "throw/seoi_nage/tori": {"dir": "throw__seoi_nage__tori", "count": 12, "pivot": [560, 650], "anchor": "tori"}
  }
}
```

`pivot` = position des pieds (de tori pour une projection) dans l'image.
