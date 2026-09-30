# Shifter

Shifter is an Atari ST emulator for iPhone and iPad: a SwiftUI front end over the
Hatari emulator core. It exists because Apple rejected the iOS build of the
Retro-* family under App Store guideline 4.3 as a duplicate app — so the iOS
front end was rebuilt from nothing as its own application, in its own
repository, under its own name.

**Shifter was authored on a Linux machine and has never been compiled.** There is
no Xcode here, so the CMake wiring, the Xcode project generation, the Swift
sources and the plist files are all verified by inspection and syntax checks
only. Expect the first build on a Mac to surface a handful of typos-level
fixes; that is normal and expected, not a sign the approach is wrong.

## Repository layout

```
build.sh                  Generates the 68000 CPU sources, configures with
                          CMake (-G Xcode), builds the Shifter scheme.
cmake/shifter-app.cmake      The Shifter app target, injected into Hatari's build
                          via -DRETRO_ATARIST_APP_CMAKE (see below).
core/                     Git submodule: CrownParkComputing/hatari, branch cpc
                          (Hatari upstream + the retro/ embedding layer).
Shifter/                     The application sources:
  ShifterApp.swift           @main SwiftUI app; launcher vs. emulation screen.
  AtariCore.swift         ObservableObject wrapping the atarist_core_* C ABI.
  EmuMetalView.swift      MTKView + 50 Hz display link, Metal texture upload,
                          touch-to-mouse.
  EmuShaders.metal        One aspect-correct textured quad.
  LauncherView.swift      Game library (Documents/AtariST/Games) + importer.
  MachineSetupView.swift  Machine, memory, monitor, blitter, FDC, joystick.
  ControlsOverlay.swift   Machine control bar over the emulation screen.
  TouchPad.swift          retro_touch_pad model: profiles, layout, JSON.
  TouchPadOverlayView.swift  Multi-touch overlay engine + UIView surface.
  TouchPadDesigner.swift  Edit-mode panel (movement, opacity, add/reset).
  STKeyboardView.swift    On-screen ST keyboard (IKBD make/break scan codes).
  Bridging/               Bridging header (+ shim.m — see below).
  Resources/EmuTOS/       EmuTOS 1.4 UK (open-source TOS replacement) + licence.
  Resources/Demo/         The bundled core-demo disk.
```

## Prerequisites (macOS)

- Xcode 15 or newer (Swift 5, iOS 16 SDK)
- CMake 3.24 or newer (`brew install cmake`) — Swift language support in the
  Xcode generator needs it
- A checked-out `core` submodule:

  ```sh
  git submodule update --init
  ```

## Building

```sh
# Device build, signed with your team:
./build.sh iphoneos -DDEVELOPMENT_TEAM=YOUR_TEAM_ID

# Simulator build:
./build.sh iphonesimulator
```

The script does three things:

1. **Pre-generates the 68000 CPU sources.** Hatari's own Xcode build phases
   compile *and run* its code generators (`build68k`, `gencpu`) with the
   iPhone SDK — but iPhone binaries cannot execute on the Mac host, so the
   script builds and runs the generators first and leaves
   `cpudefs.c`/`cpustbl.c`/`cpuemu_*.c` in `build/<sdk>/retro-atarist-cpu/`,
   where `core/retro/target.cmake` already expects them.
2. **Configures Hatari as the top-level CMake project** with the embedding
   layer injected (`-DCMAKE_PROJECT_INCLUDE=core/retro/embed.cmake`) and
   Shifter's app target injected on top of that
   (`-DRETRO_ATARIST_APP_CMAKE=cmake/shifter-app.cmake`). The SDL2 stub under
   `core/retro/cmake-stubs/` satisfies Hatari's configure-time
   `find_package(SDL2)`; no SDL code is linked. See
   `core/../docs/NATIVE_BUILD.md` in the Retro-AtariST repository for the
   full story of why the nesting goes this way round.
3. **Builds the Shifter scheme** (Release) through `cmake --build`.

The output app bundle is under
`build/<sdk>/Release-<sdk>/Shifter.app`.

Signing follows the pattern the old Retro-AtariST iOS app used: automatic by
default, overridable with `-DSHIFTER_CODE_SIGN_STYLE=Manual`,
`-DSHIFTER_PROVISIONING_PROFILE=...`, `-DSHIFTER_CODE_SIGN_IDENTITY=...`, and
`-DSHIFTER_BUILD_NUMBER=...` (CFBundleVersion; CI should pass a UTC timestamp —
App Store Connect refuses a build number it has seen before).

## Running

On first launch Shifter creates `Documents/AtariST/` (visible in the Files app,
via UIFileSharingEnabled) with `TOS/`, `Games/` and `Demo/` inside, copies the
bundled EmuTOS into `TOS/`, and hands the core the paths. Drop disk images
(`.st`, `.msa`, `.dim`, `.stx`, `.ipf`, `.img`, `.zip`) into `Games/` via
Files, or import them with the + button. With an empty library a "Run bundled
core demo" button boots the demo disk so a fresh install can prove video,
audio and input end to end.

While a title runs, the configurable on-screen controller (the Retro-*
family's shared `retro_touch_pad`) drives joystick port 1: a wobble stick or
d-pad for direction, a FIRE button, and any extra buttons you add — including
direction-as-button extras and `key:<scancode>` extras that press ST keys.
Touches no control claims fall through to the emulated mouse (drag moves,
tap clicks left). The top bar has menu, reset, disk swap, save/load state
slots, the ST keyboard, and "arrange controls": an edit mode where clusters
drag to move, tap to select for size/spacing/visibility, and a panel offers
stick/d-pad, opacity, add-a-button and reset. Layouts save to
`Documents/AtariST/Layouts/pad_layout_atarist.json` in the same JSON format
the rest of the family uses, so an arrangement made in Shifter loads in
Retro-Saturn and vice versa. Machine options (model, memory, monitor,
blitter, accurate FDC) are under the gear on the launcher screen and apply
to the next boot. The monitor defaults to RGB on purpose: TOS reads the
monitor type at boot and picks its screen mode from it, and a mono monitor
lands you in ST-HIGH (640×400, two colours), where essentially no game runs.

## Notes for maintainers

- **No JIT, ever.** The 68000 core is interpreter-only; enabling Hatari's JIT
  would make App Store distribution impossible (W^X). Do not touch the CPU
  settings.
- The **app icon is a generated placeholder**
  (`Shifter/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`) — replace it
  before submission.
- `Bridging/shim.m` is an empty Objective-C file that exists for one reason:
  Xcode only honours `SWIFT_OBJC_BRIDGING_HEADER` on a target that compiles at
  least one Objective-C source.
- Save-state slots are Hatari machine snapshots keyed by slot within the
  running title's directory, executed on the emulation thread through the
  bridge's mailbox — never touch core state from the UI thread.
- `atarist_core_start` with a new configuration while a core is running
  re-points and cold resets rather than failing; `stop` is a *soft* stop
  because Hatari cannot be `Main_Init`'d twice in one process. Don't "fix"
  this by tearing the core down between titles.

## Licence

Shifter links Hatari, which is GPL v2+. EmuTOS is bundled under its own licence
(see `Shifter/Resources/EmuTOS/LICENSE.txt`). Front-end sources:
GPL-2.0-or-later, matching the embedding layer they link against.
