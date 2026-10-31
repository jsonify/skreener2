#!/usr/bin/env python3
# Draws Resources/AppIcon.icns and the MenuBarIcon template PNGs in the SK-1 look (#353): a cream device with an olive
# LCD showing crop corners over a cream knob, a speaker grille and an orange key. The colours are Retro.swift's.
# Needs Pillow. Usage: Scripts/make_icons.py
import math
import os
from PIL import Image, ImageChops, ImageDraw, ImageFilter

res = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'Resources')
R = 2  # supersampling for the app icon's edges


def rgb(h):
    return (h >> 16) & 0xff, (h >> 8) & 0xff, h & 0xff


def gradient(w, h, stops):
    """A vertical gradient through `stops` (top to bottom, evenly spaced), as RGBA."""
    col = Image.new('RGBA', (1, h))
    for y in range(h):
        t = y / max(h - 1, 1) * (len(stops) - 1)
        i = min(int(t), len(stops) - 2)
        f = t - i
        a, b = rgb(stops[i]), rgb(stops[i + 1])
        col.putpixel((0, y), tuple(round(a[k] * (1 - f) + b[k] * f) for k in range(3)) + (255,))
    return col.resize((w, h))


def rounded_mask(size, box, radius):
    m = Image.new('L', size, 0)
    ImageDraw.Draw(m).rounded_rectangle(box, radius=radius, fill=255)
    return m


def layer(img, size, xy, mask):
    """`img` masked by `mask`, placed at `xy` on a transparent canvas of `size`."""
    img = img.copy()
    img.putalpha(ImageChops.multiply(img.getchannel('A'), mask))
    out = Image.new('RGBA', size, (0, 0, 0, 0))
    out.paste(img, xy)
    return out


def shadow(size, box, radius, alpha, blur, dy):
    s = Image.new('RGBA', size, (0, 0, 0, 0))
    x0, y0, x1, y1 = box
    ImageDraw.Draw(s).rounded_rectangle((x0, y0 + dy, x1, y1 + dy), radius=radius, fill=(0, 0, 0, alpha))
    return s.filter(ImageFilter.GaussianBlur(blur))


