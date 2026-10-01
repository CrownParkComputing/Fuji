//
//  AtariCore.swift
//
//  Swift wrapper around the plain-C ABI in atarist_bridge.h. The bridge is
//  the *entire* surface: no Hatari types cross into Swift, and everything
//  here is callable from the main thread (input is lock-free; reset, media
//  and snapshots are marshalled to the emulation thread by the bridge).
//

import Foundation

/// Launcher-facing machine description, mirrored field-for-field onto the
/// bridge's flat AtariStConfig. Persisted in UserDefaults so MachineSetupView
/// (@AppStorage) and the boot path read the same values.
struct MachineSettings {
    var machine: Int32 = ATARIST_MACHINE_ST
    var memoryKB: Int32 = 1024
    // RGB, not MONO: TOS reads the monitor type at boot and picks its screen
    // mode from it, and a mono monitor puts the machine in ST-HIGH (640x400,
    // two colours) where essentially no game runs. This is a machine part,
    // not a preference.
    var monitor: Int32 = ATARIST_MONITOR_RGB
    var blitter = false
    var accurateFloppy = false
    var joystickEnabled = true

    enum Key {
        static let machine = "machine"
        static let memoryKB = "memoryKB"
        static let monitor = "monitor"
        static let blitter = "blitter"
        static let accurateFloppy = "accurateFloppy"
        static let joystickEnabled = "joystickEnabled"
    }

    /// Registers the defaults so @AppStorage and this loader cannot disagree
    /// about what an unset key means.
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Key.machine: Int(MachineSettings().machine),
            Key.memoryKB: Int(MachineSettings().memoryKB),
            Key.monitor: Int(MachineSettings().monitor),
            Key.blitter: false,
            Key.accurateFloppy: false,
            Key.joystickEnabled: true,
        ])
    }

    static func load() -> MachineSettings {
        let d = UserDefaults.standard
        return MachineSettings(
            machine: Int32(d.integer(forKey: Key.machine)),
            memoryKB: Int32(d.integer(forKey: Key.memoryKB)),
            monitor: Int32(d.integer(forKey: Key.monitor)),
            blitter: d.bool(forKey: Key.blitter),
            accurateFloppy: d.bool(forKey: Key.accurateFloppy),
            joystickEnabled: d.bool(forKey: Key.joystickEnabled))
    }
}

