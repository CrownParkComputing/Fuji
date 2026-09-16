/*
 * Fuji - an Atari ST.
 *
 * One window, two things in it: the ST's desktop while you decide what to put
 * in the drives, and the ST itself once you switch it on.
 *
 * The same source builds for the desktop and for iOS. The desktop build is not
 * a convenience: it is the only place this code can be compiled and run
 * without a Mac, so it is where the launcher, the core integration and the
 * input mapping are actually proved.
 */
#include "fuji_desktop.h"
#include "fuji_gem.h"
#include "fuji_keymap.h"
#include "atarist_bridge.h"

#include <SDL3/SDL.h>
#include <SDL3/SDL_main.h>

#include <stdio.h>
#include <string.h>

/* The launcher is laid out in these units and letterboxed into the window, so
 * a phone, a tablet and a desktop window all get the same desktop rather than
 * three different ones. 640x400 is ST high resolution, which is the right
 * shape for a GEM desktop. */
#define LOGICAL_W 640
#define LOGICAL_H 400

typedef struct {
    SDL_Window   *window;
    SDL_Renderer *renderer;
    SDL_Texture  *screen;      /* the ST's framebuffer */
    int           screen_w, screen_h;
    int64_t       last_frame;
    FujiDesktop   desk;
    GemCtx        gem;
    bool          running;     /* the machine is on */
    bool          quit;
    char          work_dir[1024];
} Fuji;

static void set_message(Fuji *f, const char *msg)
{
    snprintf(f->desk.message, sizeof f->desk.message, "%s", msg);
}

/* ------------------------------------------------------------------ machine */

static bool machine_start(Fuji *f)
{
    AtariStConfig cfg;
    memset(&cfg, 0, sizeof cfg);
    cfg.machine         = f->desk.machine;
    cfg.memory_kb       = f->desk.memory_kb;
    cfg.monitor         = f->desk.monitor;
    cfg.tos_path        = f->desk.slot[FUJI_SLOT_TOS][0] ? f->desk.slot[FUJI_SLOT_TOS] : NULL;
    cfg.floppy_a        = f->desk.slot[FUJI_SLOT_A][0]   ? f->desk.slot[FUJI_SLOT_A]   : NULL;
    cfg.floppy_b        = f->desk.slot[FUJI_SLOT_B][0]   ? f->desk.slot[FUJI_SLOT_B]   : NULL;
    cfg.gemdos_dir      = f->desk.slot[FUJI_SLOT_C][0]   ? f->desk.slot[FUJI_SLOT_C]   : NULL;
    cfg.joystick_port1  = 1;
    cfg.work_dir        = f->work_dir;

    if (atarist_core_start(&cfg) != 0) {
        set_message(f, atarist_core_last_error());
        return false;
    }
    f->running    = true;
    f->desk.view  = FUJI_VIEW_RUNNING;
    f->last_frame = -1;
    return true;
}

static void machine_stop(Fuji *f)
{
    if (!f->running) return;
    atarist_core_stop();
    f->running   = false;
    f->desk.view = FUJI_VIEW_DESKTOP;
    /* The texture describes a framebuffer the core no longer owns. */
    if (f->screen) { SDL_DestroyTexture(f->screen); f->screen = NULL; }
    f->screen_w = f->screen_h = 0;
}

/* Uploads the ST's framebuffer, but only when it has actually changed. A GEM
 * desktop sitting idle is byte-identical for minutes, and the frame counter is
 * in the ABI precisely so a front end can skip the upload. */
