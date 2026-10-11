#!/usr/bin/env python3
"""Passe un judogi bleu en blanc dans une texture (en attendant un modèle blanc dédié) :
les pixels bleus saturés deviennent blanc cassé, ombres et plis conservés.

    python3 tools/rig/gi_blanc.py texture_bleue.png texture_blanche.png
"""
import sys

import numpy as np
from PIL import Image

im = np.asarray(Image.open(sys.argv[1]).convert("RGB")).astype(np.float32) / 255.0
r, g, b = im[..., 0], im[..., 1], im[..., 2]
mx = im.max(axis=2)
mn = im.min(axis=2)
sat = (mx - mn) / np.maximum(mx, 1e-4)
blue = (b >= mx - 1e-6) & (b > r * 1.25) & (b > g * 1.1) & (sat > 0.35)
k = np.clip((sat - 0.35) / 0.15, 0, 1) * blue
ref = np.percentile(mx[blue], 95) if blue.any() else 1.0
v = np.clip(mx / ref, 0, 1) ** 0.8
white = np.stack([0.42 + 0.56 * v, 0.42 + 0.56 * v, 0.46 + 0.54 * v], axis=-1)
out = im * (1 - k[..., None]) + white * k[..., None]
Image.fromarray((np.clip(out, 0, 1) * 255).astype(np.uint8)).save(sys.argv[2])
print("judogi blanc :", sys.argv[2], f"({k.mean() * 100:.0f} % de la texture)")
