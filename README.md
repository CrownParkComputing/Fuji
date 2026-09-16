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
| `core/` | the emulator, as a submodule. Do not edit it here — changes belong upstream in the core repository, where both apps see them. |
| `ci/ios.yml` | the full build/sign/archive/upload pipeline, ready to move to `.github/workflows/` once there is an app to build. |
| `signing/` | how the encrypted signing material works, and what has to be regenerated for this bundle id. |
| `docs/BRINGUP.md` | the order to do things in. |

**The application itself is not written yet.** That is the real work and it is
deliberately not scaffolded from a template, because a shared skeleton with a
reskin is exactly what was rejected.

## Identity

- Bundle id: `com.crownparkcomputing.fuji`
- App Store record: not created yet — see `docs/BRINGUP.md`
