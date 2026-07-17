#!/usr/bin/env python3
"""Even app icons: textured paper ground, the ScaleGlyph mark.

The background must READ as the app's paper at home-screen size (~60px),
so grain is multi-octave (coarse blotches, not per-pixel dust) with a
subtle warm vignette. Generates the iOS 18 appearance set — light (deep
paper + ink), dark (dark paper + light ink), tinted (grayscale glyph on
transparent). Glyph proportions mirror ScaleGlyph in EvenRootView.swift.
Usage: make-app-icon.py [span]   (span = glyph fraction, default 0.58)
"""
import random
import sys

from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
SPAN = float(sys.argv[1]) if len(sys.argv) > 1 else 0.58
STROKE = int(48 * SPAN / 0.70)
OUT_DIR = "ios/EvenApp/Assets.xcassets/AppIcon.appiconset"

VARIANTS = [
    # (filename, paper tone or None, glyph color, texture gain — dark bases
    # need a bigger proportional swing to read at all)
    ("AppIcon.png", (0xE9, 0xE1, 0xD2), (0x26, 0x20, 0x1A), 1.0),
    ("AppIcon-Dark.png", (0x21, 0x1B, 0x15), (0xED, 0xE5, 0xD6), 2.4),
    ("AppIcon-Tinted.png", None, (0x80, 0x80, 0x80), 1.0),
]

# Luminance swing of the paper texture (fraction of base) and vignette depth.
GRAIN_AMP = 0.055
VIGNETTE = 0.045


def octave(size, seed):
    """Random L image at `size`, upscaled smooth — one blotch scale."""
    rng = random.Random(seed)
    small = Image.new("L", (size, size))
    small.putdata([rng.randint(0, 255) for _ in range(size * size)])
    return small.resize((SIZE, SIZE), Image.BILINEAR)


def paper_map():
    """Combined texture map, 128 = neutral. Coarse octaves dominate so the
    texture survives downscaling to home-screen size."""
    o1 = octave(12, 1)    # broad clouding
    o2 = octave(36, 2)    # mid blotches
    o3 = octave(110, 3)   # fine tooth
    mix = Image.blend(Image.blend(o1, o2, 0.42), o3, 0.22)
    mix = mix.filter(ImageFilter.GaussianBlur(1.2))

    # Radial vignette: corners darker, center untouched.
    v = 64
    vig = Image.new("L", (v, v))
    cx = (v - 1) / 2
    vig.putdata([
        int(255 * min(1, (((x - cx) ** 2 + (y - cx) ** 2) ** 0.5 / (cx * 1.35)) ** 2))
        for y in range(v) for x in range(v)
    ])
    vig = vig.resize((SIZE, SIZE), Image.BICUBIC)

    # delta = grain swing minus vignette darkening, re-centered on 128.
    out = Image.new("L", (SIZE, SIZE))
    gpx, vpx = mix.load(), vig.load()
    opx = out.load()
    for y in range(SIZE):
        for x in range(SIZE):
            g = (gpx[x, y] - 128) / 128 * GRAIN_AMP
            d = 1 + g - (vpx[x, y] / 255) * VIGNETTE
            opx[x, y] = max(0, min(255, int(128 * d)))
    return out


def render(paper, ink, texture, gain):
    if paper is None:
        img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    else:
        # Apply the texture map to the solid paper via per-channel LUTs.
        channels = []
        for c in paper:
            lut = [max(0, min(255, round(c * (1 + (v / 128 - 1) * gain))))
                   for v in range(256)]
            channels.append(texture.point(lut))
        img = Image.merge("RGB", channels)

    draw = ImageDraw.Draw(img)
    box = SIZE * SPAN
    ox = (SIZE - box) / 2
    # The glyph's anchors span y 0.29–0.84 of its box; shift up so the mark
    # sits optically centered rather than low.
    oy = (SIZE - box) / 2 - box * 0.065

    def pt(x, y):
        return (ox + x * box, oy + y * box)

    def dot(p, r):
        draw.ellipse([p[0] - r, p[1] - r, p[0] + r, p[1] + r], fill=ink)

    def line(a, b, w):
        draw.line([a, b], fill=ink, width=w)
        dot(a, w / 2)
        dot(b, w / 2)

    # Beam, pointer triangle, base — same anchors as the Swift shape.
    line(pt(0.09, 0.42), pt(0.91, 0.29), STROKE)
    tri = [pt(0.5, 0.4), pt(0.66, 0.66), pt(0.34, 0.66)]
    for a, b in zip(tri, tri[1:] + tri[:1]):
        line(a, b, int(STROKE * 0.92))
    line(pt(0.28, 0.84), pt(0.72, 0.84), int(STROKE * 0.88))
    return img


texture = paper_map()
for name, paper, ink, gain in VARIANTS:
    out = f"{OUT_DIR}/{name}"
    render(paper, ink, texture, gain).save(out)
    print(f"wrote {out} (span {SPAN}, stroke {STROKE})")
