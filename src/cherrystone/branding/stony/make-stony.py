#!/usr/bin/env python3
# Stony, the Cherrystone mascot: a little pixel cherry, named after the
# stone inside (a cherrystone). This draws Stony's moods as PNG files, one pixel per character
# below, blown up with hard edges. Run it again after changing a drawing:
#   python3 make-stony.py
# It writes stony-<mood>.png (x8, big) and stony-<mood>-small.png (x4) here.
import os, struct, zlib

PAL = {
    "r": (216, 30, 60), "d": (142, 15, 38), "h": (255, 122, 144), "k": (42, 7, 16),
    "g": (47, 107, 37), "l": (92, 191, 74), "p": (255, 150, 170), "z": (128, 134, 139),
    # sad Stony is grey, like the "page didn't load" picture
    "G": (95, 99, 104), "L": (154, 160, 166), "R": (189, 193, 198), "H": (232, 234, 237),
    "D": (128, 134, 139), "K": (60, 64, 67),
    "w": (255, 255, 255), "q": (255, 214, 224), "y": (255, 201, 40),
}

MOODS = {
    "happy": [
        ".......ggll.",
        "......g.lll.",
        ".....g......",
        "...rrrrrr...",
        "..rhhrrrrr..",
        ".rhhrrrrrrr.",
        ".rrrrkrrkrr.",
        ".rrrrkrrkrr.",
        ".rrrrrrrrrr.",
        ".drrkrrrrkr.",
        "..drrkkkkrd.",
        "..ddrrrrrdd.",
        "...dddddd...",
    ],
    "excited": [
        ".......ggll.",
        "......g.lll.",
        ".....g......",
        "...rrrrrr...",
        "..rhhrrrrr..",
        ".rhhrrrrrrr.",
        ".rrrkrrrkrr.",
        ".rrrkrrrkrr.",
        ".rprrrrrrpr.",
        ".drrkkkkkrr.",
        "..drrkkkrrd.",
        "..ddrrrrrdd.",
        "...dddddd...",
    ],
    "sad": [
        ".......GGLL.",
        "......G.LLL.",
        ".....G......",
        "...RRRRRR...",
        "..RHHRRRRR..",
        ".RHHRRRRRRR.",
        ".RRRKRRRKRR.",
        ".RRRKRRRKRR.",
        ".RRRRRRRRRR.",
        ".RRRRKKKRRR.",
        "..DRKRRRKRD.",
        "..DDRRRRRDD.",
        "...DDDDDD...",
    ],
    "sleepy": [
        ".......ggll.zzz.",
        "......g.lll...z.",
        ".....g.......z..",
        "...rrrrrr...zzz.",
        "..rhhrrrrr......",
        ".rhhrrrrrrr.....",
        ".rrrrrrrrrr.....",
        ".rrkkrrkkrr.....",
        ".rrrrrrrrrr.....",
        ".drrrrkrrrr.....",
        "..drrrrrrrd.....",
        "..ddrrrrrdd.....",
        "...dddddd.......",
    ],
    "wink": [
        ".......ggll.",
        "......g.lll.",
        ".....g......",
        "...rrrrrr...",
        "..rhhrrrrr..",
        ".rhhrrrrrrr.",
        ".rrrrrrrkrr.",
        ".rrrkkrrkrr.",
        ".rprrrrrrpr.",
        ".drrkrrrrkr.",
        "..drrkkkkrd.",
        "..ddrrrrrdd.",
        "...dddddd...",
    ],
    "laughing": [
        ".......ggll.",
        "......g.lll.",
        ".....g......",
        "...rrrrrr...",
        "..rhhrrrrr..",
        ".rhhrrrrrrr.",
        ".rrrkrrrkrr.",
        ".rrkrkrkrkr.",
        ".rprrrrrrpr.",
        ".drkkkkkkrr.",
        "..drkqqqkrd.",
        "..ddrkkkrdd.",
        "...dddddd...",
    ],
    "love": [
        ".......ggll..q.q",
        "......g.lll..qqq",
        ".....g........q.",
        "...rrrrrr.......",
        "..rhhrrrrr......",
        ".rhqrqrqrqr.....",
        ".rrqqqrqqqr.....",
        ".rrrqrrrqrr.....",
        ".rrrrrrrrrr.....",
        ".drrkrrrrkr.....",
        "..drrkkkkrd.....",
        "..ddrrrrrdd.....",
        "...dddddd.......",
    ],
    "surprised": [
        ".......ggll.....",
        "......g.lll..y..",
        ".....g.......y..",
        "...rrrrrr....y..",
        "..rhhrrrrr......",
        ".rhhrrrrrrr..y..",
        ".rrrkrrrkrr.....",
        ".rrrkrrrkrr.....",
        ".rrrrrrrrrr.....",
        ".drrrkkrrrr.....",
        "..drrkkrrrd.....",
        "..ddrrrrrdd.....",
        "...dddddd.......",
    ],
    "cool": [
        ".......ggll.",
        "......g.lll.",
        ".....g......",
        "...rrrrrr...",
        "..rhhrrrrr..",
        ".rhhrrrrrrr.",
        ".rkwkkkkwkr.",
        ".rkkkrrkkkr.",
        ".rrrrrrrrrr.",
        ".drrrrrrrkr.",
        "..drrrkkkrd.",
        "..ddrrrrrdd.",
        "...dddddd...",
    ],
    "thinking": [
        ".......ggll...zz",
        "......g.lll.....",
        ".....g.......z..",
        "...rrrrrr.......",
        "..rhhrrrrr..z...",
        ".rhhrrkrrkr.....",
        ".rrrrrkrrkr.....",
        ".rrrrrrrrrr.....",
        ".rrrrrrrrrr.....",
        ".drrrrrrrrr.....",
        "..drrrkkrrd.....",
        "..ddrrrrrdd.....",
        "...dddddd.......",
    ],
}


def png(path, rows, scale):
    w, h = len(rows[0]) * scale, len(rows) * scale
    raw = bytearray()
    for row in rows:
        line = bytearray()
        for ch in row:
            px = (0, 0, 0, 0) if ch == "." else PAL[ch] + (255,)
            line += bytes(px) * scale
        for _ in range(scale):
            raw += b"\0" + line
    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    data = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b""))
    open(path, "wb").write(data)


here = os.path.dirname(os.path.abspath(__file__))
for mood, rows in MOODS.items():
    assert all(len(r) == len(rows[0]) for r in rows), mood
    png(os.path.join(here, "stony-%s.png" % mood), rows, 8)
    png(os.path.join(here, "stony-%s-small.png" % mood), rows, 4)

# Spritesheet: every mood in a row of 16x16 cells (happy, excited, sad,
# sleepy), each sitting at the bottom of its cell. stony-sheet.png is the real
# size for games and code; stony-sheet-x8.png is blown up to look at.
CELL = 16
sheet = ["." * (CELL * len(MOODS)) for _ in range(CELL)]
for i, rows in enumerate(MOODS.values()):
    top = CELL - len(rows)
    for y, row in enumerate(rows):
        row = row.ljust(CELL, ".")
        line = sheet[top + y]
        sheet[top + y] = line[:i * CELL] + row + line[(i + 1) * CELL:]
png(os.path.join(here, "stony-sheet.png"), sheet, 1)
png(os.path.join(here, "stony-sheet-x8.png"), sheet, 8)
print("drew", ", ".join(MOODS), "and the spritesheet")
