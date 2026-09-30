//
//  ControlsOverlay.swift
//
//  Touch controls layered over the framebuffer: a d-pad and fire button
//  driving ST joystick port 1 (ATARIST_JOY_* bits), plus a bar of machine
//  controls -- menu, reset, disk swap, save/load state slots, keyboard.
//

import SwiftUI
import UniformTypeIdentifiers

struct ControlsOverlay: View {
    @EnvironmentObject private var core: AtariCore

    @State private var joystickMask: Int32 = 0
    @State private var showDiskSwap = false
    @State private var showError = false

    var body: some View {
        VStack {
            controlBar
            Spacer()
            if core.showKeyboard {
                STKeyboardView()
                    .transition(.move(edge: .bottom))
            } else if MachineSettings.load().joystickEnabled {
                HStack(alignment: .bottom) {
                    dPad
                    Spacer()
                    fireButton
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
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
        // Leaving the emulation screen must never leave the joystick held:
        // the IKBD would keep reporting the direction forever.
        .onDisappear {
            joystickMask = 0
            core.joystick(0)
        }
    }

    // MARK: - Control bar

    private var controlBar: some View {
        HStack(spacing: 4) {
            Button {
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
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
    }

    // MARK: - Joystick

    /// One direction key. SwiftUI Buttons report only the tap, not the
    /// press/release pair the IKBD needs, so a zero-distance DragGesture
    /// supplies make/break instead.
    private func directionKey(_ bit: Int32, systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.title2)
            .frame(width: 56, height: 56)
            .background(.ultraThinMaterial, in: Circle())
            .contentShape(Circle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in setJoystickBit(bit, pressed: true) }
                    .onEnded { _ in setJoystickBit(bit, pressed: false) }
            )
    }

    private var dPad: some View {
        VStack(spacing: 4) {
            directionKey(ATARIST_JOY_UP, systemImage: "chevron.up")
            HStack(spacing: 4) {
                directionKey(ATARIST_JOY_LEFT, systemImage: "chevron.left")
                // The centre spacer keeps the cross shape hittable without a
                // dead zone in the middle.
                Color.clear.frame(width: 56, height: 56)
                directionKey(ATARIST_JOY_RIGHT, systemImage: "chevron.right")
            }
            directionKey(ATARIST_JOY_DOWN, systemImage: "chevron.down")
        }
    }

    private var fireButton: some View {
        Image(systemName: "circle.fill")
            .font(.system(size: 64))
            .foregroundStyle(.red.opacity(0.85))
            .contentShape(Circle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in setJoystickBit(ATARIST_JOY_FIRE, pressed: true) }
                    .onEnded { _ in setJoystickBit(ATARIST_JOY_FIRE, pressed: false) }
            )
    }

    private func setJoystickBit(_ bit: Int32, pressed: Bool) {
        let newMask = pressed ? joystickMask | bit : joystickMask & ~bit
        guard newMask != joystickMask else { return }
        joystickMask = newMask
        core.joystick(newMask)
    }
}
