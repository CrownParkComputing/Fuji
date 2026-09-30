//
//  STDeskApp.swift
//
//  STDesk is a SwiftUI front end for the Hatari Atari ST emulator core. The
//  emulator itself lives in the `core` submodule and is reached only through
//  the plain-C ABI in atarist_bridge.h (see AtariCore.swift).
//

import SwiftUI

@main
struct STDeskApp: App {
    @StateObject private var core: AtariCore
    @StateObject private var pad: TouchPadController

    init() {
        // The pad's sink needs the core at construction; build both here so
        // the StateObjects share one AtariCore.
        let core = AtariCore()
        _core = StateObject(wrappedValue: core)
        _pad = StateObject(wrappedValue: TouchPadController(core: core))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(core)
                .environmentObject(pad)
                // Emulator screens are near-black; a light status bar over the
                // framebuffer reads as a rendering bug.
                .preferredColorScheme(.dark)
        }
    }
}

/// Launcher while the machine is parked, emulation screen once a title boots.
/// The swap is driven by the core's own isRunning so it cannot disagree with
/// the emulator about which state we are in.
struct RootView: View {
    @EnvironmentObject private var core: AtariCore

    var body: some View {
        Group {
            if core.isRunning {
                EmulationView()
            } else {
                LauncherView()
            }
        }
        .onAppear {
            core.initialiseIfNeeded()
        }
    }
}

/// The framebuffer with the touch controls layered on top.
struct EmulationView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            EmuMetalView()
                .ignoresSafeArea()
            ControlsOverlay()
        }
        .statusBarHidden(true)
        // The ST is a 4:3 landscape machine; portrait letterboxes it into
        // unusability on a phone. iPad must still declare all orientations in
        // Info.plist for multitasking (App Store Connect enforces it), but
        // nothing forces us to *prefer* portrait there.
        .persistentSystemOverlays(.hidden)
    }
}
