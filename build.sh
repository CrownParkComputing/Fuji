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

cmake -S "$script_dir/core" -B "$build_dir" -G Xcode \
	-DCMAKE_PROJECT_INCLUDE="$script_dir/core/retro/embed.cmake" \
	-DRETRO_ATARIST_APP_CMAKE="$script_dir/cmake/shifter-app.cmake" \
	-DSDL2_DIR="$script_dir/core/retro/cmake-stubs" \
	-DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=BOTH \
	-DENABLE_SDL3=0 \
	-DENABLE_DSP_EMU=0 \
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
if [ -n "${SHIFTER_CONFIGURE_ONLY:-}" ]; then
	echo "configured only (SHIFTER_CONFIGURE_ONLY set): $build_dir"
	exit 0
fi

# `cmake --build` drives xcodebuild under the hood; building the Shifter target
# alone keeps Hatari's desktop executable and helper tools uncompiled, exactly
# as the Android build builds only --target atarist_core's dependents.
cmake --build "$build_dir" --config Release --target Shifter
