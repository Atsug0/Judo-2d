"""Aide : écrit tools/mocap/main/<tech>.json à partir d'une liste de clés compacte."""
import os
import json
DOC = ("Rotoscopie à la main ({tech}, clips/{tech}.mp4, Efficient Judo, utilisé avec accord) : images {ori}"
       "réduites en 960×540, {fps} i/s, numéros d'image du clip. Points : H tête, N base du cou, P bassin, "
       "Kn/An genou/cheville côté caméra, Kf/Af côté opposé (pieds ramenés sur le sol du côté caméra), "
       "Wn/Wf poignets. face : +1 regarde vers la droite. Tori est à gauche au départ.")
def J(H, N, P, Kn, An, Kf, Af, Wn, Wf, face):
    return {"face": face, "H": H, "N": N, "P": P, "Kn": Kn, "An": An, "Kf": Kf, "Af": Af, "Wn": Wn, "Wf": Wf}
def LY(x, r, y):
    return {"lying": True, "x_px": x, "rot": r, "y_units": y}
def write(tech, fps, floor, hip, F, flipped=True, extra=None):
    ori = "retournées horizontalement (tori en blanc à gauche) et " if flipped else "dans le sens d'origine (tori en blanc à gauche) et "
    ann = {"_doc": DOC.format(tech=tech, ori=ori, fps=fps), "source": f"clips/{tech}.mp4", "start_s": 0.0, "fps": fps,
           "floor_y": floor, "hip_height_px": hip, "tech": tech, "flip": flipped,
           "frames": [{"f": f, "p": p, "tori": t, "uke": u} for f, p, t, u in F]}
    if extra: ann.update(extra)
    json.dump(ann, open(os.path.join(os.path.dirname(__file__), f"{tech}.json"), "w"), indent=1, ensure_ascii=False)


def shift(a, dx, dy):
    """Recale un judoka quand la caméra a bougé (panoramique / bascule) : décalage en pixels."""
    if a.get("lying"):
        b = dict(a); b["x_px"] = a["x_px"] + dx; return b
    b = dict(a)
    for k in ("H", "N", "P", "Kn", "An", "Kf", "Af", "Wn", "Wf"):
        b[k] = [a[k][0] + dx, a[k][1] + dy]
    return b