final class AtariCore: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var fps = 0
    @Published private(set) var audioLevel = 0
    @Published var lastError: String?
    @Published var showKeyboard = false

    /// State slots surfaced by the controls overlay. The bridge keys snapshots
    /// by slot within the running title's directory, so three slots per title
    /// is plenty and keeps the overlay small enough to reach with a thumb.
    static let stateSlots: [Int32] = [0, 1, 2]

    private var initialised = false
    /// Config paths are strdup'd because the bridge is handed raw pointers;
    /// they stay allocated until stop so a re-start while running can never
    /// dangle, whatever the bridge does with them internally.
    private var configStrings: [UnsafeMutablePointer<CChar>] = []
    private var statusTimer: Timer?

    // MARK: - Filesystem layout

    // Everything user-visible lives under Documents/AtariST so it shows up in
    // the Files app (UIFileSharingEnabled); Hatari's own scratch state goes to
    // Application Support, which the user should never have to see.
    private static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var rootDirectory: URL {
        documents.appendingPathComponent("AtariST", isDirectory: true)
    }

    static var gamesDirectory: URL {
        rootDirectory.appendingPathComponent("Games", isDirectory: true)
    }

    static var demoDirectory: URL {
        rootDirectory.appendingPathComponent("Demo", isDirectory: true)
    }

    static var demoDisk: URL {
        demoDirectory.appendingPathComponent("stdesk-core-demo.st")
    }

    private static var tosDirectory: URL {
        rootDirectory.appendingPathComponent("TOS", isDirectory: true)
    }

    private static var workDirectory: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory,
                                               in: .userDomainMask)[0]
        return support.appendingPathComponent("STDeskCore", isDirectory: true)
    }

    /// Disk-image filename extensions the launcher lists and imports. Kept in
    /// sync with the UTType declarations in Info.plist and the floppy formats
    /// the bridge documents (.st, .msa, .dim, .stx, .ipf, .img, .zip).
    static let gameExtensions: Set<String> = ["st", "msa", "dim", "stx", "ipf", "img", "zip"]

    /// Extensions a TOS ROM image is likely to carry.
    private static let tosExtensions: Set<String> = ["img", "rom", "bin"]

    /// The ROM to boot with: one the user supplied if there is one,
    /// otherwise the bundled EmuTOS.
    ///
    /// The bridge does NOT look in tos_dir for this, despite taking the
    /// directory in atarist_core_init -- it boots whatever cfg.tos_path
    /// names and nothing else. Passing nil and expecting a scan left
    /// cfg_tos empty, so every start returned ATARIST_NO_TOS and the app
    /// could not run at all. Resolving it here keeps the decision on the
    /// side that knows where the files are.
    static var resolvedTOS: URL? {
        let fm = FileManager.default
        let bundledName = "emutos-1.4-uk.img"
        let roms = ((try? fm.contentsOfDirectory(at: tosDirectory,
                                                 includingPropertiesForKeys: nil)) ?? [])
            .filter { tosExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        // A real TOS the user owns wins: EmuTOS is the fallback, not the
        // preference, and the review notes promise exactly that behaviour.
        if let own = roms.first(where: { $0.lastPathComponent != bundledName }) {
            return own
        }
        return roms.first(where: { $0.lastPathComponent == bundledName })
    }

    // MARK: - Lifecycle

    init() {
        MachineSettings.registerDefaults()
    }

    /// One-time setup: create the folder layout, install the bundled EmuTOS
    /// and demo disk on first launch, then let the bridge scan for the ROM.
    /// atarist_core_init is documented as safe to call repeatedly; the flag
    /// just saves the filesystem work.
    func initialiseIfNeeded() {
        guard !initialised else { return }
        let fm = FileManager.default
        for url in [Self.rootDirectory, Self.tosDirectory, Self.gamesDirectory,
                    Self.demoDirectory, Self.workDirectory] {
            try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        }

        // Copied rather than referenced in the bundle because the user is
        // expected to drop a real (copyrighted) TOS next to it via Files.
        let installedTOS = Self.tosDirectory.appendingPathComponent("emutos-1.4-uk.img")
        if !fm.fileExists(atPath: installedTOS.path),
           let bundled = Bundle.main.url(forResource: "emutos-1.4-uk",
                                         withExtension: "img",
                                         subdirectory: "EmuTOS") {
            try? fm.copyItem(at: bundled, to: installedTOS)
        }

        let demo = Self.demoDisk
        if !fm.fileExists(atPath: demo.path),
           let bundledDemo = Bundle.main.url(forResource: "stdesk-core-demo",
                                             withExtension: "st",
                                             subdirectory: "Demo") {
            try? fm.copyItem(at: bundledDemo, to: demo)
        }

        atarist_core_init(Self.workDirectory.path, Self.tosDirectory.path)
        initialised = true

        // A bridge whose ABI we do not know would fail later and stranger;
        // say so up front. Never expected in a statically linked build, but
        // the check is one integer comparison.
        if atarist_core_abi_version() != ATARIST_BRIDGE_ABI {
            lastError = "Core ABI mismatch (got \(atarist_core_abi_version()), expected \(ATARIST_BRIDGE_ABI))"
        }
    }

    /// Boot the machine with [game] in drive A (nil = boot to the desktop).
    ///
    /// Deliberately a bare atarist_core_start with no stop first: when a core
    /// is already running the bridge re-points it at the new configuration and
    /// cold resets, because Hatari cannot be Main_Init'd twice in one process.
    /// "Start this title" therefore means the same thing whether or not
    /// something else was running.
    func start(game: URL?) {
        initialiseIfNeeded()
        let settings = MachineSettings.load()

        func dup(_ string: String?) -> UnsafePointer<CChar>? {
            guard let string else { return nil }
            let copy = strdup(string)
            configStrings.append(copy!)
            return UnsafePointer(copy)
        }

        var config = AtariStConfig(
            machine: settings.machine,
            memory_kb: settings.memoryKB,
            // Named explicitly. The bridge does not scan tos_dir; it boots
            // cfg.tos_path or returns ATARIST_NO_TOS.
            tos_path: dup(Self.resolvedTOS?.path),
            floppy_a: dup(game?.path),
            floppy_b: nil,
            gemdos_dir: nil,
            acsi_image: nil,
            ide_image: nil,
            blitter: settings.blitter ? 1 : 0,
            accurate_floppy: settings.accurateFloppy ? 1 : 0,
            sample_rate: 0,
            // STE and up have DMA stereo sound; a plain ST is mono.
            stereo: settings.machine >= ATARIST_MACHINE_STE ? 1 : 0,
            monitor: settings.monitor,
            joystick_port1: settings.joystickEnabled ? 1 : 0,
            work_dir: dup(Self.workDirectory.path))

        let result = atarist_core_start(&config)
        switch result {
        case ATARIST_OK:
            isRunning = true
            lastError = nil
            startStatusTimer()
        case ATARIST_NO_TOS:
            lastError = "No TOS image found. The bundled EmuTOS is missing — reinstall the app, or drop a TOS ROM into the AtariST/TOS folder in Files."
        default:
            lastError = Self.bridgeString(atarist_core_last_error())
                ?? "The core failed to start (error \(result))."
        }
    }

    /// Soft stop: eject media, cold reset, park the machine. Hatari stays
    /// initialised underneath because it cannot be initialised twice; the
    /// launcher simply returns to the library screen.
    func stop() {
        if atarist_core_is_running() != 0 {
            atarist_core_stop()
        }
        isRunning = false
        showKeyboard = false
        statusTimer?.invalidate()
        statusTimer = nil
        for string in configStrings { free(string) }
        configStrings.removeAll()
    }

    /// Cold = power cycle, warm = the ST's reset button.
    func reset(cold: Bool) {
        let result = atarist_core_reset(cold ? 1 : 0)
        if result != ATARIST_OK {
            lastError = Self.bridgeString(atarist_core_last_error())
        }
    }

    // MARK: - Media

    /// Insert or eject (nil) a floppy while the machine is running -- what a
    /// multi-disk game's "insert disk 2" prompt needs.
    func setFloppy(_ url: URL?, drive: Int32 = ATARIST_DRIVE_A) {
        let result = atarist_core_set_floppy(drive, url?.path)
        if result != ATARIST_OK {
            lastError = Self.bridgeString(atarist_core_last_error())
        }
    }

    /// The games currently in the library folder, display-ready.
    func libraryGames() -> [URL] {
        let fm = FileManager.default
        let urls = (try? fm.contentsOfDirectory(
            at: Self.gamesDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles])) ?? []
        return urls
            .filter { Self.gameExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// Copy an imported disk image into the library. fileImporter hands out
    /// security-scoped URLs that go stale, so the file has to be copied before
    /// the scope is dropped.
    @discardableResult
    func importGame(from url: URL) -> URL? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let destination = Self.gamesDirectory.appendingPathComponent(url.lastPathComponent)
        let fm = FileManager.default
        if fm.fileExists(atPath: destination.path) {
            try? fm.removeItem(at: destination)
        }
        do {
            try fm.copyItem(at: url, to: destination)
            return destination
        } catch {
            lastError = "Could not import \(url.lastPathComponent): \(error.localizedDescription)"
            return nil
        }
    }

    // MARK: - Input

    /// ST scan code, not a character: games read the IKBD's make/break codes
    /// directly, so press and release are delivered as separate events.
    func keyEvent(_ scancode: Int32, pressed: Bool) {
        guard isRunning else { return }
        atarist_core_key_event(scancode, pressed ? 1 : 0)
    }

    /// Port 1 -- the port games actually use. [mask] is ATARIST_JOY_* bits.
    func joystick(_ mask: Int32) {
        guard isRunning else { return }
        atarist_core_joystick(1, mask)
    }

    func mouseMotion(dx: Int32, dy: Int32) {
        guard isRunning else { return }
        atarist_core_mouse_motion(dx, dy)
    }

    /// button: 0 left, 1 right.
    func mouseButton(_ button: Int32, pressed: Bool) {
        guard isRunning else { return }
        atarist_core_mouse_button(button, pressed ? 1 : 0)
    }

    // MARK: - Save states

    /// Synchronous to the caller but executed on the emulation thread through
    /// the bridge's mailbox -- ST machine state must never be touched from
    /// this thread directly.
    func saveState(slot: Int32) {
        let result = atarist_core_save_state(slot)
        if result != ATARIST_OK {
            lastError = result == ATARIST_TIMEOUT
                ? "The emulator did not answer the save request in time."
                : Self.bridgeString(atarist_core_last_error())
        }
    }

    func loadState(slot: Int32) {
        let result = atarist_core_load_state(slot)
        if result != ATARIST_OK {
            lastError = result == ATARIST_TIMEOUT
                ? "The emulator did not answer the load request in time."
                : Self.bridgeString(atarist_core_last_error())
        }
    }

    func isStateEmpty(slot: Int32) -> Bool {
        atarist_core_state_is_empty(slot) == 1
    }

    // MARK: - Status

    var hatariVersion: String { Self.bridgeString(atarist_core_hatari_version()) ?? "unknown" }
    var audioBackend: String { Self.bridgeString(atarist_core_audio_backend()) ?? "unknown" }
    var bridgeABI: Int32 { atarist_core_abi_version() }

    static func bridgeString(_ pointer: UnsafePointer<CChar>?) -> String? {
        guard let pointer else { return nil }
        return String(cString: pointer)
    }

    private func startStatusTimer() {
        statusTimer?.invalidate()
        statusTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, self.isRunning else { return }
            // Int(): the bridge returns int32_t and both properties are
            // Int. Swift will not widen a C integer for you.
            self.fps = Int(atarist_core_fps())
            self.audioLevel = Int(atarist_core_audio_level())
        }
    }
}
