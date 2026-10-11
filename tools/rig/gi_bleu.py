#!/usr/bin/env python3
"""Teinte le judogi blanc d'une texture en bleu (pour uke), en gardant les ombres et les plis.
Les pixels peu saturés et clairs (le judogi) passent au bleu ; peau, cheveux et ceinture restent.

    python3 tools/rig/gi_bleu.py texture_0.png texture_bleue.png
"""
import sys

import numpy as np
from PIL import Image

im = np.asarray(Image.open(sys.argv[1]).convert("RGB")).astype(np.float32) / 255.0
mx = im.max(axis=2)
mn = im.min(axis=2)
sat = (mx - mn) / np.maximum(mx, 1e-4)
gi = np.clip((0.22 - sat) / 0.10, 0, 1) * np.clip((mx - 0.35) / 0.2, 0, 1)
blue = np.array([0.13, 0.33, 0.86], dtype=np.float32)
shade = (mx / 0.95) ** 1.3
target = np.clip(blue[None, None, :] * shade[..., None] * 1.15 + 0.04 * shade[..., None], 0, 1)
out = im * (1 - gi[..., None]) + target * gi[..., None]
Image.fromarray((out * 255).astype(np.uint8)).save(sys.argv[2], optimize=False, compress_level=3)
print("judogi bleu :", sys.argv[2], f"({gi.mean() * 100:.0f} % de la texture)")
