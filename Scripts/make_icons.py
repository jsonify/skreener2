#!/usr/bin/env python3
# Regenerates Resources/AppIcon.icns and the MenuBarIcon template PNGs from Resources/IconArt.png
# (application icon on the left, menu bar glyph on the right). Needs Pillow and numpy.
# Usage: Scripts/make_icons.py
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

res = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'Resources')
im = Image.open(os.path.join(res, 'IconArt.png')).convert('RGB')

# App icon: square crop of the artwork, masked to the macOS rounded rect (824 of 1024, plus a shadow).
R = 4  # supersampling for smooth mask edges
art = im.crop((86, 95, 413, 422)).resize((824, 824), Image.LANCZOS).convert('RGBA')
mask = Image.new('L', (824 * R, 824 * R), 0)
ImageDraw.Draw(mask).rounded_rectangle((0, 0, 824 * R - 1, 824 * R - 1), radius=185 * R, fill=255)
mask = mask.resize((824, 824), Image.LANCZOS)
art.putalpha(mask)
rim = Image.new('RGBA', (824 * R, 824 * R), (0, 0, 0, 0))
ImageDraw.Draw(rim).rounded_rectangle((3 * R, 3 * R, 821 * R, 821 * R), radius=182 * R,
                                      outline=(180, 200, 255, 70), width=4 * R)
art = Image.alpha_composite(art, rim.resize((824, 824), Image.LANCZOS))
shadow = Image.new('RGBA', (1024, 1024), (0, 0, 0, 0))
shadow.paste((0, 0, 0, 90), (100, 112), mask)
icon = shadow.filter(ImageFilter.GaussianBlur(14))
icon.alpha_composite(art, (100, 100))
icon.save(os.path.join(res, 'AppIcon.icns'),
          sizes=[(16, 16), (32, 32), (64, 64), (128, 128), (256, 256), (512, 512), (1024, 1024)])

# Menu bar template image: the light glyph's brightness becomes alpha on black.
g = np.asarray(im.crop((586, 81, 944, 432)).convert('L')).astype(float)
alpha = np.clip((g - 45) / (215 - 45), 0, 1)
glyph = np.zeros(g.shape + (4,), np.uint8)
glyph[..., 3] = (alpha * 255).round()
glyph = Image.fromarray(glyph, 'RGBA')
for scale, name in ((1, 'MenuBarIcon.png'), (2, 'MenuBarIcon@2x.png')):
    w = round(glyph.width * 18 / glyph.height) * scale
    glyph.resize((w, 18 * scale), Image.LANCZOS).save(os.path.join(res, name))
