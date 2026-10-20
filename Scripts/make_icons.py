#!/usr/bin/env python3
# Regenerates Resources/AppIcon.icns and the MenuBarIcon template PNGs from the cleaned artwork:
# AppIconArt.png (the lens and cursor as light on black, added onto a drawn glass tile) and
# MenuBarArt.png (the glyph's alpha). Needs Pillow and numpy. Usage: Scripts/make_icons.py
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

res = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'Resources')
R = 4  # supersampling for smooth shape edges


def rounded(size, inset, radius, **kw):
    img = Image.new('RGBA' if 'outline' in kw else 'L', (size * R, size * R), 0)
    ImageDraw.Draw(img).rounded_rectangle((inset * R, inset * R, (size - inset) * R - 1, (size - inset) * R - 1),
                                          radius=radius * R, **kw)
    return img.resize((size, size), Image.LANCZOS)


# App icon: 824 px tile in a 1024 canvas (the macOS grid), dark glass with a soft diagonal sheen.
T = 824
y = np.linspace(0, 1, T)[:, None, None]
tile = np.array([80, 58, 52]) * (1 - y) + np.array([26, 16, 14]) * y  # BGR-free: stored as RGB below
tile = tile[..., ::-1] * np.ones((T, T, 1))
xx, yy = np.meshgrid(np.arange(T), np.arange(T))
sheen = np.clip(1 - np.abs((xx + yy * 0.55) - T * 0.95) / (T * 0.18), 0, 1) * np.clip(1 - yy / T * 1.4, 0, 1)
tile += sheen[..., None] * 18

art = np.asarray(Image.open(os.path.join(res, 'AppIconArt.png')).convert('RGB')).astype(float)
scale = T * 0.80 / max(art.shape[:2])
art_img = Image.fromarray(art.astype(np.uint8)).resize(
    (round(art.shape[1] * scale), round(art.shape[0] * scale)), Image.LANCZOS)
art = np.asarray(art_img).astype(float)
oy, ox = (T - art.shape[0]) // 2, (T - art.shape[1]) // 2
tile[oy:oy + art.shape[0], ox:ox + art.shape[1]] += art  # the artwork is light, so add it

tile = Image.fromarray(np.clip(tile, 0, 255).astype(np.uint8)).convert('RGBA')
mask = rounded(T, 0, 185, fill=255)
tile.putalpha(mask)
tile = Image.alpha_composite(tile, rounded(T, 3, 182, outline=(180, 200, 255, 70), width=4 * R))
icon = Image.new('RGBA', (1024, 1024), (0, 0, 0, 0))
icon.paste((0, 0, 0, 90), (100, 112), mask)
icon = icon.filter(ImageFilter.GaussianBlur(14))
icon.alpha_composite(tile, (100, 100))
icon.save(os.path.join(res, 'AppIcon.icns'),
          sizes=[(16, 16), (32, 32), (64, 64), (128, 128), (256, 256), (512, 512), (1024, 1024)])

# Menu bar template image: black glyph, 18 pt tall.
glyph = Image.open(os.path.join(res, 'MenuBarArt.png')).getchannel('A')
for s, name in ((1, 'MenuBarIcon.png'), (2, 'MenuBarIcon@2x.png')):
    w = round(glyph.width * 18 / glyph.height) * s
    a = glyph.resize((w, 18 * s), Image.LANCZOS)
    out = Image.new('RGBA', a.size, (0, 0, 0, 0))
    out.putalpha(a)
    out.save(os.path.join(res, name))
