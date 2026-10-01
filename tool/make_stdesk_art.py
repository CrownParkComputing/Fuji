#!/usr/bin/env python3
"""App icon for ST Desk, the Atari ST emulator.

    python3 tool/make_stdesk_art.py

WHAT IT DRAWS, AND WHY THAT.

The GEM desktop: the dithered green ground, the white menu bar, and a drive
icon sitting on it. That is literally what the app is called and literally
what it shows you — with EmuTOS aboard it boots straight to this screen, so
the icon is a picture of the first thing the app does.

Anyone who used an ST recognises it instantly, and nobody else needs to:
"green desktop, menu bar, floppy" reads as a computer from the era even if
you have never seen TOS.

THE PREVIOUS ICON WAS DRAWN FOR A DIFFERENT NAME. It was raster bars, which
are what you get by rewriting the Shifter's palette registers mid-scanline —
a good mark when the app was going to be called Shifter, because the name
and the picture were one idea. That name was taken. Raster bars say nothing
about a desktop, and six stacked colour bars read as a generic rainbow once
the pun is gone.

DELIBERATELY SHARES NOTHING WITH THE OTHER APPS. Apple rejected the Retro-*
family under guideline 4.3 for being too alike, so each app out of that has
its own look: DOSDeck is an amber DOS prompt on a black CRT, this is a green
GEM desktop. No shared furniture, no shared palette.
"""

from __future__ import annotations

import os

from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SIZE = 1024

# The ST desktop's green. GEM dithered two shades in a checkerboard rather
# than using a solid fill, which is why the real thing shimmers slightly;
# the two values below are that pair.
DESK_A = (0, 161, 85)
DESK_B = (0, 125, 66)

BAR = (248, 248, 248)          # menu bar
INK = (14, 14, 14)             # GEM's black outlines and text
PAPER = (250, 250, 250)        # icon fill


def dithered_ground(size):
    """The desktop pattern: a 2px checkerboard of two greens."""
    w, h = size
    img = Image.new("RGB", (w, h), DESK_A)
    px = img.load()
    cell = max(2, w // 256)
    for y in range(h):
        for x in range(w):
            if ((x // cell) + (y // cell)) % 2:
                px[x, y] = DESK_B
    return img


def floppy(size, radius):
    """A 3.5" disk in GEM's style: flat, heavy black outline, no gradient.

    A drive icon would be more literally the GEM desktop, but a disk is the
    more legible silhouette once this is 80 pixels across, and it is the
    thing the app actually asks you for.
    """
    s = size
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    lw = max(3, s // 26)

    # Body, with the cut corner a 3.5" disk has at top right.
    cut = s * 0.22
    body = [(0, 0), (s - cut, 0), (s - 1, cut), (s - 1, s - 1), (0, s - 1)]
    d.polygon(body, fill=PAPER)
    d.line(body + [body[0]], fill=INK, width=lw, joint="curve")

    # Shutter: the metal slider across the top.
    sx0, sx1 = s * 0.26, s * 0.70
    sy0, sy1 = s * 0.06, s * 0.36
    d.rectangle((sx0, sy0, sx1, sy1), fill=INK)
    # The window in the shutter, offset left as on a real disk.
    d.rectangle((sx0 + s * 0.055, sy0 + s * 0.05,
                 sx0 + s * 0.215, sy1 - s * 0.05), fill=PAPER)

    # Label: the big white block that makes a floppy read as a floppy.
    lx0, ly0, lx1, ly1 = s * 0.14, s * 0.46, s * 0.86, s * 0.90
    d.rectangle((lx0, ly0, lx1, ly1), fill=PAPER, outline=INK, width=lw)
    # Two ruled lines on the label. Not text: at icon sizes lettering turns
    # to mud, and two bars read as "something written here" at any size.
    for i in (0, 1):
        y = ly0 + (ly1 - ly0) * (0.34 + i * 0.30)
        d.rectangle((lx0 + s * 0.08, y - lw * 0.6,
                     lx1 - s * 0.08, y + lw * 0.6), fill=INK)
    return img


def icon():
    w = h = SIZE
    img = dithered_ground((w, h)).convert("RGBA")
    d = ImageDraw.Draw(img)

    # The menu bar, with GEM's black rule under it.
    bar_h = round(h * 0.145)
    d.rectangle((0, 0, w, bar_h), fill=BAR)
    d.rectangle((0, bar_h, w, bar_h + max(3, h // 300)), fill=INK)
    # Menu titles, as blocks. Same reasoning as the label: words at this
    # scale are noise, blocks are legible.
    x = round(w * 0.06)
    for width in (0.10, 0.07, 0.08, 0.11):
        bw = round(w * width)
        d.rectangle((x, bar_h * 0.34, x + bw, bar_h * 0.66), fill=INK)
        x += bw + round(w * 0.045)

    # The disk, sat on the desktop and slightly below centre so the menu bar
    # does not crowd it.
    fs = round(w * 0.46)
    fx = (w - fs) // 2
    fy = bar_h + round((h - bar_h - fs) * 0.52)
    disk = floppy(fs, radius=0)

    # A soft drop shadow: GEM itself had none, but without one the disk sits
    # flat against a busy dither and the silhouette stops reading when small.
    shadow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    shadow.paste(Image.new("RGBA", (fs, fs), (0, 0, 0, 120)),
                 (fx + round(w * 0.012), fy + round(w * 0.012)),
                 disk.split()[3])
    img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(w * 0.012)))
    img.alpha_composite(disk, (fx, fy))
    return img.convert("RGB")


def main():
    out = os.path.join(HERE, "STDesk", "Assets.xcassets",
                       "AppIcon.appiconset", "AppIcon-1024.png")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    # RGB, not RGBA: App Store Connect rejects a marketing icon outright for
    # carrying an alpha channel.
    icon().save(out)
    print(f"icon: 1024x1024 -> {out}")


if __name__ == "__main__":
    main()
