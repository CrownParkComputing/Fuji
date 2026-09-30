//
//  LauncherView.swift
//
//  The game library: disk images in Documents/AtariST/Games, importable via
//  the system file picker. With an empty library the bundled core demo is the
//  only thing to run -- it exists so a fresh install can prove video, audio
//  and input end to end without the user owning any ST software.
//

import SwiftUI
import UniformTypeIdentifiers

/// Content types the importer accepts. The .st/.msa/.dim/.stx/.img set is one
/// declared UTType (see UTImportedTypeDeclarations in Info.plist); .ipf is
/// kept separate because it is a preservation format rather than a plain
/// sector image, and .zip is the system's own type.
extension UTType {
    static let atariDiskImage = UTType(importedAs: "com.crownparkcomputing.fuji.atari-disk-image")
    static let atariIPF = UTType(importedAs: "com.crownparkcomputing.fuji.atari-ipf")
}

struct LauncherView: View {
    @EnvironmentObject private var core: AtariCore

    @State private var games: [URL] = []
    @State private var showImporter = false
    @State private var showMachineSetup = false
    @State private var showAbout = false
    @State private var showError = false

    var body: some View {
        NavigationStack {
            Group {
                if games.isEmpty {
                    emptyLibrary
                } else {
                    gameList
                }
            }
            .navigationTitle("Fuji")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showAbout = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showMachineSetup = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    Button {
                        showImporter = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.atariDiskImage, .atariIPF, .zip],
                allowsMultipleSelection: true
            ) { result in
                if case .success(let urls) = result {
                    for url in urls { core.importGame(from: url) }
                    refreshLibrary()
                }
            }
            .sheet(isPresented: $showMachineSetup) {
                MachineSetupView()
            }
            .sheet(isPresented: $showAbout) {
                AboutView()
                    .environmentObject(core)
            }
            .alert("Atari ST", isPresented: $showError, presenting: core.lastError) { _ in
                Button("OK") { core.lastError = nil }
            } message: { message in
                Text(message)
            }
            .onChange(of: core.lastError) { newValue in
                showError = newValue != nil
            }
            .onAppear(perform: refreshLibrary)
        }
    }

    private var emptyLibrary: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "opticaldisc")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("No disk images yet")
                .font(.title2)
            Text("Import .st, .msa, .dim, .stx, .ipf, .img or .zip images with the + button, or copy them into the AtariST folder in the Files app.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            if FileManager.default.fileExists(atPath: AtariCore.demoDisk.path) {
                Button {
                    core.start(game: AtariCore.demoDisk)
                } label: {
                    Label("Run bundled core demo", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
            }
            Spacer()
        }
    }

    private var gameList: some View {
        List {
            ForEach(games, id: \.self) { game in
                Button {
                    core.start(game: game)
                } label: {
                    Label(game.deletingPathExtension().lastPathComponent,
                          systemImage: "opticaldisc")
                        .foregroundStyle(.primary)
                }
            }
            .onDelete { offsets in
                for index in offsets {
                    try? FileManager.default.removeItem(at: games[index])
                }
                refreshLibrary()
            }
        }
    }

    private func refreshLibrary() {
        games = core.libraryGames()
    }
}

/// Version and audio backend, surfaced deliberately: "no sound" and "no sink
/// on this platform" look identical from the speakers, and this screen is the
/// difference.
struct AboutView: View {
    @EnvironmentObject private var core: AtariCore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Core") {
                    LabeledContent("Hatari version", value: core.hatariVersion)
                    LabeledContent("Audio backend", value: core.audioBackend)
                    LabeledContent("Bridge ABI", value: "\(core.bridgeABI)")
                }
                Section("ROM") {
                    Text("Fuji ships with EmuTOS 1.4, an open-source replacement for the Atari ST ROM. You can drop an original TOS image into AtariST/TOS in the Files app.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("About Fuji")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
