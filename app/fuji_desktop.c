#include "fuji_desktop.h"
#include "atarist_bridge.h"

#include <stdio.h>
#include <string.h>

#define MENU_H      19.0f
#define ICON_W      72.0f
#define ICON_H      64.0f
#define ROW_H       12.0f

/* Where each icon sits on the desktop. Laid out down the left edge, the way
 * TOS puts them, rather than centred: an ST desktop has its drives in the
 * top-left corner and empty space everywhere else, and that empty space is
 * part of what makes it recognisable. */
static SDL_FRect icon_rect(int i)
{
    /* Two by two, drives on the left and what they need on the right: A above
     * C, B above the ROM. TOS puts its drives in a block in the corner and
     * leaves the rest of the desktop empty, and that emptiness is part of what
     * makes the screen read as an ST rather than as a launcher. */
    const float col = (float)(i % 2);
    const float row = (float)(i / 2);
    return (SDL_FRect){ 28.0f + col * (ICON_W + 40.0f),
                        MENU_H + 28.0f + row * (ICON_H + 30.0f),
                        ICON_W, ICON_H };
}

const char *fuji_slot_label(FujiSlot s)
{
    switch (s) {
    case FUJI_SLOT_A:   return "FLOPPY A";
    case FUJI_SLOT_B:   return "FLOPPY B";
    case FUJI_SLOT_C:   return "HARD DISK";
    case FUJI_SLOT_TOS: return "TOS ROM";
    default:            return "";
    }
}

void fuji_desktop_init(FujiDesktop *d, const char *start_dir)
{
    memset(d, 0, sizeof *d);
    d->view      = FUJI_VIEW_DESKTOP;
    d->machine   = ATARIST_MACHINE_ST;
    /* A colour monitor, always, as the default. TOS reads the monitor type at
     * boot and picks its screen mode from it: fit a mono monitor and the
     * machine comes up in ST-HIGH, 640x400 in two colours, where essentially
     * no game runs. It looks like a machine that booted and then refused to
     * start anything. */
    d->monitor   = ATARIST_MONITOR_RGB;
    d->memory_kb = 1024;
    snprintf(d->dir.path, sizeof d->dir.path, "%s", start_dir);
}

void fuji_desktop_free(FujiDesktop *d)
{
    fuji_dir_free(&d->dir);
}

/* ------------------------------------------------------------------ drawing */

static void draw_floppy_icon(GemCtx *g, SDL_FRect r, bool occupied)
{
    /* A 3.5" disk: square body, shutter at the top, label at the bottom. */
    SDL_FRect body = { r.x + 14, r.y + 4, r.w - 28, r.h - 24 };
    gem_colour(g, 255, 255, 255);
    SDL_RenderFillRect(g->r, &body);
    gem_frame(g, body);

    SDL_FRect shutter = { body.x + body.w * 0.30f, body.y + 3,
                          body.w * 0.40f, body.h * 0.34f };
    gem_colour(g, 0, 0, 0);
    SDL_RenderFillRect(g->r, &shutter);

    SDL_FRect label = { body.x + 4, body.y + body.h * 0.52f,
                        body.w - 8, body.h * 0.38f };
    gem_colour(g, occupied ? 0 : 255, occupied ? 0 : 255, occupied ? 0 : 255);
    SDL_RenderFillRect(g->r, &label);
    gem_frame(g, label);
}

static void draw_disk_icon(GemCtx *g, SDL_FRect r, bool occupied)
{
    SDL_FRect body = { r.x + 8, r.y + 10, r.w - 16, r.h - 34 };
    gem_colour(g, 255, 255, 255);
    SDL_RenderFillRect(g->r, &body);
    gem_frame(g, body);
    SDL_FRect slot = { body.x + 5, body.y + body.h - 9, body.w - 10, 4 };
    gem_colour(g, occupied ? 0 : 255, occupied ? 0 : 255, occupied ? 0 : 255);
    SDL_RenderFillRect(g->r, &slot);
    gem_frame(g, slot);
}

static void draw_rom_icon(GemCtx *g, SDL_FRect r, bool occupied)
{
    /* A DIP chip, legs and all. The TOS ROM is a chip, not a file, and the
     * app should say so: it is the one thing the user must supply, and an
     * empty one is why nothing boots. */
    SDL_FRect body = { r.x + 22, r.y + 8, r.w - 44, r.h - 30 };
    gem_colour(g, occupied ? 255 : 160, occupied ? 255 : 160,
                  occupied ? 255 : 160);
    SDL_RenderFillRect(g->r, &body);
    gem_frame(g, body);
    gem_colour(g, 0, 0, 0);
    for (float y = body.y + 4; y < body.y + body.h - 3; y += 6.0f) {
        SDL_RenderLine(g->r, body.x - 5, y, body.x - 1, y);
        SDL_RenderLine(g->r, body.x + body.w, y, body.x + body.w + 4, y);
    }
}

