/*
 * SDL scancode -> Atari ST (IKBD) scan code.
 *
 * The bridge takes ST scan codes rather than characters, because ST software
 * reads the IKBD's make/break codes directly. Translating to a character
 * loses the key-up half, and a game whose key-up never arrives runs with a
 * direction held down forever.
 */
#ifndef FUJI_KEYMAP_H
#define FUJI_KEYMAP_H

#include <SDL3/SDL.h>

/* 0 when the key has no ST equivalent, which is most of a modern keyboard. */
int fuji_st_scancode(SDL_Scancode sc);

#endif
