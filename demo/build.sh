#!/usr/bin/env bash
# Build the bundled Atari ST demo disk from core-demo.s.
#
#   demo/build.sh
#
# The source lives here rather than only in Retro-AtariST because the banner
# names the APP, and the two apps are not the same app -- the image shipped
# from that repository greets the user with "RETRO-ATARIST CORE DEMO", which
# on this app is the wrong name on the first screen a reviewer is told to
# look at. (DOSDeck shipped exactly that mistake in its DOS demo.)
#
# Needs vasmm68k_mot, vlink and mtools.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
assembler="${VASM:-vasmm68k_mot}"
linker="${VLINK:-vlink}"
object="$here/core-demo.o"
program="$here/COREDEMO.PRG"
image="$here/../Shifter/Resources/Demo/shifter-core-demo.st"

"$assembler" -m68000 -Fvobj -quiet -o "$object" "$here/core-demo.s"
"$linker" -b ataritos -nostdlib -s -o "$program" "$object"
dd if=/dev/zero of="$image" bs=1024 count=720 status=none
mformat -a -t 80 -h 2 -n 9 -i "$image" ::
MTOOLS_NO_VFAT=1 mmd -i "$image" ::AUTO
MTOOLS_NO_VFAT=1 mcopy -i "$image" -pm "$program" ::AUTO/COREDEMO.PRG
rm -f "$object" "$program"
