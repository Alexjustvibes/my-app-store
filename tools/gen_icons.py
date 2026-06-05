#!/usr/bin/env python3
"""
Generate distinct home-screen icons for the store and each app.

Each icon = the app's CSS gradient (from the REGISTRY in index.html) with the
app's emoji centered on top. Output is opaque PNG (iOS apple-touch-icons must
not be transparent) at three sizes per target:

    apple-touch-icon.png  (180x180)  -> iOS Add to Home Screen
    icon-192.png          (192x192)  -> manifest, small
    icon-512.png          (512x512)  -> manifest, large / maskable

Files are written next to the index.html that references them (root for the
store, apps/<id>/ for each app) so everything stays self-contained with
relative paths.

Requires Pillow + numpy. The committed PNGs are static; you only need to rerun
this if you change an app's emoji or gradient. From the repo root:

    python tools/gen_icons.py
"""
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EMOJI_FONT = r"C:\Windows\Fonts\seguiemj.ttf"
SIZES = {"apple-touch-icon.png": 180, "icon-192.png": 192, "icon-512.png": 512}

# id, output dir (relative to repo root), emoji, gradient colors (0% -> 100%),
# matching each REGISTRY entry's `bg` gradient. The store has no REGISTRY entry,
# so it gets its own warm amber identity + shopping-bag glyph.
SPECS = [
    {"dir": ".",            "emoji": "\U0001F6CD", "c0": "#ffc24b", "c1": "#ff6a2c"},  # store
    {"dir": "apps/notes",   "emoji": "\U0001F4DD", "c0": "#ffb347", "c1": "#ff7a00"},  # notes
    {"dir": "apps/courage", "emoji": "\U0001F525", "c0": "#e8523a", "c1": "#ff8a3d"},  # courage
]
ANGLE = 145  # CSS linear-gradient angle used throughout the REGISTRY


def hex_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def gradient(size, c0, c1, angle):
    """Opaque RGB gradient matching CSS linear-gradient(angle, c0, c1)."""
    a = math.radians(angle)
    ux, uy = math.sin(a), -math.cos(a)          # gradient axis, y-up
    length = abs(ux) + abs(uy)                   # span across unit box, center-based
    xs = (np.arange(size) + 0.5) / size          # 0..1 across columns
    ys = 1.0 - (np.arange(size) + 0.5) / size    # 0..1 up the rows (y-up)
    gx, gy = np.meshgrid(xs, ys)
    t = 0.5 + ((gx - 0.5) * ux + (gy - 0.5) * uy) / length
    t = np.clip(t, 0.0, 1.0)[..., None]
    a0 = np.array(hex_rgb(c0), dtype=float)
    a1 = np.array(hex_rgb(c1), dtype=float)
    rgb = (a0 * (1 - t) + a1 * t).astype(np.uint8)
    return Image.fromarray(rgb, "RGB")


def render(spec, size):
    bg = gradient(size, spec["c0"], spec["c1"], ANGLE).convert("RGBA")

    # Emoji layer (transparent), centered.
    font = ImageFont.truetype(EMOJI_FONT, int(size * 0.60))
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.text((size / 2, size / 2 + size * 0.01), spec["emoji"],
           font=font, embedded_color=True, anchor="mm")

    # Soft drop shadow from the emoji's alpha, for depth on the gradient.
    alpha = layer.split()[3]
    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    sd = Image.new("L", (size, size), 0)
    sd.paste(int(255 * 0.30), (0, 0), alpha)
    shadow.putalpha(sd.filter(ImageFilter.GaussianBlur(size * 0.025)))
    shadow = Image.composite(
        Image.new("RGBA", (size, size), (0, 0, 0, 255)),
        Image.new("RGBA", (size, size), (0, 0, 0, 0)),
        shadow.split()[3])
    offset = int(size * 0.015)
    bg.alpha_composite(shadow, (0, offset))
    bg.alpha_composite(layer)

    return bg.convert("RGB")  # flatten -> opaque, no alpha for iOS


def main():
    for spec in SPECS:
        outdir = os.path.join(ROOT, spec["dir"])
        for fname, size in SIZES.items():
            img = render(spec, size)
            img.save(os.path.join(outdir, fname), "PNG")
            print(f"  {os.path.join(spec['dir'], fname)}  ({size}x{size})")
    print("done.")


if __name__ == "__main__":
    main()
