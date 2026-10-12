# Modèles 3D bruts (TRELLIS)

Modèles générés par Hugo avec TRELLIS (Hugging Face, démo officielle microsoft/TRELLIS) à partir
des vues `pose_t.png` de `art/personnages/<judoka>/`. Ce sont les **sources** des judokas du jeu :
on ne les charge pas directement, on les fait passer par `tools/rig/rebuild_models.sh`
(normalisation → rig automatique → allègement → `assets/judokas/<judoka>/rig.glb`).

| Fichier | Judoka du jeu | Squelette (repos) |
| --- | --- | --- |
| `homme_blanc.glb` | `assets/judokas/homme_blanc` | `tools/rig/judoka_ia_joints.json` |
| `homme_bleu.glb` | `assets/judokas/homme_bleu` | `tools/rig/judoka_ia_bleu_joints.json` |
| `femme_bleu.glb` | `assets/judokas/femme_bleu` | `tools/rig/judokate_ia_joints.json` |

Femme en judogi blanc : pas encore de modèle dédié. `assets/judokas/femme_blanc/modele.json`
emprunte le rig de `femme_bleu` avec une texture repeinte (`tools/rig/gi_blanc.py`).
Pour la remplacer : générer `femme_blanc.glb` ici, ajouter une ligne dans `rebuild_models.sh`
(squelette : copie de `judokate_ia_joints.json`, à recaler si les proportions diffèrent),
puis supprimer `modele.json` et `texture.png`.
