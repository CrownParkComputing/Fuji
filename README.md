# Fuji

A Atari ST emulator for iOS.

**Atari's logo, the stylised mountain, on the badge of every ST.**

Fuji is a new application. It is not a port of an existing one, and it
deliberately shares no interface code with any other app in this estate — that
is the whole reason it exists. Apple rejected the previous generation under
guideline 4.3 (Design: Spam) because they were one workbench shipped several
times with a different accent colour, and the fix is not a rename. Each of
these apps gets its own navigation, its own layout and its own identity,
answering to the machine it emulates rather than to a house style.

## The core

Fuji runs on **Hatari**, which is not ours. It lives in
[`hatari`](https://github.com/CrownParkComputing/hatari) as the `core`
submodule, pinned to branch `cpc`, and it is shared — unmodified — with
the Android application that emulates the same machine. See
[CREDITS.md](CREDITS.md); crediting the core properly is both a licence
obligation and simple good manners.

A `sync-upstream` bot watches Hatari upstream and flags when it moves, so
taking an update is a decision rather than an archaeology exercise.

## What is here, and what is not

| | |
|---|---|
| `app/` | the front end. SDL3, drawn by hand, no toolkit and no code from any other app in this estate. |
| `core/` | the emulator, as a submodule. Do not edit it here — changes belong upstream in the core repository, where both apps see them. |
| `ci/ios.yml` | the full build/sign/archive/upload pipeline, ready to move to `.github/workflows/` once the Xcode project exists. |
| `signing/` | how the encrypted signing material works, and what has to be regenerated for this bundle id. |
| `docs/BRINGUP.md` | the order to do things in. |

## The launcher is the desktop

Fuji does not open on a grid of game tiles beside a navigation rail. It opens on
an Atari ST desktop: the dithered green ground, a GEM menu bar, and drive icons
for floppy A, floppy B, a hard disk and the TOS ROM. You put a disk in a drive
and switch the machine on, because that is what an ST is.

That is a design decision with a reason behind it. Every other emulator front
end in this estate is a media grid next to a sidebar, and shipping a ninth one
is what got the previous generation rejected as duplicates. The launcher is
drawn directly in SDL3 — `app/fuji_gem.c` is about a hundred lines of GEM: the
50% checker, the one-pixel black outlines, the title bar of horizontal rules.
There is no UI toolkit and nothing is shared.

Tap a drive to choose what goes in it; tap an occupied drive to empty it. The
item selector is GEM's, down to the close box. `Machine` and `Monitor` in the
menu bar cycle; the right-hand end of the bar always says what will boot.

## Building it on a desktop

The desktop build is not a convenience. It is the only target that compiles and
runs without a Mac, so it is where the launcher, the core integration and the
keyboard mapping are actually proved.

```sh
git submodule update --init --recursive
./core/retro/linux/build.sh          # libatarist_core, 29 exported symbols
cmake -S . -B build -G Ninja && cmake --build build
./build/Fuji
```

`./build/Fuji --shot out.bmp [selector|about]` draws one frame headlessly and
writes it to a BMP. With `SDL_VIDEODRIVER=offscreen` it needs no display, so CI
can look at the result. It is there because a launcher drawn by hand has no
toolkit to trust: "it compiled" says nothing about whether the icons are laid
out or stacked in one corner. It has already earned its keep — it caught the
selector opening on an empty path.

## What is still missing

The iOS half: the Xcode project, the asset catalogue, touch input and the
on-screen controls an ST needs on a phone with no keyboard and no mouse.

## Identity

- Bundle id: `com.crownparkcomputing.fuji`
- App Store record: not created yet — see `docs/BRINGUP.md`