static void draw_icon(GemCtx *g, FujiDesktop *d, int i)
{
    const SDL_FRect r = icon_rect(i);
    const bool occupied = d->slot[i][0] != '\0';

    switch (i) {
    case FUJI_SLOT_A:
    case FUJI_SLOT_B:   draw_floppy_icon(g, r, occupied); break;
    case FUJI_SLOT_C:   draw_disk_icon(g, r, occupied);   break;
    default:            draw_rom_icon(g, r, occupied);    break;
    }

    const char *label = fuji_slot_label((FujiSlot)i);
    const float tw = gem_text_w(label, 1.0f);
    SDL_FRect plate = { r.x + (r.w - tw) / 2.0f - 2, r.y + r.h - 12,
                        tw + 4, 10 };
    gem_colour(g, 255, 255, 255);
    SDL_RenderFillRect(g->r, &plate);
    gem_colour(g, 0, 0, 0);
    gem_text(g, plate.x + 2, plate.y + 1, label, 1.0f);

    if (occupied) {
        const char *base = strrchr(d->slot[i], '/');
        base = base ? base + 1 : d->slot[i];
        char shown[22];
        snprintf(shown, sizeof shown, "%s", base);
        const float bw = gem_text_w(shown, 1.0f);
        SDL_FRect bp = { r.x + (r.w - bw) / 2.0f - 2, r.y + r.h - 1,
                         bw + 4, 10 };
        gem_colour(g, 255, 255, 255);
        SDL_RenderFillRect(g->r, &bp);
        gem_frame(g, bp);
        gem_colour(g, 0, 0, 0);
        gem_text(g, bp.x + 2, bp.y + 1, shown, 1.0f);
    }
}

/* The menu bar. Titles only -- GEM drops menus on hover, which a touch screen
 * does not have, so each title is a button that does one thing. */
static const char *kMenu[] = { " Fuji ", " Machine ", " Monitor ", " Boot " };
#define MENU_COUNT ((int)(sizeof kMenu / sizeof kMenu[0]))

static SDL_FRect menu_rect(GemCtx *g, int i)
{
    float x = 0.0f;
    for (int k = 0; k < i; ++k) x += gem_text_w(kMenu[k], 1.0f);
    (void)g;
    return (SDL_FRect){ x, 0.0f, gem_text_w(kMenu[i], 1.0f), MENU_H };
}

static const char *machine_name(int m)
{
    switch (m) {
    case ATARIST_MACHINE_ST:       return "ST";
    case ATARIST_MACHINE_MEGA_ST:  return "Mega ST";
    case ATARIST_MACHINE_STE:      return "STE";
    case ATARIST_MACHINE_MEGA_STE: return "Mega STE";
    case ATARIST_MACHINE_TT:       return "TT";
    case ATARIST_MACHINE_FALCON:   return "Falcon";
    default:                       return "?";
    }
}

static const char *monitor_name(int m)
{
    switch (m) {
    case ATARIST_MONITOR_MONO: return "Mono";
    case ATARIST_MONITOR_RGB:  return "Colour";
    case ATARIST_MONITOR_VGA:  return "VGA";
    case ATARIST_MONITOR_TV:   return "TV";
    default:                   return "?";
    }
}

static void draw_menubar(FujiDesktop *d, GemCtx *g)
{
    SDL_FRect bar = { 0, 0, (float)g->w, MENU_H };
    gem_colour(g, 255, 255, 255);
    SDL_RenderFillRect(g->r, &bar);
    gem_colour(g, 0, 0, 0);
    SDL_RenderLine(g->r, 0, MENU_H, (float)g->w, MENU_H);

    for (int i = 0; i < MENU_COUNT; ++i) {
        const SDL_FRect m = menu_rect(g, i);
        gem_text(g, m.x, (MENU_H - 8) / 2.0f, kMenu[i], 1.0f);
    }

    /* The right-hand end states the machine, the way TOS states free memory.
     * It is the one thing you need to know before booting and the commonest
     * reason a title does nothing. */
    char right[64];
    snprintf(right, sizeof right, "%s  %dK  %s",
             machine_name(d->machine), d->memory_kb, monitor_name(d->monitor));
    gem_text(g, (float)g->w - gem_text_w(right, 1.0f) - 6,
             (MENU_H - 8) / 2.0f, right, 1.0f);
}