def well(canvas, box, radius, top, bottom, inner_alpha):
    """A sunken tray: a light lip under it, its floor, and a shadow inside under its top edge."""
    x0, y0, x1, y1 = box
    w, h = x1 - x0, y1 - y0
    lip = Image.new('RGBA', canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(lip).rounded_rectangle((x0, y0 + 3 * R, x1, y1 + 3 * R), radius=radius, fill=(255, 255, 255, 200))
    canvas.alpha_composite(lip)
    mask = rounded_mask((w, h), (0, 0, w - 1, h - 1), radius)
    canvas.alpha_composite(layer(gradient(w, h, [top, bottom]), canvas.size, (x0, y0), mask))
    ring = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(ring).rounded_rectangle((-30 * R, -30 * R + 8 * R, w + 30 * R, h + 30 * R), radius=radius + 30 * R,
                                           outline=(0, 0, 0, inner_alpha), width=34 * R)
    ring = ring.filter(ImageFilter.GaussianBlur(7 * R))
    canvas.alpha_composite(layer(ring, canvas.size, (x0, y0), mask))


def key(canvas, box, radius, top, bottom, skirt, highlight):
    """A raised key: the shadow it casts, its skirt, its face and a light line along its top edge."""
    x0, y0, x1, y1 = box
    w, h = x1 - x0, y1 - y0
    canvas.alpha_composite(shadow(canvas.size, box, radius, 70, 9 * R, 16 * R))
    ImageDraw.Draw(canvas).rounded_rectangle((x0, y0 + 12 * R, x1, y1 + 12 * R), radius=radius, fill=rgb(skirt) + (255,))
    mask = rounded_mask((w, h), (0, 0, w - 1, h - 1), radius)
    canvas.alpha_composite(layer(gradient(w, h, [top, bottom]), canvas.size, (x0, y0), mask))
    glow = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(glow).rounded_rectangle((0, 0, w - 1, h - 1), radius=radius, outline=(255, 255, 255, highlight),
                                           width=3 * R)
    glow.putalpha(ImageChops.multiply(glow.getchannel('A'), gradient(w, h, [0xffffff, 0x000000]).getchannel('R')))
    canvas.alpha_composite(layer(glow, canvas.size, (x0, y0), mask))


def knob(canvas, cx, cy, r):
    """A round cream knob seen from above: tick marks around it, the shadow it casts, a darker skirt, a domed face
    and a pointer line at ten o'clock."""
    d = ImageDraw.Draw(canvas)
    for i in range(7):  # ticks from seven o'clock round to five o'clock
        a = math.radians(225 - i * 45)
        x0, y0 = cx + math.cos(a) * (r + 14 * R), cy - math.sin(a) * (r + 14 * R)
        t = 5 * R
        d.ellipse((x0 - t, y0 - t, x0 + t, y0 + t), fill=rgb(0x8f8a80) + (255,))
    box = (cx - r, cy - r, cx + r, cy + r)
    canvas.alpha_composite(shadow(canvas.size, box, r, 80, 9 * R, 14 * R))
    d = ImageDraw.Draw(canvas)
    d.ellipse((cx - r, cy - r + 8 * R, cx + r, cy + r + 8 * R), fill=rgb(0xb3ada1) + (255,))
    size = 2 * r
    disc = Image.new('L', (size, size), 0)
    ImageDraw.Draw(disc).ellipse((0, 0, size - 1, size - 1), fill=255)
    canvas.alpha_composite(layer(gradient(size, size, [0xfdfcfa, 0xece8e0, 0xd6d1c6]), canvas.size, (cx - r, cy - r), disc))
    fr = r - 12 * R  # the domed top, a little lighter than the skirt's slope
    top = Image.new('L', (2 * fr, 2 * fr), 0)
    ImageDraw.Draw(top).ellipse((0, 0, 2 * fr - 1, 2 * fr - 1), fill=255)
    canvas.alpha_composite(layer(gradient(2 * fr, 2 * fr, [0xf2efe8, 0xfbfaf7]), canvas.size, (cx - fr, cy - fr), top))
    d = ImageDraw.Draw(canvas)
    d.ellipse((cx - fr, cy - fr, cx + fr, cy + fr), outline=(0x9e, 0x98, 0x8b, 90), width=2 * R)
    a = math.radians(135)
    w = 5 * R
    x0, y0 = cx + math.cos(a) * 10 * R, cy - math.sin(a) * 10 * R
    x1, y1 = cx + math.cos(a) * (fr - 6 * R), cy - math.sin(a) * (fr - 6 * R)
    d.line((x0, y0, x1, y1), fill=rgb(0x2b2a27) + (255,), width=2 * w)
    for x, y in ((x0, y0), (x1, y1)):
        d.ellipse((x - w, y - w, x + w, y + w), fill=rgb(0x2b2a27) + (255,))


def app_icon():
    S, T = 1024 * R, 824 * R  # the macOS grid: an 824 pt tile in a 1024 pt canvas
    o = (S - T) // 2
    icon = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    tile_box = (o, o, o + T - 1, o + T - 1)
    icon.alpha_composite(shadow(icon.size, tile_box, 185 * R, 95, 16 * R, 12 * R))
    tile_mask = rounded_mask((T, T), (0, 0, T - 1, T - 1), 185 * R)
    icon.alpha_composite(layer(gradient(T, T, [0xf6f4ee, 0xebe8e1, 0xdcd7cc]), icon.size, (o, o), tile_mask))
    glow = gradient(T, T, [0xffffff, 0xffffff])
    glow.putalpha(gradient(T, T, [0x8c8c8c, 0x000000, 0x000000]).getchannel('R'))
    icon.alpha_composite(layer(glow, icon.size, (o, o), tile_mask))
    edge = Image.new('RGBA', (T, T), (0, 0, 0, 0))
    ImageDraw.Draw(edge).rounded_rectangle((0, 0, T - 1, T - 1), radius=185 * R, outline=(0x9e, 0x98, 0x8b, 120),
                                           width=3 * R)
    icon.alpha_composite(edge, (o, o))

    def at(x0, y0, x1, y1):  # tile coordinates (824 grid) to canvas pixels
        return o + x0 * R, o + y0 * R, o + x1 * R, o + y1 * R

    # The LCD: glass in a sunken bezel, crop corners in LCD ink.
    well(icon, at(104, 104, 720, 512), 58 * R, 0xc9c4b9, 0xdedad1, 110)
    gx0, gy0, gx1, gy1 = at(132, 132, 692, 484)
    gw, gh = gx1 - gx0, gy1 - gy0
    glass_mask = rounded_mask((gw, gh), (0, 0, gw - 1, gh - 1), 34 * R)
    icon.alpha_composite(layer(gradient(gw, gh, [0xd3d9be, 0xc3caad, 0xb9c0a2]), icon.size, (gx0, gy0), glass_mask))
    inner = Image.new('RGBA', (gw, gh), (0, 0, 0, 0))
    ImageDraw.Draw(inner).rounded_rectangle((-20 * R, -20 * R + 6 * R, gw + 20 * R, gh + 20 * R), radius=54 * R,
                                            outline=(0x1e, 0x23, 0x18, 70), width=26 * R)
    icon.alpha_composite(layer(inner.filter(ImageFilter.GaussianBlur(6 * R)), icon.size, (gx0, gy0), glass_mask))
    sheen = Image.new('RGBA', (gw, gh), (0, 0, 0, 0))
    ImageDraw.Draw(sheen).polygon([(0, 0), (gw * 0.62, 0), (gw * 0.30, gh), (0, gh)], fill=(255, 255, 255, 34))
    icon.alpha_composite(layer(sheen, icon.size, (gx0, gy0), glass_mask))

    ink = rgb(0x1e2318) + (235,)
    d = ImageDraw.Draw(icon)
    stroke, arm = 32 * R, 66 * R
    bx0, by0, bx1, by1 = gx0 + 92 * R, gy0 + 64 * R, gx1 - 92 * R, gy1 - 64 * R
    for cx, cy, sx, sy in ((bx0, by0, 1, 1), (bx1, by0, -1, 1), (bx0, by1, 1, -1), (bx1, by1, -1, -1)):
        # Each corner as one L with a rounded outer bend and rounded ends.
        h = stroke // 2
        d.rounded_rectangle((min(cx - sx * h, cx + sx * arm), min(cy - sy * h, cy + sy * h),
                             max(cx - sx * h, cx + sx * arm), max(cy - sy * h, cy + sy * h)), radius=h, fill=ink)
        d.rounded_rectangle((min(cx - sx * h, cx + sx * h), min(cy - sy * h, cy + sy * arm),
                             max(cx - sx * h, cx + sx * h), max(cy - sy * h, cy + sy * arm)), radius=h, fill=ink)

    # The bottom row: a cream knob, the speaker grille and the orange key.
    knob(icon, o + 190 * R, o + 642 * R, 56 * R)
    key(icon, at(524, 584, 720, 694), 30 * R, 0xff8045, 0xf2520f, 0xb93a07, 150)
    d = ImageDraw.Draw(icon)
    for row in range(3):
        for col in range(5):
            cx, cy = o + (352 + col * 30) * R, o + (608 + row * 34) * R
            r = 8 * R
            d.ellipse((cx - r, cy - r + R, cx + r, cy + r + R), fill=(255, 255, 255, 170))
            d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=rgb(0x8f8a80) + (255,))
            d.ellipse((cx - r + 2 * R, cy - r + 2 * R, cx + r - R, cy + r - R), fill=rgb(0x3d3b37) + (255,))

    return icon.resize((1024, 1024), Image.LANCZOS)


