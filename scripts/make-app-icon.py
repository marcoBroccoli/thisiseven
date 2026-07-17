#!/usr/bin/env python3
"""Even app icons: paper ground, faint grain, the ScaleGlyph mark.

Generates the iOS 18 appearance set — light (paper + ink), dark (dark paper
+ light ink, never plain black), and tinted (grayscale glyph on transparent).
Glyph proportions mirror the SwiftUI ScaleGlyph shape in EvenRootView.swift.
Usage: make-app-icon.py [span]   (span = glyph fraction of canvas, default 0.58)
"""
import random
import sys

from PIL import Image, ImageDraw

SIZE = 1024
SPAN = float(sys.argv[1]) if len(sys.argv) > 1 else 0.58
STROKE = int(48 * SPAN / 0.70)
OUT_DIR = "ios/EvenApp/Assets.xcassets/AppIcon.appiconset"

VARIANTS = [
    # (filename, background paper tone or None for transparent, glyph color)
    ("AppIcon.png", (0xF6, 0xF1, 0xE6), (0x26, 0x20, 0x1A)),
    ("AppIcon-Dark.png", (0x21, 0x1B, 0x15), (0xED, 0xE5, 0xD6)),
    ("AppIcon-Tinted.png", None, (0x80, 0x80, 0x80)),
]


def render(paper, ink):
    mode = "RGB" if paper else "RGBA"
    ground = paper if paper else (0, 0, 0, 0)
    img = Image.new(mode, (SIZE, SIZE), ground)
    draw = ImageDraw.Draw(img)

    # Whisper of grain on the paper variants.
    if paper:
        rng = random.Random(7)
        for _ in range(9000):
            x, y = rng.randrange(SIZE), rng.randrange(SIZE)
            g = rng.randint(-9, 9)
            px = tuple(max(0, min(255, c + g)) for c in paper)
            draw.point((x, y), fill=px)

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


for name, paper, ink in VARIANTS:
    out = f"{OUT_DIR}/{name}"
    render(paper, ink).save(out)
    print(f"wrote {out} (span {SPAN}, stroke {STROKE})")
