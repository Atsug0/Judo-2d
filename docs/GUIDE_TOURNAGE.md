# Guide de tournage au dojo (à imprimer)

## Avant la séance

- [ ] Accord du club pour filmer
- [ ] Partenaire de gabarit proche (± 10 cm, catégories voisines)
- [ ] Trépied, téléphone chargé + stockage libre (≈ 30 Go pour 247 prises en 1080p60)
- [ ] Judogis blanc **et** bleu
- [ ] Scotch de couleur pour les repères au sol
- [ ] Cette liste imprimée, un crayon

## Installation (10 minutes)

1. Trépied **perpendiculaire** à l'axe du combat, objectif à **hauteur de hanche**.
2. Recule jusqu'à voir les deux judokas **en entier, chute comprise** (laisse de la marge au-dessus).
3. Réglages : **60 i/s**, 1080p ou 4K, mise au point et exposition **verrouillées**.
4. Scotch au sol : position de départ de tori et d'uke.
5. Filme 5 secondes de tatami vide (utile pour caler la scène).

## Pendant la séance

- Annonce le nom du plan à voix haute avant chaque prise (ça aide au tri).
- Une technique = **lente** puis **vitesse réelle**, côté droitier puis gaucher.
- Ajoute **1 raté** (uke résiste) et **1 waza-ari** (chute sur le côté).
- Inverse les rôles : chaque technique faite par vous deux.
- Ne bouge jamais le trépied au milieu d'une série.

## Ordre conseillé (≈ 2 h 30)

| Bloc | Plans | Durée |
| --- | --- | --- |
| Base | salut, garde, déplacements, saisies, casser la prise | 20 min |
| Kuzushi | avant, arrière, côté | 10 min |
| Techniques debout | les 13 techniques | 60 min |
| Contres | ura-nage, utsuri-goshi, uchi-mata-sukashi, o-soto-gaeshi, tsubame-gaeshi | 20 min |
| Enchaînements | les 5 enchaînements | 15 min |
| Chutes, ratés, blocages | ukemi, attaque ratée, blocage | 10 min |
| Sol | transition, 6 techniques, sortie | 25 min |
| Fin | victoire, défaite, salut | 5 min |

La liste détaillée (avec le nombre de prises par plan) : `data/shotlist.json`.
Après la séance : `python3 tools/video/check_rushes.py rushes` dit ce qui manque.

## Nommage

`<id>_<droitier|gaucher|face>_prise<N>.mp4` — exemple : `tech_uchi_mata_gaucher_prise2.mp4`
