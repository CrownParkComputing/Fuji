/*
 * fuji_gem - the small part of GEM's look that Fuji actually needs.
 *
 * Fuji's launcher is the ST's own desktop, not a list of games with a sidebar.
 * That is a deliberate choice: every other emulator front end in this estate
 * is a media grid beside a navigation rail, and shipping a ninth one is what
 * got the previous generation rejected as duplicates. A machine whose desktop
 * IS its identity should look like its desktop.
 *
 * So this draws GEM: the dithered desktop, the white menu bar, the outlined
 * boxes with a one-pixel black border and no gradient anywhere. It is drawn
 * rather than themed -- there is no toolkit here, and none of it is shared
 * with another app.
 */
#ifndef FUJI_GEM_H
#define FUJI_GEM_H

#include <SDL3/SDL.h>
#include <stdbool.h>

/* TOS's desktop palette. The green is the one an ST came up in from the
 * factory in low resolution; the rest of GEM is black on white. */
#define GEM_DESKTOP_R   0x00
#define GEM_DESKTOP_G   0xA0
#define GEM_DESKTOP_B   0x60

typedef struct {
    SDL_Renderer *r;
    float         scale;     /* logical GEM pixel -> device pixel */
    int           w, h;      /* logical size, in GEM pixels */
} GemCtx;

void gem_begin(GemCtx *g, SDL_Renderer *r, int logical_w, int logical_h);

void gem_colour(GemCtx *g, Uint8 r, Uint8 gg, Uint8 b);
void gem_fill(GemCtx *g, SDL_FRect rect);
void gem_frame(GemCtx *g, SDL_FRect rect);          /* 1px black outline */
void gem_box(GemCtx *g, SDL_FRect rect);            /* white fill + outline */

/* The 50% checker the ST desktop is tiled with. Drawn as real alternating
 * pixels rather than a blended colour: at 1:1 it is the actual pattern, and
 * it is what makes the desktop read as an ST rather than as a green page. */
void gem_dither(GemCtx *g, SDL_FRect rect, Uint8 r, Uint8 gg, Uint8 b);

/* Text in SDL's built-in 8x8 font, scaled to `size` GEM pixels per cell.
 * GEM's own font is 8x16; drawing at size 2 in the vertical gives the same
 * proportions without shipping a font table. */
void gem_text(GemCtx *g, float x, float y, const char *s, float size);
float gem_text_w(const char *s, float size);

/* A GEM button: outlined box, centred label, thicker border when it is the
 * default. Returns true if `p` is inside it. */
bool gem_button(GemCtx *g, SDL_FRect rect, const char *label, bool dflt);
bool gem_hit(SDL_FRect rect, float x, float y);

/* A GEM window frame: title bar of horizontal rules with a close box, and a
 * white interior. Returns the interior rect. */
SDL_FRect gem_window(GemCtx *g, SDL_FRect rect, const char *title,
                     SDL_FRect *out_close);

#endif
