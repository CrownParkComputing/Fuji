# Shifter — App Review notes

Everything BELOW the rule is the reviewer-facing text, and it goes into
**Review Notes** on **every** submission, not just the first: App Review
bounces an emulator submission that arrives without the 4.7.4 index, and the
field does not carry over from the previous version. This paragraph is a note
to ourselves and must not be sent — `tool/set-review-notes.sh` splits on the
rule so the reviewer never reads our instructions to each other.

---

## What this app is

Shifter is an Atari ST emulator for iPhone and iPad. The emulation is
[Hatari](https://www.hatari-emu.org/), GNU GPL v2, used unmodified in every
respect that matters to the emulation; the SwiftUI interface around it is
ours. The app credits Hatari and EmuTOS on its About screen, with links to
both projects and to our own source.

It is not a version of our Android app "Retro-AtariST". It is a separate
app with its own name, icon, identifier, listing and interface, sharing only
the open-source engine underneath. (This is the answer to the 4.3 rejection
of the Retro-* family: not a rename, a different app.)

## 4.7.4 — index of software offered in the app

**There is none.** The app offers no catalogue, no store, no downloads and no
links to obtain software. It runs software the user already has.

Two pieces of software are **embedded** in the app, and neither is offered as
a download:

| Embedded | What it is | Licence |
|---|---|---|
| `emutos-1.4-uk.img` | EmuTOS 1.4, a free open-source replacement for the Atari TOS ROM, so the machine can boot with nothing supplied | GNU GPL v2, emutos.sourceforge.io |
| `shifter-core-demo.st` | A small demonstration floppy we wrote — it boots, draws a moving marker and waits for a key | Ours, GPL v2 with the app |

Everything else a user runs is a file they supply themselves, through the
Files app, from their own media. The app has no means of acquiring software.

**No Atari TOS ROM is included.** TOS is Atari's and is not ours to
distribute. A user who owns an original TOS image may place it in the app's
folder, and the emulator will use it instead of EmuTOS; the app neither
supplies one nor can obtain one.

## 2.5.2 / JIT

No just-in-time compilation. The CPU is Hatari's interpreter — the target
compiles the generated `cpuemu_*.c` tables and nothing else. No
writable-executable memory is requested and `com.apple.security.cs.allow-jit`
is not claimed.

## 5.6 / networking

**The app has no network features of any kind.** There is no account, no sign
in, no analytics, no update check, no telemetry.

This is enforced in the build rather than asserted: the iOS job fails if the
finished binary imports any of `socket`, `connect`, `bind`, `listen`,
`accept`, `getaddrinfo`, `gethostbyname`, `sendto` or `recvfrom`. A configure
flag is a claim; a symbol table is the fact.

## Privacy

Nothing is collected, because nothing leaves the device. No data is
transmitted anywhere; there is nowhere for it to go.

## How to try it

1. Open the app. It boots straight to the EmuTOS desktop — that is the
   emulated machine running, with no file from the reviewer needed.
2. The bundled demonstration floppy appears in the library. Insert it and
   reset, and it draws a moving marker and waits for a key, which shows the
   CPU, the video and the keyboard all working.
3. To run your own software, add a disk image (ST, MSA, DIM, STX, IMG, IPF,
   or a ZIP of one) through the Files app; it appears in the library.

## Copyright

No proprietary software is bundled, downloaded or linked to. The app does not
supply Atari TOS, or any game. EmuTOS is free software, included under the
GPL with its licence text in the bundle, and the demonstration floppy is our
own work.
