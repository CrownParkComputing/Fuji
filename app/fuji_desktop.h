/*
 * The launcher: the ST's desktop, not a library grid.
 *
 * You are looking at drive icons on a dithered green desktop with a GEM menu
 * bar, because that is what an Atari ST is. Choosing what to run means putting
 * a disk in a drive and switching the machine on -- which is both the truth
 * about the hardware and, not by accident, nothing like the media-card grid
 * every other front end in this estate uses.
 */
#ifndef FUJI_DESKTOP_H
#define FUJI_DESKTOP_H

#include "fuji_files.h"
#include "fuji_gem.h"

#include <stdbool.h>

typedef enum {
    FUJI_VIEW_DESKTOP = 0,
    FUJI_VIEW_SELECTOR,
    FUJI_VIEW_ABOUT,
    FUJI_VIEW_RUNNING,
} FujiView;

typedef enum {
    FUJI_SLOT_A = 0,
    FUJI_SLOT_B,
    FUJI_SLOT_C,     /* GEMDOS folder, fitted as an ST hard disk */
    FUJI_SLOT_TOS,
    FUJI_SLOT_COUNT,
} FujiSlot;

typedef struct {
    FujiView view;

    /* What is in each drive. Empty string means the drive is empty, which is
     * a legitimate state: an ST with no disk boots to its desktop. */
    char     slot[FUJI_SLOT_COUNT][1024];

    int      machine;       /* ATARIST_MACHINE_* */
    int      monitor;       /* ATARIST_MONITOR_* */
    int      memory_kb;

    /* Selector state. */
    FujiSlot selecting;
    FujiDir  dir;
    int      sel_index;
    int      sel_top;
    bool     dirs_only;     /* choosing the GEMDOS folder, not a disk image */

    char     message[256];  /* the one-line alert strip, "" when quiet */
} FujiDesktop;

void fuji_desktop_init(FujiDesktop *d, const char *start_dir);
void fuji_desktop_free(FujiDesktop *d);

/* Draws the current view. */
void fuji_desktop_draw(FujiDesktop *d, GemCtx *g);

/* A tap or click in logical GEM coordinates. Returns true when the machine
 * should be started. */
bool fuji_desktop_click(FujiDesktop *d, GemCtx *g, float x, float y);

/* Keyboard while the launcher is up: Up/Down/Return/Escape in the selector. */
void fuji_desktop_key(FujiDesktop *d, int sdl_scancode);

const char *fuji_slot_label(FujiSlot s);

#endif
