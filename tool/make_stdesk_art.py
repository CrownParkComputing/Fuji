#!/usr/bin/env python3
"""App icon for STDesk, the Atari ST emulator.

    python3 tool/make_stdesk_art.py

WHAT IT DRAWS, AND WHY THAT.

RASTER BARS. The ST's video chip is called the Shifter: it clocks bitplanes
out of memory and turns them into a picture, and rewriting its palette
registers mid-scanline is how a demo draws bars of colour down the screen.
That effect is the single most recognisable thing the machine ever did, and
to anyone who owned one it says "Atari ST" instantly, without a word of type
in the image.

(The app was briefly going to be called Shifter, which would have made the
mark and the name the same joke. The name was taken; the picture is still
the right picture.)

DELIBERATELY SHARES NOTHING WITH THE OTHER APPS. Apple rejected the Retro-*
family under guideline 4.3 for being too alike, so each app that came out of
that has its own look and no shared furniture: DOSDeck is an amber DOS prompt
on a CRT, this is colour on black. Nobody would take one for a version of the
other, which is the entire point.

It also replaces a placeholder -- a plain orange diamond on navy -- that said
nothing about the app at all.
"""

from __future__ import annotations

import os

from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SIZE = 1024

# An ST screen at rest: near-black, faintly blue rather than neutral.
BG_TOP = (9, 10, 20)
BG_BOTTOM = (4, 4, 10)

# Bar hues. Saturated primaries and secondaries, which is what a 512-colour
# palette actually looked like reaching for a rainbow -- not a smooth modern
# gradient.
BARS = [
    (255, 64, 96),     # red
    (255, 160, 32),    # orange
    (248, 232, 64),    # yellow
    (72, 224, 128),    # green
    (64, 176, 255),    # cyan
    (176, 112, 255),   # violet
]


def vertical_gradient(size, top, bottom):
    w, h = size
    strip = Image.new("RGB", (1, h))
    px = strip.load()
    for y in range(h):
        t = y / max(1, h - 1)
        px[0, y] = tuple(round(a + (b - a) * t) for a, b in zip(top, bottom))
    return strip.resize((w, h), Image.BILINEAR).convert("RGBA")


def raster_bar(width, height, colour, radius):
    """One bar, lit from its own middle.

    A raster bar is not a flat rectangle: the colour is brightest along the
    centre line and falls away above and below it, because the palette is
    being rewritten every scanline and the eye reads the run as a tube of
    light. Flat rectangles read as a chart.
    """
    bar = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    px = bar.load()
    r, g, b = colour
    for y in range(height):
        # 1.0 at the centre row, 0 at the edges, eased so the falloff is
        # soft rather than linear.
        t = 1.0 - abs((y / (height - 1)) * 2.0 - 1.0)
        f = t * t * (3 - 2 * t)
        # Never fully black at the edge, or the bars look like separate
        # objects instead of one lit band.
        k = 0.22 + 0.78 * f
        px_row = (round(r * k), round(g * k), round(b * k), 255)
        for x in range(width):
            px[x, y] = px_row

    mask = Image.new("L", (width, height), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, width - 1, height - 1),
                                           radius=radius, fill=255)
    bar.putalpha(mask)
    return bar


def scanlines(img, spacing, strength):
    dark = Image.new("RGBA", img.size, (0, 0, 0, strength))
    mask = Image.new("L", img.size, 0)
    d = ImageDraw.Draw(mask)
    for y in range(0, img.size[1], spacing):
        d.line([(0, y), (img.size[0], y)], fill=255, width=max(1, spacing // 3))
    img.paste(dark, (0, 0), mask)
    return img


def icon():
    w = h = SIZE
    img = vertical_gradient((w, h), BG_TOP, BG_BOTTOM)

    n = len(BARS)
    bar_h = round(h * 0.098)
    gap = round(h * 0.020)
    bar_w = round(w * 0.60)
    radius = bar_h // 2

    block_h = n * bar_h + (n - 1) * gap
    y = (h - block_h) // 2

    # The horizontal step is the whole idea: each bar starts a little further
    # along than the one above it, so the stack reads as mid-frame movement --
    # the palette being SHIFTED down the screen -- rather than as a stack of
    # stripes. A centred block of equal bars is a flag.
    step = round(w * 0.035)
    x0 = (w - bar_w - step * (n - 1)) // 2

    glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    for i, colour in enumerate(BARS):
        bar = raster_bar(bar_w, bar_h, colour, radius)
        pos = (x0 + step * i, y + i * (bar_h + gap))
        glow.alpha_composite(bar, pos)
    # The light each bar throws, laid in twice so it is actually visible.
    blurred = glow.filter(ImageFilter.GaussianBlur(SIZE * 0.028))
    img.alpha_composite(blurred)
    img.alpha_composite(blurred)
    img.alpha_composite(glow)

    img = scanlines(img, max(3, round(h / 170)), 38)

    # A tube is brighter in the middle.
    vign = Image.new("L", (w, h), 0)
    ImageDraw.Draw(vign).ellipse((-w * 0.22, -h * 0.22, w * 1.22, h * 1.22), fill=255)
    vign = vign.filter(ImageFilter.GaussianBlur(w * 0.11))
    from PIL import ImageOps
    img.paste(Image.new("RGBA", (w, h), (0, 0, 0, 110)), (0, 0), ImageOps.invert(vign))
    return img


def main():
    out = os.path.join(HERE, "STDesk", "Assets.xcassets",
                       "AppIcon.appiconset", "AppIcon-1024.png")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    # RGB, not RGBA: App Store Connect rejects a marketing icon outright for
    # carrying an alpha channel.
    icon().convert("RGB").save(out)
    print(f"icon: 1024x1024 -> {out}")


if __name__ == "__main__":
    main()
