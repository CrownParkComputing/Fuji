#include "fuji_gem.h"

#include <string.h>

void gem_begin(GemCtx *g, SDL_Renderer *r, int logical_w, int logical_h)
{
    g->r = r;
    g->w = logical_w;
    g->h = logical_h;
    g->scale = 1.0f;
}

void gem_colour(GemCtx *g, Uint8 r, Uint8 gg, Uint8 b)
{
    SDL_SetRenderDrawColor(g->r, r, gg, b, 255);
}

void gem_fill(GemCtx *g, SDL_FRect rect)
{
    SDL_RenderFillRect(g->r, &rect);
}

void gem_frame(GemCtx *g, SDL_FRect rect)
{
    gem_colour(g, 0, 0, 0);
    SDL_RenderRect(g->r, &rect);
}

void gem_box(GemCtx *g, SDL_FRect rect)
{
    gem_colour(g, 255, 255, 255);
    SDL_RenderFillRect(g->r, &rect);
    gem_frame(g, rect);
}

void gem_dither(GemCtx *g, SDL_FRect rect, Uint8 r, Uint8 gg, Uint8 b)
{
    /* Solid ground first, then every other pixel in black. Two passes of
     * whole rows is far fewer draw calls than one point per pixel and looks
     * identical: the ST's pattern is a column checker, so a row drawn with a
     * one-pixel gap is the same thing. */
    gem_colour(g, r, gg, b);
    SDL_RenderFillRect(g->r, &rect);

    gem_colour(g, 0, 0, 0);
    for (float y = rect.y; y < rect.y + rect.h; y += 1.0f) {
        const float phase = ((int)(y - rect.y) & 1) ? 1.0f : 0.0f;
        for (float x = rect.x + phase; x < rect.x + rect.w; x += 2.0f) {
            SDL_RenderPoint(g->r, x, y);
        }
    }
}

void gem_text(GemCtx *g, float x, float y, const char *s, float size)
{
    if (!s || !*s) return;
    /* SDL's debug font is a fixed 8x8. Scaling the renderer is the only way
     * to draw it larger, and it has to be put back or everything after this
     * call is drawn at the wrong size -- which looks like a layout bug
     * several functions away from the cause. */
    float sx, sy;
    SDL_GetRenderScale(g->r, &sx, &sy);
    SDL_SetRenderScale(g->r, sx * size, sy * size);
    SDL_RenderDebugText(g->r, x / size, y / size, s);
    SDL_SetRenderScale(g->r, sx, sy);
}

float gem_text_w(const char *s, float size)
{
    return s ? (float)strlen(s) * 8.0f * size : 0.0f;
}

bool gem_hit(SDL_FRect rect, float x, float y)
{
    return x >= rect.x && x < rect.x + rect.w &&
           y >= rect.y && y < rect.y + rect.h;
}

bool gem_button(GemCtx *g, SDL_FRect rect, const char *label, bool dflt)
{
    gem_box(g, rect);
    if (dflt) {
        SDL_FRect inner = { rect.x + 1, rect.y + 1, rect.w - 2, rect.h - 2 };
        gem_frame(g, inner);
    }
    gem_colour(g, 0, 0, 0);
    const float tw = gem_text_w(label, 1.0f);
    gem_text(g, rect.x + (rect.w - tw) / 2.0f,
                rect.y + (rect.h - 8.0f) / 2.0f, label, 1.0f);
    return false;
}

SDL_FRect gem_window(GemCtx *g, SDL_FRect rect, const char *title,
                     SDL_FRect *out_close)
{
    gem_box(g, rect);

    const float bar_h = 19.0f;
    SDL_FRect bar = { rect.x + 1, rect.y + 1, rect.w - 2, bar_h };
    gem_colour(g, 255, 255, 255);
    SDL_RenderFillRect(g->r, &bar);

    /* GEM fills the unused half of a title bar with horizontal rules. It is
     * the single most recognisable thing about a GEM window. */
    gem_colour(g, 0, 0, 0);
    for (float y = bar.y + 3; y < bar.y + bar_h - 3; y += 2.0f) {
        SDL_RenderLine(g->r, bar.x + 2, y, bar.x + bar.w - 3, y);
    }

    SDL_FRect close = { bar.x, bar.y, bar_h, bar_h };
    gem_box(g, close);
    SDL_FRect mark = { close.x + 5, close.y + 5, bar_h - 10, bar_h - 10 };
    gem_colour(g, 0, 0, 0);
    SDL_RenderFillRect(g->r, &mark);
    if (out_close) *out_close = close;

    const float tw = gem_text_w(title, 1.0f);
    SDL_FRect label = { bar.x + (bar.w - tw) / 2.0f - 6, bar.y,
                        tw + 12, bar_h };
    gem_colour(g, 255, 255, 255);
    SDL_RenderFillRect(g->r, &label);
    gem_colour(g, 0, 0, 0);
    gem_text(g, label.x + 6, bar.y + (bar_h - 8) / 2.0f, title, 1.0f);

    SDL_FRect line = { rect.x + 1, bar.y + bar_h, rect.w - 2, 1 };
    gem_colour(g, 0, 0, 0);
    SDL_RenderFillRect(g->r, &line);

    SDL_FRect interior = { rect.x + 1, bar.y + bar_h + 1,
                           rect.w - 2, rect.h - bar_h - 3 };
    gem_colour(g, 255, 255, 255);
    SDL_RenderFillRect(g->r, &interior);
    return interior;
}
