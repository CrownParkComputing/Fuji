//
//  ControlsOverlay.swift
//
//  The layer over the framebuffer: the family's configurable touch pad
//  (TouchPadOverlayView -- stick/d-pad, fire and any user-added buttons,
//  with unclaimed touches falling through to the emulated mouse), plus a
//  bar of machine controls -- menu, reset, disk swap, save/load state slots,
//  keyboard, and the "arrange controls" edit mode.
//

import SwiftUI
import UniformTypeIdentifiers

struct ControlsOverlay: View {
    @EnvironmentObject private var core: AtariCore
    @EnvironmentObject private var pad: TouchPadController

    @State private var showDiskSwap = false
    @State private var showError = false

    var body: some View {
        ZStack {
            // The pad stays up while the keyboard is open: its unclaimed
            // touches are the only mouse the emulation screen has.
            TouchPadOverlayView(pad: pad, core: core)

            VStack(spacing: 0) {
                controlBar
                Spacer()
                if core.showKeyboard {
                    STKeyboardView()
                        .transition(.move(edge: .bottom))
                }
            }

            if pad.editing {
                TouchPadDesigner(pad: pad) {
                    pad.setEditing(false)
                }
            }
        }
        .fileImporter(
            isPresented: $showDiskSwap,
            allowedContentTypes: [.atariDiskImage, .atariIPF, .zip]
        ) { result in
            // The picker hands out a security-scoped URL that goes stale, so
            // the image is copied into the library before the drive is
            // pointed at it.
            if case .success(let urls) = result, let url = urls.first,
               let imported = core.importGame(from: url) {
                core.setFloppy(imported)
            }
        }
        .alert("Atari ST", isPresented: $showError, presenting: core.lastError) { _ in
            Button("OK") { core.lastError = nil }
        } message: { message in
            Text(message)
        }
        .onChange(of: core.lastError) { newValue in
            showError = newValue != nil
        }
        // Leaving the emulation screen must never leave anything held: the
        // IKBD would keep reporting the direction or fire forever.
        .onDisappear {
            pad.releaseAll()
        }
    }

    // MARK: - Control bar

    private var controlBar: some View {
        HStack(spacing: 4) {
            Button {
                pad.releaseAll()
                core.stop()
            } label: {
                Label("Menu", systemImage: "chevron.backward")
            }

            Spacer()

            Text("\(core.fps) fps")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                core.reset(cold: false)
            } label: {
                Image(systemName: "arrow.counterclockwise")
            }
            .accessibilityLabel("Reset")

            Button {
                showDiskSwap = true
            } label: {
                Image(systemName: "opticaldisc")
            }
            .accessibilityLabel("Swap disk")

            Menu {
                ForEach(AtariCore.stateSlots, id: \.self) { slot in
                    Button("Save slot \(slot + 1)") { core.saveState(slot: slot) }
                }
            } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .accessibilityLabel("Save state")

            Menu {
                ForEach(AtariCore.stateSlots, id: \.self) { slot in
                    Button("Load slot \(slot + 1)\(core.isStateEmpty(slot: slot) ? " (empty)" : "")") {
                        core.loadState(slot: slot)
                    }
                    .disabled(core.isStateEmpty(slot: slot))
                }
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .accessibilityLabel("Load state")

            Button {
                withAnimation { core.showKeyboard.toggle() }
            } label: {
                Image(systemName: "keyboard")
            }
            .accessibilityLabel("Keyboard")

            Button {
                withAnimation { pad.setEditing(!pad.editing) }
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .accessibilityLabel("Arrange controls")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
    }
}