static void draw_message(FujiDesktop *d, GemCtx *g)
{
    if (!d->message[0]) return;
    SDL_FRect strip = { 0, (float)g->h - 16.0f, (float)g->w, 16.0f };
    gem_colour(g, 255, 255, 255);
    SDL_RenderFillRect(g->r, &strip);
    gem_colour(g, 0, 0, 0);
    SDL_RenderLine(g->r, 0, strip.y, (float)g->w, strip.y);
    gem_text(g, 6, strip.y + 4, d->message, 1.0f);
}

static void draw_selector(FujiDesktop *d, GemCtx *g)
{
    SDL_FRect win = { 24, MENU_H + 16, (float)g->w - 48,
                      (float)g->h - MENU_H - 48 };
    SDL_FRect close;
    SDL_FRect in = gem_window(g, win, d->dirs_only ? "Choose a folder"
                                                   : "Insert a disk", &close);

    gem_colour(g, 0, 0, 0);
    gem_text(g, in.x + 4, in.y + 3, d->dir.path, 1.0f);

    const float list_y = in.y + 16;
    const int rows = (int)((in.h - 24 - 22) / ROW_H);

    for (int i = 0; i < rows; ++i) {
        const int idx = d->sel_top + i;
        if (idx >= d->dir.count) break;
        const FujiEntry *e = &d->dir.items[idx];
        SDL_FRect row = { in.x + 2, list_y + (float)i * ROW_H,
                          in.w - 4, ROW_H };
        if (idx == d->sel_index) {
            gem_colour(g, 0, 0, 0);
            SDL_RenderFillRect(g->r, &row);
            gem_colour(g, 255, 255, 255);
        } else {
            gem_colour(g, 0, 0, 0);
        }
        char line[288];
        snprintf(line, sizeof line, "%s%s", e->is_dir ? "\\ " : "  ", e->name);
        gem_text(g, row.x + 3, row.y + 2, line, 1.0f);
    }

    SDL_FRect ok     = { in.x + in.w - 150, in.y + in.h - 22, 64, 18 };
    SDL_FRect cancel = { in.x + in.w - 78,  in.y + in.h - 22, 64, 18 };
    gem_button(g, ok, "OK", true);
    gem_button(g, cancel, "Cancel", false);
}

static void draw_about(FujiDesktop *d, GemCtx *g)
{
    (void)d;
    SDL_FRect win = { (float)g->w / 2 - 170, (float)g->h / 2 - 90, 340, 180 };
    SDL_FRect close;
    SDL_FRect in = gem_window(g, win, "Fuji", &close);

    gem_colour(g, 0, 0, 0);
    float y = in.y + 10;
    const char *lines[] = {
        "Fuji - an Atari ST, on iOS.",
        "",
        "Emulation by Hatari, which is not ours.",
        "GPL-2.0-or-later. Full text in Credits.",
        "github.com/CrownParkComputing/hatari",
        "",
        "TOS is Atari's and is not included.",
        "Supply your own ROM.",
    };
    for (size_t i = 0; i < sizeof lines / sizeof lines[0]; ++i) {
        gem_text(g, in.x + 12, y, lines[i], 1.0f);
        y += 12;
    }
    char ver[96];
    snprintf(ver, sizeof ver, "Core: %s", atarist_core_hatari_version());
    gem_text(g, in.x + 12, y + 4, ver, 1.0f);
}

void fuji_desktop_draw(FujiDesktop *d, GemCtx *g)
{
    gem_dither(g, (SDL_FRect){ 0, 0, (float)g->w, (float)g->h },
               GEM_DESKTOP_R, GEM_DESKTOP_G, GEM_DESKTOP_B);
    draw_menubar(d, g);
    for (int i = 0; i < FUJI_SLOT_COUNT; ++i) draw_icon(g, d, i);

    if (d->view == FUJI_VIEW_SELECTOR) draw_selector(d, g);
    if (d->view == FUJI_VIEW_ABOUT)    draw_about(d, g);
    draw_message(d, g);
}

/* ------------------------------------------------------------------ input */

static void open_selector(FujiDesktop *d, FujiSlot s)
{
    d->selecting = s;
    d->dirs_only = (s == FUJI_SLOT_C);
    d->sel_index = 0;
    d->sel_top   = 0;
    if (!fuji_dir_read(&d->dir, d->dir.path)) {
        /* The tail of the path, not the head: a message box is 256 bytes and
         * a path can be 1024, and the part that identifies the directory is
         * at the end. */
        const size_t n = strlen(d->dir.path);
        const char *tail = (n > 200) ? d->dir.path + n - 200 : d->dir.path;
        snprintf(d->message, sizeof d->message, "Cannot read %s%.200s",
                 (tail == d->dir.path) ? "" : "...", tail);
        return;
    }
    d->view = FUJI_VIEW_SELECTOR;
    d->message[0] = '\0';
}

