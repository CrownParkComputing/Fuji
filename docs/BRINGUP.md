# Bringing Fuji up

The order matters; several of these block the ones after them.

## 1. The core builds for iOS

`core/` is already wired. Build the core for the simulator first — it is the
half that has nothing to do with the UI, and proving it early means a later
failure is unambiguously the app's fault.

## 2. Design the app

This is the part that cannot be templated. Fuji emulates a Atari ST, and it
should look and behave like an app for that machine rather than an entry in a
family. Different navigation, different layout, different emphasis from every
other app in this estate. If it can be described as "the same app with a
different accent colour", it will be rejected again under 4.3.

## 3. Apple identity

- Create the App Store Connect record. Bundle id `com.crownparkcomputing.fuji`.
- Create an App Store **distribution provisioning profile for that bundle id** —
  another app's will not work; see `signing/README.md`.
- Encrypt the four blobs into `signing/` and set the `SIGNING_PASSPHRASE`
  repository secret.

## 4. Turn CI on

Move `ci/ios.yml` to `.github/workflows/ios.yml` and change the target name,
scheme and bundle id. It is a working pipeline lifted from a shipping app:
simulator build, SDK check, signing decrypt, certificate import, build number,
archive, a check that the bundle cannot be discarded in processing, then export
and upload.

It is deliberately not in `.github/workflows/` yet. There is no app to build,
and a repository that is red on every push teaches everyone to ignore it.

## 5. Review notes

**Every submission of an emulator app needs the 4.7.4 index in the Review
Notes** — a list of the games and software the app makes available that are not
embedded in it. Apple bounced Retro-Dosbox and Retro-C64 for its absence and
they now require it on every version of every emulator app on the account.

If the honest answer is "none — everything executable is embedded", that is the
answer to give, and it should be true.

## 6. Credit the core

Before submitting, check the three obligations in [CREDITS.md](../CREDITS.md)
are actually met in the built app, not just written down here.
