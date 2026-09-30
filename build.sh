#!/usr/bin/env bash
set -euo pipefail

sdk="${1:-iphoneos}"
case "$sdk" in
	iphoneos|iphonesimulator) ;;
	*)
		echo "usage: $0 [iphoneos|iphonesimulator] [-DDEVELOPMENT_TEAM=TEAM_ID]" >&2
		exit 2
		;;
esac

script_dir="$(cd "$(dirname "$0")" && pwd)"
build_dir="$script_dir/build/$sdk"
cpu_source="$script_dir/core/src/cpu"
cpu_build="$build_dir/retro-atarist-cpu"

# Hatari normally creates these sources from Xcode build phases. A Darwin host
# targeting iOS is not consistently treated as a cross-build by CMake/Xcode,
# so the small generators can accidentally become simulator executables and
# fail when the Mac tries to run them. Generate the architecture-independent C
# sources up front with the macOS compiler instead; target.cmake then compiles
# them from $cpu_build (see "retro-atarist-cpu" there) and Xcode never pulls in
# upstream's generator phases.
mkdir -p "$cpu_build"
"${CC:-cc}" -I"$cpu_source" \
	"$cpu_source/build68k.c" "$cpu_source/writelog.c" \
	-o "$cpu_build/build68k"
"$cpu_build/build68k" < "$cpu_source/table68k" > "$cpu_build/cpudefs.c"
"${CC:-cc}" -I"$cpu_source" \
	"$cpu_build/cpudefs.c" "$cpu_source/gencpu.c" "$cpu_source/readcpu.c" \
	-o "$cpu_build/gencpu"
(
	cd "$cpu_build"
	./gencpu
)

# HAVE_UNIX_DOMAIN_SOCKETS is forced off below, and it is NOT a networking
# feature: src/control.c opens an AF_UNIX socket so another local process can
# drive the emulator. Nothing on iOS can be that process, so the code is
# already unreachable -- but it still makes the binary import socket() and
# connect(), and this app's review notes say it has neither. Retro-Amiga was
# rejected under guideline 5.6 for precisely that shape: notes claiming no
# networking over a binary whose symbol table disagreed. CMake's
# check_include_files honours a value already in the cache, so setting it
# here means the probe never runs. The iOS job greps the built binary and
# fails if the symbols come back.
cmake -S "$script_dir/core" -B "$build_dir" -G Xcode \
	-DCMAKE_PROJECT_INCLUDE="$script_dir/core/retro/embed.cmake" \
	-DRETRO_ATARIST_APP_CMAKE="$script_dir/cmake/stdesk-app.cmake" \
	-DSDL2_DIR="$script_dir/core/retro/cmake-stubs" \
	-DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=BOTH \
	-DENABLE_SDL3=0 \
	-DENABLE_DSP_EMU=0 \
	-DHAVE_UNIX_DOMAIN_SOCKETS=0 \
	-DENABLE_OSX_BUNDLE=0 \
	-DCMAKE_SYSTEM_NAME=iOS \
	-DCMAKE_OSX_SYSROOT="$sdk" \
	-DCMAKE_OSX_ARCHITECTURES=arm64 \
	-DCMAKE_OSX_DEPLOYMENT_TARGET=16.0 \
	-DCMAKE_BUILD_TYPE=Release \
	-DCMAKE_XCODE_GENERATE_SCHEME=ON \
	"${@:2}"

# CI configures here and then runs `xcodebuild archive` itself, because an
# archive is not a build and `cmake --build` cannot produce one. Without this
# the tree would be configured, built, and then built a second time by the
# archive -- twice the slowest step in the job for nothing.
if [ -n "${STDESK_CONFIGURE_ONLY:-}" ]; then
	echo "configured only (STDESK_CONFIGURE_ONLY set): $build_dir"
	exit 0
fi

# `cmake --build` drives xcodebuild under the hood; building the STDesk target
# alone keeps Hatari's desktop executable and helper tools uncompiled, exactly
# as the Android build builds only --target atarist_core's dependents.
cmake --build "$build_dir" --config Release --target STDesk