static void present_machine(Fuji *f)
{
    int w = 0, h = 0, pitch = 0;
    const uint32_t *px = atarist_core_get_framebuffer(&w, &h, &pitch);
    if (!px || w <= 0 || h <= 0) return;

    if (!f->screen || w != f->screen_w || h != f->screen_h) {
        if (f->screen) SDL_DestroyTexture(f->screen);
        f->screen = SDL_CreateTexture(f->renderer, SDL_PIXELFORMAT_XRGB8888,
                                      SDL_TEXTUREACCESS_STREAMING, w, h);
        if (!f->screen) return;
        /* The ST is a machine of hard pixels. Smoothing them is a choice
         * nobody asked for. */
        SDL_SetTextureScaleMode(f->screen, SDL_SCALEMODE_NEAREST);
        f->screen_w = w;
        f->screen_h = h;
        f->last_frame = -1;
    }

    const int64_t frame = atarist_core_frame_counter();
    if (frame != f->last_frame) {
        /* pitch is in BYTES. Treating it as a pixel count is what produces
         * the classic diagonally sheared emulator screenshot. */
        SDL_UpdateTexture(f->screen, NULL, px, pitch);
        f->last_frame = frame;
    }

    /* Letterbox to the ST's own aspect, not the window's. ST low resolution is
     * 320x200 on a 4:3 monitor, so square pixels are wrong by a third. */
    double aspect = atarist_core_pixel_aspect();
    if (aspect <= 0.0) aspect = 4.0 / 3.0;

    int ww = 0, wh = 0;
    SDL_GetRenderOutputSize(f->renderer, &ww, &wh);
    float dw = (float)ww, dh = (float)(ww / aspect);
    if (dh > (float)wh) { dh = (float)wh; dw = (float)(wh * aspect); }
    const SDL_FRect dst = { ((float)ww - dw) / 2.0f, ((float)wh - dh) / 2.0f,
                            dw, dh };

    SDL_SetRenderDrawColor(f->renderer, 0, 0, 0, 255);
    SDL_RenderClear(f->renderer);
    SDL_RenderTexture(f->renderer, f->screen, NULL, &dst);
}

/* -------------------------------------------------------------------- input */

static void handle_event(Fuji *f, const SDL_Event *e)
{
    switch (e->type) {
    case SDL_EVENT_QUIT:
        f->quit = true;
        break;

    case SDL_EVENT_KEY_DOWN:
    case SDL_EVENT_KEY_UP: {
        const bool down = (e->type == SDL_EVENT_KEY_DOWN);

        /* F12 is the one key the app keeps for itself: it puts the machine
         * away and brings the desktop back. Everything else belongs to the
         * ST, including Escape, which GEM uses. */
        if (down && e->key.scancode == SDL_SCANCODE_F12 && f->running) {
            machine_stop(f);
            return;
        }
        if (!f->running) {
            if (down) fuji_desktop_key(&f->desk, (int)e->key.scancode);
            return;
        }
        const int st = fuji_st_scancode(e->key.scancode);
        if (st) atarist_core_key_event(st, down ? 1 : 0);
        break;
    }

    case SDL_EVENT_MOUSE_MOTION:
        if (f->running) {
            atarist_core_mouse_motion((int)e->motion.xrel,
                                      (int)e->motion.yrel);
        }
        break;

    case SDL_EVENT_MOUSE_BUTTON_DOWN:
    case SDL_EVENT_MOUSE_BUTTON_UP: {
        const bool down = (e->type == SDL_EVENT_MOUSE_BUTTON_DOWN);
        if (f->running) {
            const int b = (e->button.button == SDL_BUTTON_RIGHT) ? 1 : 0;
            atarist_core_mouse_button(b, down ? 1 : 0);
            break;
        }
        if (!down) break;
        /* The launcher is drawn in logical coordinates and the renderer is
         * letterboxing it, so the window coordinate has to come back through
         * that transform or every hit test is off by the letterbox. */
        float lx = 0, ly = 0;
        SDL_RenderCoordinatesFromWindow(f->renderer, e->button.x, e->button.y,
                                        &lx, &ly);
        if (fuji_desktop_click(&f->desk, &f->gem, lx, ly)) machine_start(f);
        break;
    }

    default:
        break;
    }
}

/* --------------------------------------------------------------------- main */

/* Draws one frame of the launcher and writes it to a BMP, then exits.
 *
 * This exists because the launcher is drawn by hand -- there is no toolkit to
 * trust -- and "it compiled" says nothing about whether the desktop is laid
 * out or whether every icon is stacked in one corner. With the offscreen video
 * driver it needs no display, so CI can look at the result too. */