def menu_bar_glyph(scale):
    """The device as a template glyph, 18 pt tall: the body's outline, the LCD block, the knob and the key."""
    s = 16  # drawn larger, then reduced, for smooth curves on whole-pixel geometry
    px = scale * s
    w, h = 20 * px, 18 * px
    m = Image.new('L', (w, h), 0)
    d = ImageDraw.Draw(m)
    line = round(1.5 * px)
    d.rounded_rectangle((1.5 * px, 1.5 * px, w - 1.5 * px - 1, h - 1.5 * px - 1), radius=4 * px, outline=255,
                        width=line)
    d.rounded_rectangle((4.5 * px, 4.5 * px, w - 4.5 * px - 1, 10.5 * px - 1), radius=1.25 * px, fill=255)
    d.ellipse((4.5 * px, 11.5 * px, 7.5 * px - 1, 14.5 * px - 1), fill=255)
    d.rounded_rectangle((w - 8.5 * px, 12 * px, w - 4.5 * px - 1, 14 * px - 1), radius=1 * px, fill=255)
    alpha = m.resize((20 * scale, 18 * scale), Image.LANCZOS)
    out = Image.new('RGBA', alpha.size, (0, 0, 0, 0))
    out.putalpha(alpha)
    return out


icon = app_icon()
icon.save(os.path.join(res, 'AppIcon.icns'),
          sizes=[(16, 16), (32, 32), (64, 64), (128, 128), (256, 256), (512, 512), (1024, 1024)])
for scale, name in ((1, 'MenuBarIcon.png'), (2, 'MenuBarIcon@2x.png')):
    menu_bar_glyph(scale).save(os.path.join(res, name))
