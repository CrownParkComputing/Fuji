# Fuji - an Atari ST, on iOS.
#
# The desktop build is not a side project. It is the only target that can be
# compiled and run without a Mac, so it is where the launcher, the core
# integration and the input mapping are actually proved; the iOS target is the
# same sources in a bundle.
#
# The emulator is not built here. core/ is CrownParkComputing/hatari, which
# carries Hatari and the embedding layer that turns it into libatarist_core --
# build that first with core/retro/linux/build.sh, then point this at it.
cmake_minimum_required(VERSION 3.21)
project(Fuji C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

if(NOT EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/core/retro/bridge/atarist_bridge.h")
    message(FATAL_ERROR
        "The core is missing at core/. Run:\n"
        "    git submodule update --init --recursive")
endif()

# Where libatarist_core.so was linked. core/retro/linux/build.sh puts it beside
# itself; an iOS build links the static core instead and sets this to that.
set(FUJI_CORE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/core/retro/linux/build"
    CACHE PATH "Directory containing the built core library")

find_package(SDL3 REQUIRED CONFIG)

add_executable(Fuji
    app/fuji_main.c
    app/fuji_desktop.c
    app/fuji_gem.c
    app/fuji_files.c
    app/fuji_keymap.c
)

target_include_directories(Fuji PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/app"
    "${CMAKE_CURRENT_SOURCE_DIR}/core/retro/bridge"
)

target_compile_options(Fuji PRIVATE -Wall -Wextra -Wno-unused-parameter)

find_library(FUJI_CORE_LIB
    NAMES atarist_core
    PATHS "${FUJI_CORE_DIR}"
    NO_DEFAULT_PATH)

if(NOT FUJI_CORE_LIB)
    message(FATAL_ERROR
        "No libatarist_core in ${FUJI_CORE_DIR}.\n"
        "Build it first:\n"
        "    ./core/retro/linux/build.sh\n"
        "or set -DFUJI_CORE_DIR=<dir> to an existing one.")
endif()

target_link_libraries(Fuji PRIVATE SDL3::SDL3 "${FUJI_CORE_LIB}")

# The core is a shared library sitting in the build tree rather than on the
# library path. Without this the binary links and then fails to start, which
# looks like a broken build rather than a missing search path.
set_target_properties(Fuji PROPERTIES
    BUILD_RPATH "${FUJI_CORE_DIR}"
    INSTALL_RPATH "${FUJI_CORE_DIR}")

if(APPLE AND CMAKE_SYSTEM_NAME STREQUAL "iOS")
    # Signing, the bundle id and the asset catalogue live in the iOS project,
    # not here -- see docs/BRINGUP.md. This only asserts the shape.
    set_target_properties(Fuji PROPERTIES
        MACOSX_BUNDLE YES
        XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER com.crownparkcomputing.fuji
        XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY "1,2"
        XCODE_ATTRIBUTE_IPHONEOS_DEPLOYMENT_TARGET "15.0")
endif()
