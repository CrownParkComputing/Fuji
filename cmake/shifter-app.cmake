# Shifter -- the SwiftUI iPhone/iPad application. This file is included after
# atarist_core is defined, from Hatari's deferred target injection (see
# core/retro/embed.cmake for why the nesting goes that way round), because
# core/retro/target.cmake was handed its path via -DRETRO_ATARIST_APP_CMAKE.
#
# Because this is include()d into Hatari's top-level scope, CMAKE_CURRENT_*
# names the Hatari tree; every path below goes through SHIFTER_ROOT, derived from
# this file's own location. ATARIST_CORE_DIR is already in scope and names
# core/retro.

get_filename_component(SHIFTER_ROOT "${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)
set(SHIFTER_APP "${SHIFTER_ROOT}/Shifter")

set(SHIFTER_RESOURCES
	"${SHIFTER_APP}/PrivacyInfo.xcprivacy"
	# GPLv2: the app links Hatari, and the licence text must ship with it.
	"${SHIFTER_ROOT}/LICENSE"
	# Bundled as source and compiled at runtime (see attach(to:) in
	# EmuMetalView.swift): CMake's Xcode generator does not recognise the
	# .metal file type, so a build-phase compile would silently not happen.
	"${SHIFTER_APP}/EmuShaders.metal"
	"${SHIFTER_APP}/Assets.xcassets")
set_source_files_properties(${SHIFTER_RESOURCES} PROPERTIES
	MACOSX_PACKAGE_LOCATION Resources)

# EmuTOS is the ROM the app can legally ship; the bridge scans tos_dir for it
# and the app copies these into Documents on first launch.
set(SHIFTER_EMUTOS_RESOURCES
	"${SHIFTER_APP}/Resources/EmuTOS/emutos-1.4-uk.img"
	"${SHIFTER_APP}/Resources/EmuTOS/LICENSE.txt"
	"${SHIFTER_APP}/Resources/EmuTOS/README.txt"
	"${SHIFTER_APP}/Resources/EmuTOS/SOURCE.md")
set_source_files_properties(${SHIFTER_EMUTOS_RESOURCES} PROPERTIES
	MACOSX_PACKAGE_LOCATION "Resources/EmuTOS")

set(SHIFTER_DEMO_RESOURCES
	"${SHIFTER_APP}/Resources/Demo/shifter-core-demo.st"
	"${SHIFTER_APP}/Resources/Demo/README.md")
set_source_files_properties(${SHIFTER_DEMO_RESOURCES} PROPERTIES
	MACOSX_PACKAGE_LOCATION "Resources/Demo")

add_executable(Shifter MACOSX_BUNDLE
	"${SHIFTER_APP}/ShifterApp.swift"
	"${SHIFTER_APP}/AtariCore.swift"
	"${SHIFTER_APP}/EmuMetalView.swift"
	"${SHIFTER_APP}/LauncherView.swift"
	"${SHIFTER_APP}/MachineSetupView.swift"
	"${SHIFTER_APP}/ControlsOverlay.swift"
	"${SHIFTER_APP}/TouchPad.swift"
	"${SHIFTER_APP}/TouchPadOverlayView.swift"
	"${SHIFTER_APP}/TouchPadDesigner.swift"
	"${SHIFTER_APP}/STKeyboardView.swift"
	# The bridging header is only honoured once the target compiles at least
	# one Objective-C source; shim.m exists solely to be that source.
	"${SHIFTER_APP}/Bridging/shim.m"
	${SHIFTER_RESOURCES}
	${SHIFTER_EMUTOS_RESOURCES}
	${SHIFTER_DEMO_RESOURCES})

# The Swift sources call the atarist_core_* C entry points through the
# bridging header, which #imports atarist_bridge.h by bare name -- so the
# bridge directory has to be on the header search path, not just the include
# path of any one compile unit.
target_link_libraries(Shifter PRIVATE atarist_core
	"-framework AudioToolbox"
	"-framework AVFoundation"
	"-framework Foundation"
	"-framework Metal"
	"-framework MetalKit"
	"-framework QuartzCore"
	"-framework UIKit"
	"-framework UniformTypeIdentifiers")

# Automatic signing looks for an *App Development* profile, and a release
# machine only ever has the App Store distribution one, so an unattended
# device build fails with "No profiles for ... were found" before it reaches
# the archive. CI overrides these to sign manually.
set(SHIFTER_BUILD_NUMBER "1" CACHE STRING "CFBundleVersion; CI passes a UTC timestamp")
set(SHIFTER_CODE_SIGN_STYLE "Automatic" CACHE STRING "Automatic or Manual")
set(SHIFTER_PROVISIONING_PROFILE "" CACHE STRING "profile name, Manual signing only")
set(SHIFTER_CODE_SIGN_IDENTITY "" CACHE STRING "e.g. Apple Distribution")

set_target_properties(Shifter PROPERTIES
	MACOSX_BUNDLE_INFO_PLIST "${SHIFTER_APP}/Info.plist"
	# We ship our own Info.plist; Xcode's generated-info-plist path would
	# merge keys over the top of it depending on the Xcode version.
	XCODE_ATTRIBUTE_GENERATE_INFOPLIST_FILE "NO"
	XCODE_ATTRIBUTE_CLANG_ENABLE_OBJC_ARC YES
	XCODE_ATTRIBUTE_SWIFT_VERSION "5.0"
	XCODE_ATTRIBUTE_SWIFT_OBJC_BRIDGING_HEADER "${SHIFTER_APP}/Bridging/Shifter-Bridging-Header.h"
	XCODE_ATTRIBUTE_HEADER_SEARCH_PATHS "${ATARIST_CORE_DIR}/bridge"
	# Signing belongs ON THE TARGET. Passing PROVISIONING_PROFILE_SPECIFIER on
	# the xcodebuild command line applies it to every target in the project,
	# including the static libraries, which then fail with "does not support
	# provisioning profiles" on something that is not the app.
	XCODE_ATTRIBUTE_CODE_SIGN_STYLE "${SHIFTER_CODE_SIGN_STYLE}"
	XCODE_ATTRIBUTE_PROVISIONING_PROFILE_SPECIFIER "${SHIFTER_PROVISIONING_PROFILE}"
	XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY "${SHIFTER_CODE_SIGN_IDENTITY}"
	# For the Xcode generator CMake leaves SKIP_INSTALL at YES, which produces
	# an archive whose Products/Applications is empty and carries no
	# ApplicationProperties -- -exportArchive then has nothing to export and
	# the failure says nothing about the cause.
	XCODE_ATTRIBUTE_INSTALL_PATH "$(LOCAL_APPS_DIR)"
	XCODE_ATTRIBUTE_SKIP_INSTALL "NO"
	XCODE_ATTRIBUTE_ASSETCATALOG_COMPILER_APPICON_NAME AppIcon
	XCODE_ATTRIBUTE_IPHONEOS_DEPLOYMENT_TARGET 16.0
	# Info.plist reads CFBundleVersion from this. CI overrides it on the
	# xcodebuild command line with a UTC timestamp; without a default here a
	# local build would produce an empty CFBundleVersion, which is invalid.
	XCODE_ATTRIBUTE_CURRENT_PROJECT_VERSION "${SHIFTER_BUILD_NUMBER}"
	XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER com.crownparkcomputing.shifter
	XCODE_ATTRIBUTE_PRODUCT_NAME Shifter
	XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY "1,2")

if(DEFINED DEVELOPMENT_TEAM AND NOT DEVELOPMENT_TEAM STREQUAL "")
	set_target_properties(Shifter PROPERTIES
		XCODE_ATTRIBUTE_DEVELOPMENT_TEAM "${DEVELOPMENT_TEAM}")
endif()
