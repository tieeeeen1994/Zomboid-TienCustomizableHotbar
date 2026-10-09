"""Builds the mod's icon, poster and Workshop preview.

    python3 scripts/make_art.py

Needs Pillow. Reads item icons from the local Project Zomboid install (media/texturepacks/UI2.pack, UI.pack), writes:
  Contents/mods/TienCustomizableHotbar/42/icon.png      128x128
  Contents/mods/TienCustomizableHotbar/42/poster.png    512x512
  preview.png                                         512x512
"""

import io
import math
import os
import re
import struct

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
MOD = os.path.join(REPO, "Contents", "mods", "TienCustomizableHotbar", "42")
PZ = os.path.expanduser(
    "~/Library/Application Support/Steam/steamapps/common/ProjectZomboid/"
    "Project Zomboid.app/Contents/Java"
)
PACKS = [os.path.join(PZ, "media", "texturepacks", name) for name in ("UI2.pack", "UI.pack")]
FONT = "/System/Library/Fonts/Helvetica.ttc"

SS = 4
GLOW = (78, 66, 48)
DARK = (14, 14, 17)
ACCENT = (255, 205, 80)
BORDER = (204, 204, 204, 255)
INK = (12, 12, 12, 255)

_PACKS = {}


def pack_index(path):
    """name -> (page, x, y, w, h, offsetX, offsetY, originalW, originalH). A .pack is a run of
    int32-length-prefixed entry names, each followed by eight int32s, then once per page a plain
    PNG of the sheet; an entry belongs to the first PNG that starts after it."""
    if path in _PACKS:
        return _PACKS[path]
    if not os.path.exists(path):
        raise SystemExit("Missing game file: " + path)
    blob = open(path, "rb").read()
    pages = list(zip(
        [m.start() for m in re.finditer(rb"\x89PNG\r\n\x1a\n", blob)],
        [m.start() + 12 for m in re.finditer(rb"IEND\xaeB`\x82", blob)],
    ))
    index = {}
    for match in re.finditer(rb"[A-Za-z0-9_]{3,60}", blob):
        at, run = match.start(), match.group()
        if at < 4:
            continue
        length = struct.unpack_from("<i", blob, at - 4)[0]
        if not 3 <= length <= len(run):
            continue
        try:
            rect = struct.unpack_from("<8i", blob, at + length)
        except struct.error:
            continue
        page = next((i for i, p in enumerate(pages) if p[0] > at), None)
        if page is not None:
            index[run[:length].decode()] = (page,) + rect
    _PACKS[path] = {"blob": blob, "pages": pages, "sheets": {}, "index": index}
    return _PACKS[path]


def item_icon(name):
    """The game's item icon, from the first pack that has it (B42 icons are in UI2.pack, older ones
    such as the baseball bat and painkillers only in UI.pack)."""
    for path in PACKS:
        pack = pack_index(path)
        if name not in pack["index"]:
            continue
        page, x, y, w, h, ox, oy, ow, oh = pack["index"][name]
        if page not in pack["sheets"]:
            start, end = pack["pages"][page]
            pack["sheets"][page] = Image.open(io.BytesIO(pack["blob"][start:end])).convert("RGBA")
        icon = Image.new("RGBA", (ow, oh), (0, 0, 0, 0))
        icon.paste(pack["sheets"][page].crop((x, y, x + w, y + h)), (ox, oy))
        return icon
    raise SystemExit("No icon named %s in UI2.pack or UI.pack" % name)


def font(px, bold=False):
    return ImageFont.truetype(FONT, max(6, round(px)), index=1 if bold else 0)


def backdrop(size):
    """Dark, with a warm glow in the middle."""
    img = Image.new("RGBA", (size, size))
    px = img.load()
    cx, cy, r = size * 0.5, size * 0.4, size * 0.62
    for y in range(size):
        for x in range(size):
            t = min(1.0, ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5 / r)
            t = t * t * (3 - 2 * t)
            px[x, y] = tuple(round(a + (b - a) * t) for a, b in zip(GLOW, DARK)) + (255,)
    return img


def dilate(alpha, px):
    return alpha.filter(ImageFilter.MaxFilter(2 * px + 1)) if px > 0 else alpha


def fill_holes(mask):
    """Closes the holes inside a mask (a strap loop), so the outline only follows the outside edge."""
    pad = Image.new("L", (mask.width + 2, mask.height + 2), 0)
    pad.paste(mask, (1, 1))
    ImageDraw.floodfill(pad, (0, 0), 128)
    pad = pad.point(lambda a: 0 if a == 128 else 255)
    return pad.crop((1, 1, mask.width + 1, mask.height + 1))


