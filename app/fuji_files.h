/*
 * Directory listing for the item selector.
 *
 * readdir, not SDL_GlobDirectory: glob with a NULL pattern RECURSES, so one
 * game folder comes back as a dozen entries of which only the first is
 * startable, and it hangs outright on some mobile storage roots. A selector
 * wants one level, which is what readdir gives.
 */
#ifndef FUJI_FILES_H
#define FUJI_FILES_H

#include <stdbool.h>

typedef struct {
    char name[256];
    bool is_dir;
} FujiEntry;

typedef struct {
    char       path[1024];
    FujiEntry *items;
    int        count;
} FujiDir;

/* Lists one level of [path], directories first then files, each alphabetical,
 * keeping only the extensions the ST can actually take in a drive. ".." is
 * included unless [path] is the root. Returns false and leaves the listing
 * empty if the directory cannot be read. */
bool fuji_dir_read(FujiDir *d, const char *path);
void fuji_dir_free(FujiDir *d);

/* Appends [name] to [d->path] with exactly one separator, resolving "..". */
void fuji_path_join(char *out, int out_sz, const char *dir, const char *name);

/* True for .st .msa .dim .stx .ipf .zip, case-insensitively. */
bool fuji_is_disk_image(const char *name);

#endif