static int shoot(const char *path, const char *home, const char *view)
{
    SDL_Window *w = NULL;
    SDL_Renderer *r = NULL;
    if (!SDL_CreateWindowAndRenderer("Fuji", LOGICAL_W, LOGICAL_H, 0, &w, &r)) {
        SDL_Log("shoot: %s", SDL_GetError());
        return 1;
    }
    SDL_SetRenderLogicalPresentation(r, LOGICAL_W, LOGICAL_H,
                                     SDL_LOGICAL_PRESENTATION_LETTERBOX);

    FujiDesktop d;
    GemCtx g;
    fuji_desktop_init(&d, home ? home : ".");
    gem_begin(&g, r, LOGICAL_W, LOGICAL_H);

    if (view && SDL_strcmp(view, "selector") == 0) {
        /* Reached the way a user reaches it -- by tapping the drive -- so the
         * shot exercises the click handling, not just the drawing. */
        const SDL_FRect a = { 28.0f, 19.0f + 28.0f, 72.0f, 64.0f };
        fuji_desktop_click(&d, &g, a.x + 4, a.y + 4);
    } else if (view && SDL_strcmp(view, "about") == 0) {
        fuji_desktop_click(&d, &g, 10.0f, 8.0f);
    }

    SDL_SetRenderDrawColor(r, 0, 0, 0, 255);
    SDL_RenderClear(r);
    fuji_desktop_draw(&d, &g);
    SDL_RenderPresent(r);

    SDL_Surface *shot = SDL_RenderReadPixels(r, NULL);
    int rc = 1;
    if (shot) {
        rc = SDL_SaveBMP(shot, path) ? 0 : 1;
        if (rc) SDL_Log("SDL_SaveBMP: %s", SDL_GetError());
        SDL_DestroySurface(shot);
    } else {
        SDL_Log("SDL_RenderReadPixels: %s", SDL_GetError());
    }

    fuji_desktop_free(&d);
    SDL_DestroyRenderer(r);
    SDL_DestroyWindow(w);
    return rc;
}

int main(int argc, char *argv[])
{

    if (!SDL_Init(SDL_INIT_VIDEO | SDL_INIT_AUDIO)) {
        SDL_Log("SDL_Init: %s", SDL_GetError());
        return 1;
    }

    const char *home_env = SDL_getenv("HOME");

    if (argc >= 3 && SDL_strcmp(argv[1], "--shot") == 0) {
        const int rc = shoot(argv[2], home_env, argc > 3 ? argv[3] : NULL);
        SDL_Quit();
        return rc;
    }

    Fuji f;
    memset(&f, 0, sizeof f);

    if (!SDL_CreateWindowAndRenderer("Fuji", LOGICAL_W * 2, LOGICAL_H * 2,
                                     SDL_WINDOW_RESIZABLE,
                                     &f.window, &f.renderer)) {
        SDL_Log("SDL_CreateWindowAndRenderer: %s", SDL_GetError());
        SDL_Quit();
        return 1;
    }
    SDL_SetRenderLogicalPresentation(f.renderer, LOGICAL_W, LOGICAL_H,
                                     SDL_LOGICAL_PRESENTATION_LETTERBOX);

    /* Where Hatari may write its config, NVRAM and snapshots. On iOS this is
     * inside the app's container; the container's UUID changes on every
     * install, so it is asked for at run time rather than remembered. */
    char *pref = SDL_GetPrefPath("CrownParkComputing", "Fuji");
    snprintf(f.work_dir, sizeof f.work_dir, "%s", pref ? pref : ".");
    if (pref) SDL_free(pref);

    atarist_core_init(f.work_dir, f.work_dir);

    fuji_desktop_init(&f.desk, home_env ? home_env : ".");
    gem_begin(&f.gem, f.renderer, LOGICAL_W, LOGICAL_H);

    SDL_Log("Fuji: core ABI %d, %s", atarist_core_abi_version(),
            atarist_core_hatari_version());

    while (!f.quit) {
        SDL_Event e;
        while (SDL_PollEvent(&e)) handle_event(&f, &e);

        if (f.running && !atarist_core_is_running()) machine_stop(&f);

        if (f.running) {
            present_machine(&f);
        } else {
            SDL_SetRenderDrawColor(f.renderer, 0, 0, 0, 255);
            SDL_RenderClear(f.renderer);
            fuji_desktop_draw(&f.desk, &f.gem);
        }
        SDL_RenderPresent(f.renderer);
        SDL_Delay(8);
    }

    machine_stop(&f);
    atarist_core_shutdown();
    fuji_desktop_free(&f.desk);
    if (f.screen)   SDL_DestroyTexture(f.screen);
    if (f.renderer) SDL_DestroyRenderer(f.renderer);
    if (f.window)   SDL_DestroyWindow(f.window);
    SDL_Quit();
    return 0;
}
