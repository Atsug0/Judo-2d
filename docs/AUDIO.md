# Son

Tout le son est **généré par synthèse** : `python3 tools/audio/gen_audio.py` (numpy, scipy et ffmpeg). Aucun fichier externe, aucune licence. Le résultat est déterministe.

- `audio/sfx/*.wav` : bruitages, voix et foule (mono, 44,1 kHz).
- `audio/music/*.ogg` : musiques `menu`, `match`, `dojo` (en boucle) et `victory` (jingle).
- `scripts/audio/sound.gd` : autoload `Sound`.
  - Bus Music et SFX, limiteur sur le master.
  - Pool de 24 lecteurs, musique en fondu enchaîné.
  - Foule dont le volume suit l'intensité du combat.
- Les volumes des options (général, musique, effets) s'appliquent en direct.

Le son est purement cosmétique. Il ne touche jamais la simulation, donc le déterminisme et le futur rollback en ligne ne sont pas concernés.

## Qui déclenche quoi

| Moment | Sons |
|---|---|
| Navigation menus | `ui_move`, `ui_accept`, `ui_back`, `ui_tab` (coupés pendant le combat, sauf en pause) |
| Écran VS | `whoosh_2` puis `vs_slam` quand le VS claque |
| Saisie, casse de saisie | `grip_0..3`, `grip_break_0..1` |
| Attaque | `whoosh_1` + `kiai_<joueur>_0..2` |
| Bloque, stoppé | `block` |
| Contre | `counter` + `crowd_ooh` |
| Projection | `whoosh_2`, puis à l'impact `fall_heavy` (ippon) ou `fall_medium` + acclamation |
| Annonces | `ref_hajime` + taiko, `ref_matte` + claquoir, `ref_ippon`/`ref_wazaari` + stinger, `ref_osaekomi`, `ref_toketa`, `ref_shido` + buzzer, `ref_soremade` + gong |
| Osaekomi | `tock` à chaque seconde, de plus en plus aigu |
| Sol | `rustle_0..2` en continu, `grunt_<joueur>` sur une tentative de soumission, `tap_out` sur l'abandon |
| Chrono | `tick` pendant les 10 dernières secondes |
| Pas | `step_0..3` quand un judoka se déplace |

## Remplacer par de vrais enregistrements (recommandé pour les voix)

Les voix synthétiques (arbitre, kiai) restent robotiques : ce sont des placeholders. Le plus simple est de les enregistrer au club :

1. **Matériel** : un téléphone suffit. Mets-le à 30 cm de la bouche, dans une pièce calme, puis exporte en WAV ou en M4A.
2. **Arbitre** : dis chaque appel 3 fois, avec une voix posée et forte. Les appels : « Hajime », « Matte », « Ippon », « Waza-ari », « Osaekomi », « Toketa », « Shido », « Sore-made ».
3. **Kiai** : 3 kiai par personne, un par variante (court, moyen, long). Ajoute 1 souffle d'effort au sol.
4. **Chutes** : pose le téléphone au bord du tatami et fais quelques ukemi (avant, arrière, côté). C'est le son le plus important du jeu.
5. **Judogi** : saisies, casses de saisie et froissements au sol, en enregistrant près du tissu.

Il suffit de **garder les mêmes noms de fichiers** (`ref_hajime.wav`, `kiai_0_1.wav`, `fall_heavy.wav`…). Le jeu les prend sans changer une ligne de code. Pour ajouter une variante, ajoute `nom_4.wav` à côté de `nom_0..3` : elle est tirée au hasard automatiquement.

Pour nettoyer une prise :

```
ffmpeg -i prise.m4a -ac 1 -ar 44100 -af "silenceremove=1:0:-45dB,areverse,silenceremove=1:0:-45dB,areverse,loudnorm" ref_hajime.wav
```
