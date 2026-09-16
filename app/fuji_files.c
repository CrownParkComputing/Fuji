#include "fuji_files.h"

#include <dirent.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/stat.h>

static const char *kExt[] = { ".st", ".msa", ".dim", ".stx", ".ipf", ".zip" };

bool fuji_is_disk_image(const char *name)
{
    const char *dot = strrchr(name, '.');
    if (!dot) return false;
    for (size_t i = 0; i < sizeof kExt / sizeof kExt[0]; ++i) {
        if (strcasecmp(dot, kExt[i]) == 0) return true;
    }
    return false;
}

void fuji_path_join(char *out, int out_sz, const char *dir, const char *name)
{
    if (strcmp(name, "..") == 0) {
        snprintf(out, out_sz, "%s", dir);
        char *slash = strrchr(out, '/');
        if (slash && slash != out) *slash = '\0';
        else if (slash) out[1] = '\0';     /* stop at "/" */
        return;
    }
    const size_t n = strlen(dir);
    if (n && dir[n - 1] == '/') snprintf(out, out_sz, "%s%s", dir, name);
    else                        snprintf(out, out_sz, "%s/%s", dir, name);
}

static int cmp_entry(const void *a, const void *b)
{
    const FujiEntry *x = a, *y = b;
    if (x->is_dir != y->is_dir) return x->is_dir ? -1 : 1;
    return strcasecmp(x->name, y->name);
}

void fuji_dir_free(FujiDir *d)
{
    free(d->items);
    d->items = NULL;
    d->count = 0;
}

bool fuji_dir_read(FujiDir *d, const char *path)
{
    /* The caller is allowed to pass d->path -- re-reading the directory you
     * are already in is the obvious thing to write. snprintf onto its own
     * source is undefined, and in practice it produced an empty string, so
     * the selector reported "Cannot read " about nothing at all. Copy first.
     */
    char want[sizeof d->path];
    snprintf(want, sizeof want, "%s", path);

    fuji_dir_free(d);
    snprintf(d->path, sizeof d->path, "%s", want);

    DIR *dir = opendir(want);
    if (!dir) return false;

    int cap = 32;
    d->items = calloc((size_t)cap, sizeof *d->items);
    if (!d->items) { closedir(dir); return false; }

    if (strcmp(want, "/") != 0) {
        snprintf(d->items[d->count].name, sizeof d->items[0].name, "..");
        d->items[d->count].is_dir = true;
        d->count++;
    }

    struct dirent *e;
    while ((e = readdir(dir)) != NULL) {
        if (e->d_name[0] == '.') continue;      /* "." ".." and hidden */

        char full[1024];
        fuji_path_join(full, sizeof full, want, e->d_name);
        struct stat st;
        if (stat(full, &st) != 0) continue;
        const bool is_dir = S_ISDIR(st.st_mode);

        /* A selector that lists every file on the device is not a selector.
         * Directories stay because they are how you get anywhere. */
        if (!is_dir && !fuji_is_disk_image(e->d_name)) continue;

        if (d->count == cap) {
            cap *= 2;
            FujiEntry *grown = realloc(d->items, (size_t)cap * sizeof *grown);
            if (!grown) break;
            d->items = grown;
        }
        snprintf(d->items[d->count].name, sizeof d->items[0].name,
                 "%s", e->d_name);
        d->items[d->count].is_dir = is_dir;
        d->count++;
    }
    closedir(dir);

    /* ".." is already first and must stay there. */
    const int skip = (d->count && strcmp(d->items[0].name, "..") == 0) ? 1 : 0;
    if (d->count > skip) {
        qsort(d->items + skip, (size_t)(d->count - skip),
              sizeof *d->items, cmp_entry);
    }
    return true;
}
