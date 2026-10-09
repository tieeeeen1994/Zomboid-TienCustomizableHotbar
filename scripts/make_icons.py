"""Toolbar icons for the bars' right-hand column: 16x16 white pixel glyphs with a soft dark outline.

python3 scripts/make_icons.py  (Pillow) -> Contents/mods/TienCustomizableHotbar/42/media/ui/TienCustomizableHotbar/
"""
import os

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "Contents", "mods", "TienCustomizableHotbar", "42", "media", "ui", "TienCustomizableHotbar")
SIZE = 16
OUTLINE = (0, 0, 0, 150)


def from_rows(rows):
    return {(x, y) for y, row in enumerate(rows) for x, c in enumerate(row) if c == "#"}


BODY = [
    "..############..",
    "..############..",
    "..#####..#####..",
    "..#####..#####..",
    "..#####..#####..",
    "..#####..#####..",
    "..############..",
    "..############..",
]

LOCK = from_rows([
    "................",
    ".....######.....",
    "....########....",
    "....##....##....",
    "....##....##....",
    "....##....##....",
    "....##....##....",
] + BODY + ["................"])

UNLOCK = from_rows([
    "................",
    ".....######.....",
    "....########....",
    "....##....##....",
    "....##..........",
    "....##..........",
    "....##..........",
] + BODY + ["................"])

SWAP = from_rows([
    "................",
    ".........#......",
    ".........##.....",
    ".###########....",
    ".###########....",
    ".........##.....",
    ".........#......",
    "................",
    "................",
    "......#.........",
    ".....##.........",
    "....###########.",
    "....###########.",
    ".....##.........",
    "......#.........",
    "................",
])

INSERT = from_rows([
    ".......##.......",
    ".......##.......",
    ".......##.......",
    ".......##.......",
    ".......##.......",
    "....########....",
    ".....######.....",
    "......####......",
    ".......##.......",
    "................",
    "#####.....######",
    "#...#..##.#....#",
    "#...#..##.#....#",
    "#...#..##.#....#",
    "#####..##.######",
    "................",
])

EYE = from_rows([
    "................",
    "................",
    "................",
    ".....######.....",
    "...##########...",
    "..###......###..",
    ".##....##....##.",
    "##....####....##",
    "##....####....##",
    ".##....##....##.",
    "..###......###..",
    "...##########...",
    ".....######.....",
    "................",
    "................",
    "................",
])


def eye_off():
    slash = set()
    for i in range(1, 15):
        slash.add((i, 15 - i))
        slash.add((i, 14 - i))
    gap = {(x + dx, y + dy) for x, y in slash for dx in (-1, 0, 1) for dy in (-1, 0, 1)} - slash
    return (EYE - gap) | slash


GEAR = from_rows([
    "......####......",
    "......####......",
    "..###.####.###..",
    "..############..",
    "...##########...",
    "...####..####...",
    "######....######",
    "#####......#####",
    "#####......#####",
    "######....######",
    "...####..####...",
    "...##########...",
    "..############..",
    "..###.####.###..",
    "......####......",
    "......####......",
])


def save(name, on):
    im = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    px = im.load()
    for x, y in on:
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                nx, ny = x + dx, y + dy
                if 0 <= nx < SIZE and 0 <= ny < SIZE and (nx, ny) not in on:
                    px[nx, ny] = OUTLINE
    for x, y in on:
        px[x, y] = (255, 255, 255, 255)
    im.save(os.path.join(OUT, name + ".png"))
    return im


def main():
    os.makedirs(OUT, exist_ok=True)
    icons = {
        "lock": LOCK,
        "unlock": UNLOCK,
        "swap": SWAP,
        "insert": INSERT,
        "eye": EYE,
        "eyeoff": eye_off(),
        "gear": GEAR,
    }
    sheet = Image.new("RGBA", (len(icons) * 72, 72), (70, 70, 50, 255))
    for i, (name, on) in enumerate(icons.items()):
        im = save(name, on)
        sheet.alpha_composite(im.resize((64, 64), Image.NEAREST), (i * 72 + 4, 4))
    sheet.save(os.path.join(HERE, "icons_preview.png"))


if __name__ == "__main__":
    main()
