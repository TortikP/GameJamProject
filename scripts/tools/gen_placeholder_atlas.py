#!/usr/bin/env python3
"""Generate placeholder hex atlas for the map editor.

One PNG with 6 flat-top hexes, 128×80 each, in a horizontal strip.
Each hex is a single saturated colour so the silhouette reads at a
glance — temporary stand-in until Katya's tileset lands.

Run from repo root:
    python3 scripts/tools/gen_placeholder_atlas.py

Output: assets/tiles/placeholder_atlas.png
"""

from PIL import Image, ImageDraw

# Order matches placeholder_terrain.tres atlas-coord (X, 0) — X=0..N-1.
TILES = [
    ("grass", (74, 138, 74)),    # forest green
    ("sand",  (214, 188, 130)),  # warm tan
    ("stone", (138, 142, 152)),  # cool grey
    ("water", (74, 122, 170)),   # muted blue
    ("dirt",  (138, 96, 64)),    # rich brown
    ("snow",  (224, 230, 240)),  # cool white
]

W, H = 128, 80   # matches every other hex_terrain in the project
SHRINK = 1       # 0-pixel inset gives crisp tile borders; 1 leaves 1px gap

# Flat-top hex polygon points for a 128×80 cell (sides at x=32 and x=96).
HEX = [
    (32 + SHRINK,  0 + SHRINK),
    (96 - SHRINK,  0 + SHRINK),
    (128 - SHRINK, 40),
    (96 - SHRINK,  80 - SHRINK),
    (32 + SHRINK,  80 - SHRINK),
    (0 + SHRINK,   40),
]


def main() -> None:
    atlas = Image.new("RGBA", (W * len(TILES), H), (0, 0, 0, 0))
    for i, (_name, rgb) in enumerate(TILES):
        cell = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        draw = ImageDraw.Draw(cell)
        # Slight darken for outline so adjacent same-colour tiles still
        # read as separate hexes when placed side-by-side.
        outline = tuple(max(0, c - 35) for c in rgb)
        draw.polygon(HEX, fill=rgb + (255,), outline=outline + (255,))
        atlas.paste(cell, (i * W, 0))
    out = "assets/tiles/placeholder_atlas.png"
    atlas.save(out, "PNG")
    print(f"wrote {out}  ({len(TILES)} tiles, {atlas.size[0]}×{atlas.size[1]})")


if __name__ == "__main__":
    main()
