//
//  TouchPadDesigner.swift
//
//  The edit-mode side panel for the touch pad, ported from the C++
//  designer_controls() / cluster_panel() split: general pad controls
//  (Movement / Opacity / Add a button / Reset layout) in one panel, and the
//  selected control's Size / Spacing / Shown / Remove in a second panel that
//  only appears while something is selected. Every mutation saves the layout
//  immediately (the C++ returns "changed" to its host for the same reason).
//

import SwiftUI

struct TouchPadDesigner: View {
    @ObservedObject var pad: TouchPadController
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            if !pad.selection.isEmpty {
                clusterPanel
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .bottom))
            }
            generalPanel
                .padding(.horizontal)
                .padding(.bottom, 8)
        }
    }

    // MARK: General pad controls (designer_controls)

    private var generalPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Arrange controls")
                    .font(.headline)
                Spacer()
                Button("Done", action: onDone)
                    .font(.headline)
            }

            HStack {
                Text("Movement")
                Spacer()
                Picker("Movement", selection: Binding(
                    get: { pad.stickStyle },
                    set: { pad.stickStyle = $0 })) {
                    Text("Stick").tag(PadStick.wobble)
                    Text("D-pad").tag(PadStick.dpad)
                }
                .pickerStyle(.segmented)
                .frame(width: 180)
            }

            HStack {
                Text("Opacity")
                Slider(value: Binding(
                    get: { Double(pad.opacity) },
                    set: { pad.opacity = Float($0) }),
                    in: Double(PadLimits.minOpacity)...Double(PadLimits.maxOpacity))
                Text("\(Int((pad.opacity * 100).rounded()))%")
                    .font(.caption.monospacedDigit())
                    .frame(width: 44, alignment: .trailing)
            }

            HStack {
                Menu {
                    if pad.allowDirectionButtons {
                        Section("Joystick direction") {
                            ForEach(directionItems) { item in
                                Button(item.label) { pad.addExtra(id: item.id, label: item.label) }
                                    .disabled(hasExtra(item.id))
                            }
                        }
                    }
                    Section("Buttons") {
                        ForEach(pad.profile.clusters.flatMap(\.buttons), id: \.id) { b in
                            Button(b.label) { pad.addExtra(id: b.id, label: b.label) }
                                .disabled(hasExtra(b.id))
                        }
                    }
                } label: {
                    Label("Add a button...", systemImage: "plus.circle")
                }
                Spacer()
                Button("Reset layout", role: .destructive) { pad.resetLayout() }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: Selected-cluster panel (cluster_panel)

    private var clusterPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(pad.selectedTitle)
                    .font(.headline)
                Spacer()
                if pad.selectedIsExtra {
                    Button("Remove", role: .destructive) { pad.removeSelected() }
                }
                Button("Close") { pad.clearSelection() }
            }

            HStack {
                Text("Size")
                Slider(value: Binding(
                    get: { Double(pad.selectedScale) },
                    set: { pad.selectedScale = Float($0) }),
                    in: Double(PadLimits.minScale)...Double(PadLimits.maxScale))
                Text(String(format: "%.2fx", pad.selectedScale))
                    .font(.caption.monospacedDigit())
                    .frame(width: 52, alignment: .trailing)
            }

            HStack {
                Text("Spacing")
                Slider(value: Binding(
                    get: { Double(pad.selectedSpacing) },
                    set: { pad.selectedSpacing = Float($0) }),
                    in: Double(PadLimits.minSpacing)...Double(PadLimits.maxSpacing))
                Text(String(format: "%.2fx", pad.selectedSpacing))
                    .font(.caption.monospacedDigit())
                    .frame(width: 52, alignment: .trailing)
            }

            if !pad.selectedIsExtra {
                Toggle("Shown", isOn: Binding(
                    get: { pad.selectedVisible },
                    set: { pad.selectedVisible = $0 }))
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func hasExtra(_ id: String) -> Bool {
        pad.engine.layout.extras.contains { $0.id == id }
    }

    private struct DirectionItem: Identifiable {
        let id: String
        let label: String
    }

    private let directionItems = [
        DirectionItem(id: "dir:up", label: "UP"),
        DirectionItem(id: "dir:down", label: "DOWN"),
        DirectionItem(id: "dir:left", label: "LEFT"),
        DirectionItem(id: "dir:right", label: "RIGHT"),
    ]
}
