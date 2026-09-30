//
//  STKeyboardView.swift
//
//  On-screen Atari ST keyboard. Keys send IKBD make/break scan codes -- the
//  ST's own codes, not host keycodes or characters -- because games read the
//  IKBD directly and anything higher-level loses the key-up half, leaving a
//  direction held down forever. The scan codes below are the same set the
//  native C++ frontend's keyboard uses (Hatari's ikbd layout).
//

import SwiftUI

struct STKeyboardView: View {
    @EnvironmentObject private var core: AtariCore

    private struct Key: Identifiable {
        let label: String
        let code: Int32
        var id: Int32 { code }
    }

    // Row order matches the physical ST keyboard, top to bottom.
    private let functions: [Key] = [
        Key(label: "Esc", code: 0x01),
        Key(label: "F1", code: 0x3B), Key(label: "F2", code: 0x3C),
        Key(label: "F3", code: 0x3D), Key(label: "F4", code: 0x3E),
        Key(label: "F5", code: 0x3F), Key(label: "F6", code: 0x40),
        Key(label: "F7", code: 0x41), Key(label: "F8", code: 0x42),
        Key(label: "F9", code: 0x43), Key(label: "F10", code: 0x44),
        Key(label: "Help", code: 0x62), Key(label: "Undo", code: 0x61),
    ]

    private let numbers: [Key] = [
        Key(label: "`", code: 0x29),
        Key(label: "1", code: 0x02), Key(label: "2", code: 0x03),
        Key(label: "3", code: 0x04), Key(label: "4", code: 0x05),
        Key(label: "5", code: 0x06), Key(label: "6", code: 0x07),
        Key(label: "7", code: 0x08), Key(label: "8", code: 0x09),
        Key(label: "9", code: 0x0A), Key(label: "0", code: 0x0B),
        Key(label: "-", code: 0x0C), Key(label: "=", code: 0x0D),
        Key(label: "⌫", code: 0x0E),
    ]

    private let qwerty: [Key] = [
        Key(label: "Tab", code: 0x0F),
        Key(label: "Q", code: 0x10), Key(label: "W", code: 0x11),
        Key(label: "E", code: 0x12), Key(label: "R", code: 0x13),
        Key(label: "T", code: 0x14), Key(label: "Y", code: 0x15),
        Key(label: "U", code: 0x16), Key(label: "I", code: 0x17),
        Key(label: "O", code: 0x18), Key(label: "P", code: 0x19),
        Key(label: "[", code: 0x1A), Key(label: "]", code: 0x1B),
        Key(label: "⏎", code: 0x1C),
    ]

    private let home: [Key] = [
        Key(label: "Ctrl", code: 0x1D),
        Key(label: "A", code: 0x1E), Key(label: "S", code: 0x1F),
        Key(label: "D", code: 0x20), Key(label: "F", code: 0x21),
        Key(label: "G", code: 0x22), Key(label: "H", code: 0x23),
        Key(label: "J", code: 0x24), Key(label: "K", code: 0x25),
        Key(label: "L", code: 0x26), Key(label: ";", code: 0x27),
        Key(label: "'", code: 0x28), Key(label: "#", code: 0x2B),
    ]

    private let lower: [Key] = [
        Key(label: "⇧", code: 0x2A), Key(label: "<", code: 0x60),
        Key(label: "Z", code: 0x2C), Key(label: "X", code: 0x2D),
        Key(label: "C", code: 0x2E), Key(label: "V", code: 0x2F),
        Key(label: "B", code: 0x30), Key(label: "N", code: 0x31),
        Key(label: "M", code: 0x32), Key(label: ",", code: 0x33),
        Key(label: ".", code: 0x34), Key(label: "/", code: 0x35),
        Key(label: "⇧", code: 0x36),
    ]

    private let bottom: [Key] = [
        Key(label: "Caps", code: 0x3A), Key(label: "Alt", code: 0x38),
        Key(label: "Space", code: 0x39),
        Key(label: "Ins", code: 0x52), Key(label: "Home", code: 0x47),
        Key(label: "←", code: 0x4B), Key(label: "↓", code: 0x50),
        Key(label: "↑", code: 0x48), Key(label: "→", code: 0x4D),
        Key(label: "Del", code: 0x53),
    ]

    var body: some View {
        VStack(spacing: 4) {
            keyRow(functions)
            keyRow(numbers)
            keyRow(qwerty)
            keyRow(home)
            keyRow(lower)
            keyRow(bottom)
        }
        .padding(6)
        .background(.ultraThinMaterial)
    }

    private func keyRow(_ keys: [Key]) -> some View {
        HStack(spacing: 4) {
            ForEach(keys) { key in
                KeyButton(label: key.label) { pressed in
                    core.keyEvent(key.code, pressed: pressed)
                }
                // Space earns its keep: most games start on it.
                .layoutPriority(key.code == 0x39 ? 3 : 1)
            }
        }
    }
}

/// A single key reporting press AND release. SwiftUI's Button only reports
/// the completed tap, so a zero-distance DragGesture supplies the make/break
/// pair instead -- same trick the d-pad uses, for the same reason.
private struct KeyButton: View {
    let label: String
    let onPressChange: (Bool) -> Void

    @State private var pressed = false

    var body: some View {
        Text(label)
            .font(.caption.weight(.medium))
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background(pressed ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in setPressed(true) }
                    .onEnded { _ in setPressed(false) }
            )
    }

    private func setPressed(_ value: Bool) {
        guard value != pressed else { return }
        pressed = value
        onPressChange(value)
    }
}
