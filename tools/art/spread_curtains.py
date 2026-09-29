# -*- coding: utf-8 -*-
"""Slide the two curtains of curtains_overlay.png outward (patch 0.119).

The image model was asked for curtains filling 14% of each edge and drew 22%,
which crowds the machines and hangs over Ace. Rather than re-roll the art,
this moves each half outward by the difference and crops what falls off the
edge (plain fabric). Deterministic, so the manifest entry names it as a post
step and re-generation stays reproducible: run it once after generate_art.
"""
import sys
from PIL import Image
import numpy as np

PATH = "assets/backgrounds/curtains_overlay.png"
TARGET = 0.14   # each curtain's inner extent, as a fraction of the width

im = Image.open(PATH).convert("RGBA")
a = np.array(im)[:, :, 3]
h, w = a.shape
cols = (a > 8).any(axis=0)
mid = w // 2
left_inner = max(i for i in range(mid) if cols[i])
right_inner = min(i for i in range(mid, w) if cols[i])
shift_l = max(0, left_inner - int(w * TARGET))
shift_r = max(0, (w - right_inner) - int(w * TARGET))
if shift_l == 0 and shift_r == 0:
    print("curtains already at or inside %.0f%%; nothing to do" % (TARGET * 100))
    sys.exit(0)
out = Image.new("RGBA", (w, h), (0, 0, 0, 0))
out.paste(im.crop((0, 0, mid, h)), (-shift_l, 0))
out.paste(im.crop((mid, 0, w, h)), (mid + shift_r, 0))
out.save(PATH)
print("left moved %d px, right moved %d px; curtains now reach %.1f%% per side"
      % (shift_l, shift_r, 100.0 * (left_inner - shift_l) / w))