static void selector_choose(FujiDesktop *d)
{
    if (d->sel_index < 0 || d->sel_index >= d->dir.count) return;
    const FujiEntry *e = &d->dir.items[d->sel_index];

    if (e->is_dir) {
        char next[1024];
        fuji_path_join(next, sizeof next, d->dir.path, e->name);
        /* Choosing the GEMDOS folder means choosing a directory, so entering
         * one and accepting one are the same gesture on different buttons:
         * a tap walks in, OK takes what is highlighted. */
        if (fuji_dir_read(&d->dir, next)) {
            d->sel_index = 0;
            d->sel_top = 0;
        }
        return;
    }
    fuji_path_join(d->slot[d->selecting], sizeof d->slot[0],
                   d->dir.path, e->name);
    d->view = FUJI_VIEW_DESKTOP;
}

static void selector_accept_dir(FujiDesktop *d)
{
    if (d->dirs_only) {
        snprintf(d->slot[FUJI_SLOT_C], sizeof d->slot[0], "%s", d->dir.path);
        d->view = FUJI_VIEW_DESKTOP;
        return;
    }
    selector_choose(d);
}

bool fuji_desktop_click(FujiDesktop *d, GemCtx *g, float x, float y)
{
    if (d->view == FUJI_VIEW_ABOUT) { d->view = FUJI_VIEW_DESKTOP; return false; }

    if (d->view == FUJI_VIEW_SELECTOR) {
        SDL_FRect win = { 24, MENU_H + 16, (float)g->w - 48,
                          (float)g->h - MENU_H - 48 };
        SDL_FRect close = { win.x + 1, win.y + 1, 19, 19 };
        if (gem_hit(close, x, y)) { d->view = FUJI_VIEW_DESKTOP; return false; }

        SDL_FRect in = { win.x + 1, win.y + 21, win.w - 2, win.h - 23 };
        SDL_FRect ok     = { in.x + in.w - 150, in.y + in.h - 22, 64, 18 };
        SDL_FRect cancel = { in.x + in.w - 78,  in.y + in.h - 22, 64, 18 };
        if (gem_hit(cancel, x, y)) { d->view = FUJI_VIEW_DESKTOP; return false; }
        if (gem_hit(ok, x, y))     { selector_accept_dir(d);      return false; }

        const float list_y = in.y + 16;
        const int row = (int)((y - list_y) / ROW_H);
        if (row >= 0) {
            const int idx = d->sel_top + row;
            if (idx < d->dir.count) {
                if (idx == d->sel_index) selector_choose(d);
                else                     d->sel_index = idx;
            }
        }
        return false;
    }

    if (y < MENU_H) {
        for (int i = 0; i < MENU_COUNT; ++i) {
            if (!gem_hit(menu_rect(g, i), x, y)) continue;
            switch (i) {
            case 0: d->view = FUJI_VIEW_ABOUT; break;
            case 1: d->machine = (d->machine + 1) % 6; break;
            case 2: d->monitor = (d->monitor + 1) % 4; break;
            case 3:
                if (!d->slot[FUJI_SLOT_TOS][0]) {
                    snprintf(d->message, sizeof d->message,
                             "No TOS ROM. Tap the chip icon and choose one.");
                    return false;
                }
                return true;
            }
            return false;
        }
        return false;
    }

    for (int i = 0; i < FUJI_SLOT_COUNT; ++i) {
        if (!gem_hit(icon_rect(i), x, y)) continue;
        /* A second tap on an occupied drive ejects, which is what dragging it
         * to the trash did and is one gesture instead of two on a phone. */
        if (d->slot[i][0]) {
            d->slot[i][0] = '\0';
            snprintf(d->message, sizeof d->message, "%s emptied",
                     fuji_slot_label((FujiSlot)i));
        } else {
            open_selector(d, (FujiSlot)i);
        }
        return false;
    }
    d->message[0] = '\0';
    return false;
}

void fuji_desktop_key(FujiDesktop *d, int sdl_scancode)
{
    if (d->view != FUJI_VIEW_SELECTOR) {
        if (d->view == FUJI_VIEW_ABOUT) d->view = FUJI_VIEW_DESKTOP;
        return;
    }
    switch (sdl_scancode) {
    case SDL_SCANCODE_UP:
        if (d->sel_index > 0) d->sel_index--;
        if (d->sel_index < d->sel_top) d->sel_top = d->sel_index;
        break;
    case SDL_SCANCODE_DOWN:
        if (d->sel_index + 1 < d->dir.count) d->sel_index++;
        break;
    case SDL_SCANCODE_RETURN:
    case SDL_SCANCODE_KP_ENTER:
        selector_choose(d);
        break;
    case SDL_SCANCODE_ESCAPE:
        d->view = FUJI_VIEW_DESKTOP;
        break;
    default:
        break;
    }
}
