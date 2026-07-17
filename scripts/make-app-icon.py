#!/usr/bin/env python3
"""Even app icon: paper ground, faint grain, the ScaleGlyph mark in ink.

Glyph proportions mirror the SwiftUI ScaleGlyph shape in EvenRootView.swift.
Usage: make-app-icon.py [span]   (span = glyph fraction of canvas, default 0.70)
"""
import random
import sys

from PIL import Image, ImageDraw

SIZE = 1024
SPAN = float(sys.argv[1]) if len(sys.argv) > 1 else 0.70
PAPER = (0xF6, 0xF1, 0xE6)
INK = (0x26, 0x20, 0x1A)
STROKE = int(48 * SPAN / 0.70)

img = Image.new("RGB", (SIZE, SIZE), PAPER)
draw = ImageDraw.Draw(img)

# Whisper of grain.
rng = random.Random(7)
for _ in range(9000):
    x, y = rng.randrange(SIZE), rng.randrange(SIZE)
    g = rng.randint(-9, 9)
    px = tuple(max(0, min(255, c + g)) for c in PAPER)
    draw.point((x, y), fill=px)

box = SIZE * SPAN
ox = oy = (SIZE - box) / 2

def pt(x, y):
    return (ox + x * box, oy + y * box)

def dot(p, r):
    draw.ellipse([p[0] - r, p[1] - r, p[0] + r, p[1] + r], fill=INK)

def line(a, b, w):
    draw.line([a, b], fill=INK, width=w)
    dot(a, w / 2)
    dot(b, w / 2)

# Beam, pointer triangle, base — same anchors as the Swift shape.
line(pt(0.09, 0.42), pt(0.91, 0.29), STROKE)
tri = [pt(0.5, 0.4), pt(0.66, 0.66), pt(0.34, 0.66)]
for a, b in zip(tri, tri[1:] + tri[:1]):
    line(a, b, int(STROKE * 0.92))
line(pt(0.28, 0.84), pt(0.72, 0.84), int(STROKE * 0.88))

out = "ios/EvenApp/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
img.save(out)
print(f"wrote {out} (span {SPAN}, stroke {STROKE})")