def sticker(icon, scale, ring):
    """Pixel art scaled by a whole number, with a thin dark line and then a white outline one art
    pixel wide, stepped like the pixels (the series' sticker look)."""
    art = icon.resize((icon.width * scale, icon.height * scale), Image.NEAREST)
    pad = ring * 3
    canvas = Image.new("RGBA", (art.width + pad * 2, art.height + pad * 2), (0, 0, 0, 0))
    canvas.alpha_composite(art, (pad, pad))
    alpha = canvas.getchannel("A").point(lambda a: 255 if a > 40 else 0)
    out = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    white = Image.new("RGBA", canvas.size, (255, 255, 255, 255))
    dark = max(1, ring // 3)
    solid = fill_holes(alpha)
    holes = ImageChops.subtract(solid, dilate(alpha, dark))
    out.paste(white, (0, 0), ImageChops.subtract(dilate(solid, ring + dark), holes))
    out.paste(Image.new("RGBA", canvas.size, INK), (0, 0), dilate(alpha, dark))
    out.alpha_composite(canvas)
    return out


def shadow(img, layer, at, blur, alpha, offset):
    mask = layer.getchannel("A").point(lambda a: a * alpha // 255)
    pad = blur * 3
    sh = Image.new("RGBA", (layer.width + pad * 2, layer.height + pad * 2), (0, 0, 0, 0))
    black = Image.new("RGBA", layer.size, (0, 0, 0, 255))
    sh.paste(black, (pad, pad), mask)
    sh = sh.filter(ImageFilter.GaussianBlur(blur))
    img.alpha_composite(sh, (at[0] - pad + offset[0], at[1] - pad + offset[1]))


def place(img, layer, centre):
    at = (round(centre[0] - layer.width / 2), round(centre[1] - layer.height / 2))
    img.alpha_composite(layer, at)
    return at


def slot(img, box, number, icon, k, lit=False):
    """A hotbar slot as the game draws it: thin light border, the slot number top left."""
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.rectangle(box, fill=(255, 255, 255, 46) if lit else (0, 0, 0, 120))
    d.rectangle(box, outline=ACCENT + (255,) if lit else BORDER, width=max(1, round(3 * k)))
    img.alpha_composite(layer)
    if icon is not None:
        scale = max(1, int((box[2] - box[0]) * 0.78 // icon.width))
        art = icon.resize((icon.width * scale, icon.height * scale), Image.NEAREST)
        place(img, art, ((box[0] + box[2]) / 2, (box[1] + box[3]) / 2))
    ImageDraw.Draw(img).text((box[0] + round(8 * k), box[1] + round(4 * k)), number, font=font(24 * k),
                             fill=(255, 255, 255, 255))


def keycap(size, label):
    """A keyboard key, light grey with a darker base, the label in bold."""
    w = size
    h = round(size * 1.06)
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    r = round(size * 0.18)
    edge = max(2, round(size * 0.05))
    d.rounded_rectangle([0, 0, w - 1, h - 1], radius=r, fill=INK)
    d.rounded_rectangle([edge, edge, w - 1 - edge, h - 1 - edge], radius=r - edge, fill=(150, 150, 156, 255))
    d.rounded_rectangle([edge * 2, edge * 1.6, w - 1 - edge * 2, h - 1 - edge * 3.6], radius=r - edge,
                        fill=(232, 232, 236, 255))
    d.text((w / 2, (h - edge * 2) / 2), label, font=font(size * 0.56, bold=True), fill=(40, 40, 44, 255), anchor="mm")
    return img


def plus_slot(img, box, k):
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.rectangle(box, fill=(0, 0, 0, 120), outline=BORDER, width=max(1, round(3 * k)))
    img.alpha_composite(layer)
    ImageDraw.Draw(img).text(((box[0] + box[2]) / 2, (box[1] + box[3]) / 2), "+", font=font(46 * k),
                             fill=(255, 255, 255, 150), anchor="mm")


def grip(img, x, cy, k):
    d = ImageDraw.Draw(img)
    r = max(1, round(3 * k))
    for i in (-1, 0, 1):
        y = cy + i * round(11 * k)
        d.ellipse([x - r, y - r, x + r, y + r], fill=(180, 180, 180, 220))


def curve(d, pts, k):
    d.line(pts, fill=(0, 0, 0, 210), width=round(13 * k), joint="curve")
    d.line(pts, fill=ACCENT + (255,), width=round(7 * k), joint="curve")

def bez(p0, p1, p2, n=48):
    return [((1-t)**2*p0[0]+2*(1-t)*t*p1[0]+t*t*p2[0], (1-t)**2*p0[1]+2*(1-t)*t*p1[1]+t*t*p2[1]) for t in [i/n for i in range(n+1)]]

def head(d, pts, k):
    (x1, y1), (x2, y2) = pts[-4], pts[-1]
    a = math.atan2(y2 - y1, x2 - x1); L = 30 * k
    tip = (x2 + math.cos(a) * 8 * k, y2 + math.sin(a) * 8 * k)
    poly = [tip, (x2 - math.cos(a - 0.55) * L, y2 - math.sin(a - 0.55) * L), (x2 - math.cos(a + 0.55) * L, y2 - math.sin(a + 0.55) * L)]
    d.polygon(poly, fill=ACCENT + (255,), outline=(0, 0, 0, 210), width=round(3 * k))

def poster(size):
    k = size / 512
    img = backdrop(size)
    # inventory window
    wx, wy, ww = round(40 * k), round(70 * k), round(250 * k)
    row = round(48 * k)
    rows = [("Item_WaterBottle", False), ("Item_AssaultRifle", True), ("Item_Hammer", False), ("Item_Whiskey", False)]
    title = round(30 * k)
    wh = title + row * len(rows) + round(10 * k)
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.rectangle([wx, wy, wx + ww, wy + wh], fill=(18, 18, 20, 235), outline=(110, 110, 110, 255), width=round(2 * k))
    d.rectangle([wx, wy, wx + ww, wy + title], fill=(40, 40, 44, 255))
    img.alpha_composite(layer)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([wx + round(14 * k), wy + round(11 * k), wx + round(130 * k), wy + round(19 * k)], radius=round(4 * k), fill=(150, 150, 150, 255))
    rifle_row = None
    for i, (name, lit) in enumerate(rows):
        y = wy + title + round(5 * k) + i * row
        if lit:
            hl = Image.new("RGBA", img.size, (0, 0, 0, 0))
            ImageDraw.Draw(hl).rectangle([wx + round(4 * k), y, wx + ww - round(4 * k), y + row - round(4 * k)], fill=(255, 205, 80, 46), outline=ACCENT + (255,), width=round(3 * k))
            img.alpha_composite(hl)
            d = ImageDraw.Draw(img)
            rifle_row = (wx + ww, y + (row - round(4 * k)) / 2)
        ic = item_icon(name).resize((round(40 * k), round(40 * k)), Image.NEAREST)
        img.alpha_composite(ic, (wx + round(10 * k), y + round(1 * k)))
        d.rounded_rectangle([wx + round(62 * k), y + round(16 * k), wx + round((200 if lit else 160 - i * 12) * k), y + round(26 * k)], radius=round(5 * k), fill=(200, 200, 200, 255) if lit else (120, 120, 120, 255))
    # bar
    cell, gap, edge = round(96 * k), round(14 * k), round(22 * k)
    count = 4
    total = cell * count + gap * (count - 1)
    left = (size - total) // 2 + round(6 * k)
    top = size - cell - round(30 * k)
    bar = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(bar).rectangle([left - edge, top - gap, left + total + gap, top + cell + gap], fill=(0, 0, 0, 130), outline=BORDER, width=max(1, round(2 * k)))
    img.alpha_composite(bar)
    grip(img, left - edge / 2 - round(1 * k), top + cell / 2, k)
    boxes = [(left + i * (cell + gap), top, left + i * (cell + gap) + cell, top + cell) for i in range(count)]
    slot(img, boxes[0], "1", item_icon("Item_KnifeHunting"), k)
    slot(img, boxes[1], "2", item_icon("Item_AssaultRifle"), k, lit=True)
    slot(img, boxes[2], "3", item_icon("Item_PillsBetablocker"), k)
    plus_slot(img, boxes[3], k)
    d = ImageDraw.Draw(img)
    end = ((boxes[1][0] + boxes[1][2]) / 2 + round(14 * k), boxes[1][1] - round(26 * k))
    start = (rifle_row[0] + round(14 * k), rifle_row[1])
    pts = bez(start, (start[0] + round(170 * k), start[1] + round(10 * k)), end)
    curve(d, pts, k)
    head(d, pts, k)
    bag = sticker(item_icon("Item_BigHiking_Green"), round(3 * k), round(3 * k))
    bat = (wx + ww - round(70 * k), wy - round(62 * k))
    shadow(img, bag, bat, round(6 * k), 160, (round(6 * k), round(8 * k)))
    img.alpha_composite(bag, bat)
    return img

def icon(size):
    """A lit hotbar slot holding the rifle, the bag sticker on its empty corner."""
    big = size * SS
    k = big / 128.0
    img = backdrop(big)
    s = round(96 * k)
    box = (round(10 * k), round(10 * k), round(10 * k) + s, round(10 * k) + s)
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).rectangle(box, fill=(255, 255, 255, 40), outline=ACCENT + (255,), width=round(3 * k))
    img.alpha_composite(layer)
    rifle = item_icon("Item_AssaultRifle")
    rifle = rifle.resize((round(64 * k), round(64 * k)), Image.NEAREST)
    place(img, rifle, ((box[0] + box[2]) / 2, (box[1] + box[3]) / 2))
    bag = sticker(item_icon("Item_BigHiking_Green"), max(1, round(1.4 * k)), max(1, round(1.2 * k)))
    at = (big - bag.width - round(2 * k), big - bag.height - round(2 * k))
    shadow(img, bag, at, round(3 * k), 160, (round(2 * k), round(3 * k)))
    img.alpha_composite(bag, at)
    return img.resize((size, size), Image.LANCZOS)


def main():
    os.makedirs(MOD, exist_ok=True)
    icon(128).convert("RGB").save(os.path.join(MOD, "icon.png"))
    art = poster(512).convert("RGB")
    art.save(os.path.join(MOD, "poster.png"))
    art.save(os.path.join(REPO, "preview.png"))
    print("Wrote icon.png, poster.png and preview.png")


if __name__ == "__main__":
    main()
