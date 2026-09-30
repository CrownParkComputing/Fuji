//
//  MachineSetupView.swift
//
//  The machine the launcher boots. These are hardware choices, not cosmetic
//  preferences: TOS reads the monitor type at boot and picks its screen mode
//  from it, so a mono monitor puts the machine in ST-HIGH (640x400, two
//  colours) where essentially no game runs -- the default stays RGB.
//

import SwiftUI

struct MachineSetupView: View {
    // Keys shared with MachineSettings.load(); @AppStorage writes, the boot
    // path reads. Defaults are registered in AtariCore.init.
    @AppStorage(MachineSettings.Key.machine) private var machine: Int = Int(ATARIST_MACHINE_ST)
    @AppStorage(MachineSettings.Key.memoryKB) private var memoryKB: Int = 1024
    @AppStorage(MachineSettings.Key.monitor) private var monitor: Int = Int(ATARIST_MONITOR_RGB)
    @AppStorage(MachineSettings.Key.blitter) private var blitter = false
    @AppStorage(MachineSettings.Key.accurateFloppy) private var accurateFloppy = false
    @AppStorage(MachineSettings.Key.joystickEnabled) private var joystickEnabled = true

    @Environment(\.dismiss) private var dismiss

    private let machines: [(name: String, value: Int32)] = [
        ("ST", ATARIST_MACHINE_ST),
        ("Mega ST", ATARIST_MACHINE_MEGA_ST),
        ("STE", ATARIST_MACHINE_STE),
        ("Mega STE", ATARIST_MACHINE_MEGA_STE),
        ("TT", ATARIST_MACHINE_TT),
        ("Falcon", ATARIST_MACHINE_FALCON),
    ]

    // The set the bridge documents; 0 would mean "Hatari's default", which
    // varies by machine and makes the setting unpredictable.
    private let memorySizes = [512, 1024, 2048, 4096]

    private let monitors: [(name: String, value: Int32)] = [
        ("RGB colour", ATARIST_MONITOR_RGB),
        ("TV", ATARIST_MONITOR_TV),
        ("Mono (desktop apps only)", ATARIST_MONITOR_MONO),
        ("VGA (TT/Falcon)", ATARIST_MONITOR_VGA),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Machine") {
                    Picker("Model", selection: $machine) {
                        ForEach(machines, id: \.value) { entry in
                            Text(entry.name).tag(Int(entry.value))
                        }
                    }
                    Picker("Memory", selection: $memoryKB) {
                        ForEach(memorySizes, id: \.self) { size in
                            Text(size >= 1024 ? "\(size / 1024) MB" : "\(size) KB").tag(size)
                        }
                    }
                    Picker("Monitor", selection: $monitor) {
                        ForEach(monitors, id: \.value) { entry in
                            Text(entry.name).tag(Int(entry.value))
                        }
                    }
                }

                Section {
                    Toggle("Blitter", isOn: $blitter)
                    Toggle("Accurate floppy timing", isOn: $accurateFloppy)
                } footer: {
                    Text("The Blitter is Mega ST / STE hardware; enabling it on a plain ST is a Hatari extension some demos want. Accurate FDC timing is needed by protected originals but loads much more slowly.")
                }

                Section {
                    Toggle("Joystick in port 1", isOn: $joystickEnabled)
                } footer: {
                    Text("Port 1 is the port games use. Driven by the on-screen d-pad while a title is running.")
                }
            }
            .navigationTitle("Machine")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
