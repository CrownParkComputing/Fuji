//
//  TouchPad.swift
//
//  The model half of retro_touch_pad, the Retro-* family's shared on-screen
//  controller, ported from Retro-Saturn's frontend/touch_pad.cpp (the C++ is
//  authoritative -- read the header comment there first). Same ideas and the
//  same layout file, so an arrangement made in one app means the same thing
//  in another:
//
//    profile  what a machine has: clusters of buttons with default places,
//             and a stick or d-pad. Data, not code -- one overlay draws
//             every one.
//    layout   where the player put them: fractions of the play area (a
//             phone held either way and a tablet agree), a scale and a
//             hidden flag per cluster, plus any extra buttons they added.
//    overlay  draws a layout over the picture and turns fingers into
//             presses (TouchPadOverlayView.swift).
//
//  The layout JSON is byte-compatible with the C++ encoder: same keys, same
//  nesting, same %.4g number formatting, cluster ids sorted (std::map
//  order). A file written by Shifter must load in Retro-Saturn and vice versa.
//

import CoreGraphics
import Foundation

// MARK: - Enums

enum PadShape {
    case column, row, diamond, grid3x2
}

enum PadFace {
    case circle, pill, square
}

enum PadStick {
    case wobble, dpad
}

// MARK: - Profile

struct PadButton {
    let id: String      // what the host switches on: "fire", "key:57"
    let label: String
    let colour: UInt32  // 0xRRGGBBAA
    let size: Float     // logical pixels at scale 1
    let face: PadFace
}

struct PadCluster {
    let id: String
    let label: String
    let dx: Float
    let dy: Float       // default centre, as fractions
    let isStick: Bool
    let stickSize: Float // diameter at scale 1
    let shape: PadShape
    let buttons: [PadButton]
}

struct PadProfile {
    let id: String      // stable: it names the layout file
    let name: String
    let defaultStick: PadStick
    let allowDirectionButtons: Bool
    let clusters: [PadCluster]

    func cluster(_ id: String) -> PadCluster? {
        clusters.first { $0.id == id }
    }
}

// The pad palette, lifted from the C++ (IM_COL32 values rewritten as
// 0xRRGGBBAA). Not serialised, so the packing change is invisible to files.
enum PadColour {
    static let red: UInt32    = 0xDC3232FF
    static let blue: UInt32   = 0x3050DCFF
    static let green: UInt32  = 0x2E9E44FF
    static let yellow: UInt32 = 0xD8C43CFF
    static let grey: UInt32   = 0x5A5A5AFF
    static let slate: UInt32  = 0x6E7681FF
    static let accent: UInt32 = 0x34D9C4FF
    static let extraDefault: UInt32 = 0x8A94A6FF
}

enum PadProfiles {
    private static func stick(_ id: String, _ label: String, _ dx: Float, _ dy: Float) -> PadCluster {
        PadCluster(id: id, label: label, dx: dx, dy: dy,
                   isStick: true, stickSize: 150, shape: .column, buttons: [])
    }

    private static func buttons(_ id: String, _ label: String, _ dx: Float, _ dy: Float,
                                _ shape: PadShape, _ buttons: [PadButton]) -> PadCluster {
        PadCluster(id: id, label: label, dx: dx, dy: dy,
                   isStick: false, stickSize: 0, shape: shape, buttons: buttons)
    }

    private static func btn(_ id: String, _ label: String, _ colour: UInt32,
                            _ size: Float = 64, _ face: PadFace = .circle) -> PadButton {
        PadButton(id: id, label: label, colour: colour, size: size, face: face)
    }

    /// The 360 pad most people know. Machine-neutral: the host maps the ids.
    static let xbox360 = PadProfile(
        id: "xbox360", name: "360 pad",
        defaultStick: .dpad, allowDirectionButtons: false,
        clusters: [
            stick("dpad", "D-pad", 0.13, 0.70),
            buttons("face", "Buttons", 0.86, 0.68, .diamond, [
                btn("y", "Y", PadColour.yellow, 58), btn("x", "X", PadColour.blue, 58),
                btn("b", "B", PadColour.red, 58),    btn("a", "A", PadColour.green, 58)]),
            buttons("shoulder_l", "LB / LT", 0.10, 0.14, .row, [
                btn("lt", "LT", PadColour.slate, 44, .pill), btn("lb", "LB", PadColour.slate, 44, .pill)]),
            buttons("shoulder_r", "RB / RT", 0.90, 0.14, .row, [
                btn("rb", "RB", PadColour.slate, 44, .pill), btn("rt", "RT", PadColour.slate, 44, .pill)]),
            buttons("meta", "Back / Start", 0.50, 0.92, .row, [
                btn("back", "BACK", PadColour.grey, 34, .pill), btn("start", "START", PadColour.grey, 34, .pill)]),
        ])

    /// Stick and two fire buttons: the least glass covered.
    static let generic = PadProfile(
        id: "generic", name: "Joystick",
        defaultStick: .wobble, allowDirectionButtons: true,
        clusters: [
            stick("stick", "Stick", 0.13, 0.74),
            buttons("fire", "Fire", 0.89, 0.72, .column, [
                btn("fire2", "2", PadColour.blue, 72), btn("fire1", "1", PadColour.red, 72)]),
        ])

    /// The real thing: six face buttons in two rows, L/R, Start.
    static let saturn = PadProfile(
        id: "saturn", name: "Saturn pad",
        defaultStick: .dpad, allowDirectionButtons: false,
        clusters: [
            stick("dpad", "D-pad", 0.13, 0.70),
            buttons("face", "Buttons", 0.82, 0.70, .grid3x2, [
                btn("x", "X", PadColour.slate, 50), btn("y", "Y", PadColour.slate, 50), btn("z", "Z", PadColour.slate, 50),
                btn("a", "A", PadColour.red, 56),   btn("b", "B", PadColour.blue, 56),   btn("c", "C", PadColour.green, 56)]),
            buttons("triggers", "L / R", 0.50, 0.10, .row, [
                btn("l", "L", PadColour.slate, 44, .pill), btn("start", "START", PadColour.grey, 34, .pill),
                btn("r", "R", PadColour.slate, 44, .pill)]),
        ])

    /// The Atari ST joystick is digital: four directions and ONE fire button.
    /// Modeled on profile_generic() with the second fire button dropped --
    /// there is nothing on an ST for it to map to.
    static let atarist = PadProfile(
        id: "atarist", name: "Atari ST",
        defaultStick: .wobble, allowDirectionButtons: true,
        clusters: [
            stick("stick", "Stick", 0.13, 0.74),
            buttons("fire", "Fire", 0.89, 0.72, .column, [
                btn("fire", "FIRE", PadColour.red, 72)]),
        ])

    /// Ids match the rest of the family's profiles.
    static func byId(_ id: String) -> PadProfile? {
        switch id {
        case "xbox360": return xbox360
        case "generic": return generic
        case "saturn":  return saturn
        case "atarist": return atarist
        default:        return nil
        }
    }
}

// MARK: - Layout

struct PadPlaced {
    var dx: Float
    var dy: Float
    var scale: Float = 1      // size multiplier; user-tunable per cluster
    var spacing: Float = 1    // gap between buttons INSIDE this cluster
    var visible: Bool = true
}

struct PadExtra {
    var id: String        // "dir:up" for a direction, else a host action
    var label: String
    var dx: Float
    var dy: Float
    var scale: Float = 1
    var spacing: Float = 1 // kept on extras so an added button participates
                           // in the same model as a cluster

    var isDirection: Bool { id.hasPrefix("dir:") }
}

struct PadLayout {
    var profile: String = ""
    var clusters: [String: PadPlaced] = [:]
    var extras: [PadExtra] = []
    var stick: PadStick = .wobble
    var opacity: Float = 0.75

    static func defaults(for p: PadProfile) -> PadLayout {
        var l = PadLayout()
        l.profile = p.id
        l.stick = p.defaultStick
        for c in p.clusters {
            l.clusters[c.id] = PadPlaced(dx: c.dx, dy: c.dy)
        }
        return l
    }
}

// MARK: - Limits (shared with the overlay and the designer)

enum PadLimits {
    static let minPos: Float = 0.04
    static let maxPos: Float = 0.96
    /// 0.5..3.0x: was 0.6..1.6 upstream until 2026-09-18 — the wider ceiling
    /// lets one drag cover the "make it all bigger" case.
    static let minScale: Float = 0.5
    static let maxScale: Float = 3.0
    static let minSpacing: Float = 0.5
    static let maxSpacing: Float = 2.5
    static let minOpacity: Float = 0.2
    static let maxOpacity: Float = 1.0

    static func clamp(_ v: Float, _ lo: Float, _ hi: Float) -> Float {
        min(hi, max(lo, v))
    }
}

// MARK: - JSON

private func padQuote(_ s: String) -> String {
    var o = "\""
    for c in s {
        if c == "\"" || c == "\\" { o += "\\"; o.append(c) }
        else if c == "\n" { o += "\\n" }
        else { o.append(c) }
    }
    return o + "\""
}

/// %.4g, exactly as the C++ encoder formats: up to four significant digits,
/// no trailing zeros, always a decimal point. String(format:) without a
/// locale argument is not localised, so a German device cannot turn 0.75
/// into "0,75" and corrupt every file it saves.
private func padNum(_ v: Float) -> String {
    String(format: "%.4g", Double(v))
}

private func padNumber(_ v: Any?, default d: Float) -> Float {
    (v as? NSNumber)?.floatValue ?? d
}

extension PadLayout {

    /// Anything unreadable, or written for another profile, is the defaults:
    /// a corrupt file must never be the reason a game has no controls.
    static func decode(_ json: String, for p: PadProfile) -> PadLayout {
        let d = defaults(for: p)
        guard !json.isEmpty,
              let data = json.data(using: .utf8),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              (root["profile"] as? String) == p.id
        else { return d }

        var l = d
        if let st = root["stick"] as? String {
            l.stick = st == "dpad" ? .dpad : st == "wobble" ? .wobble : p.defaultStick
        }
        if let op = root["opacity"] {
            l.opacity = PadLimits.clamp(padNumber(op, default: 0.75),
                                        PadLimits.minOpacity, PadLimits.maxOpacity)
        }

        // A "pos" pair: array of >= 2 numbers, each clamped into the play
        // area. A non-number element keeps the value it came in with, which
        // is what the C++ does via J::num(default).
        func point(_ v: Any?, _ x: inout Float, _ y: inout Float) -> Bool {
            guard let a = v as? [Any], a.count >= 2 else { return false }
            x = PadLimits.clamp(padNumber(a[0], default: x), PadLimits.minPos, PadLimits.maxPos)
            y = PadLimits.clamp(padNumber(a[1], default: y), PadLimits.minPos, PadLimits.maxPos)
            return true
        }

        if let cs = root["clusters"] as? [String: Any] {
            // Array(): the keys view shares storage with the dictionary,
            // which we mutate inside the loop.
            for cid in Array(l.clusters.keys) {
                guard let c = cs[cid] as? [String: Any] else { continue } // newer cluster: default
                var placed = l.clusters[cid]!
                _ = point(c["pos"], &placed.dx, &placed.dy)
                if let s = c["scale"] {
                    placed.scale = PadLimits.clamp(padNumber(s, default: 1),
                                                   PadLimits.minScale, PadLimits.maxScale)
                }
                if let sp = c["spacing"] {
                    placed.spacing = PadLimits.clamp(padNumber(sp, default: 1),
                                                     PadLimits.minSpacing, PadLimits.maxSpacing)
                }
                if let v = c["visible"] {
                    placed.visible = (v as? NSNumber)?.boolValue ?? true
                }
                l.clusters[cid] = placed
            }
        }

        if let ex = root["extras"] as? [Any] {
            for e in ex {
                guard let entry = e as? [String: Any],
                      let action = entry["action"] as? [String: Any],
                      let id = action["id"] as? String, !id.isEmpty
                else { continue }
                var x = PadExtra(id: id, label: action["label"] as? String ?? id, dx: 0.5, dy: 0.5)
                // A direction's label is derived, never stored: the C++
                // uppercases the part after "dir:" whatever the file says.
                if x.isDirection { x.label = String(id.dropFirst(4)).uppercased() }
                guard point(entry["pos"], &x.dx, &x.dy) else { continue }
                if let s = entry["scale"] {
                    x.scale = PadLimits.clamp(padNumber(s, default: 1),
                                              PadLimits.minScale, PadLimits.maxScale)
                }
                if let sp = entry["spacing"] {
                    x.spacing = PadLimits.clamp(padNumber(sp, default: 1),
                                                PadLimits.minSpacing, PadLimits.maxSpacing)
                }
                if !l.extras.contains(where: { $0.id == x.id }) {
                    l.extras.append(x)
                }
            }
        }
        return l
    }

    /// Byte-compatible with the C++ encode(): identical key order and
    /// nesting, cluster ids sorted (std::map order), extras written WITHOUT
    /// their spacing (the C++ reads it back but never writes it -- an
    /// upstream asymmetry kept on purpose so diffs stay empty).
    func encode() -> String {
        var o = "{\"version\":1,\"profile\":" + padQuote(profile) +
                ",\"stick\":" + padQuote(stick == .dpad ? "dpad" : "wobble") +
                ",\"opacity\":" + padNum(opacity) + ",\"clusters\":{"
        var first = true
        for cid in clusters.keys.sorted() {
            let p = clusters[cid]!
            if !first { o += "," }
            first = false
            o += padQuote(cid) + ":{\"pos\":[" + padNum(p.dx) + "," + padNum(p.dy) +
                 "],\"scale\":" + padNum(p.scale) +
                 ",\"spacing\":" + padNum(p.spacing) +
                 ",\"visible\":" + (p.visible ? "true" : "false") + "}"
        }
        o += "},\"extras\":["
        first = true
        for e in extras {
            if !first { o += "," }
            first = false
            o += "{\"action\":{\"id\":" + padQuote(e.id) + ",\"label\":" + padQuote(e.label)
            if e.isDirection {
                o += ",\"kind\":\"direction\",\"code\":0,\"direction\":" + padQuote(String(e.id.dropFirst(4)))
            } else {
                o += ",\"kind\":\"button\",\"code\":0"
            }
            o += "},\"pos\":[" + padNum(e.dx) + "," + padNum(e.dy) + "],\"scale\":" + padNum(e.scale) + "}"
        }
        return o + "]}"
    }

    static func fileFor(dir: String, profile p: PadProfile) -> String {
        var d = dir
        if !d.isEmpty && !d.hasSuffix("/") && !d.hasSuffix("\\") { d += "/" }
        return d + "pad_layout_" + p.id + ".json"
    }

    static func load(dir: String, for p: PadProfile) -> PadLayout {
        guard let data = FileManager.default.contents(atPath: fileFor(dir: dir, profile: p)),
              let json = String(data: data, encoding: .utf8)
        else { return defaults(for: p) }
        return decode(json, for: p)
    }

    /// Written whole to a .tmp and renamed into place: a crash mid-write
    /// then strands a .tmp file, never a half-written layout that decode()
    /// would (admittedly) survive by falling back to defaults.
    @discardableResult
    func save(dir: String) -> Bool {
        guard let p = PadProfiles.byId(profile) else { return false }
        let path = PadLayout.fileFor(dir: dir, profile: p)
        let tmp = path + ".tmp"
        do {
            try encode().write(toFile: tmp, atomically: false, encoding: .utf8)
            // POSIX rename() overwrites; moveItem refuses to, so the old
            // file goes first. The .tmp is complete on disk before this
            // point, so the window without any layout is microscopic.
            if FileManager.default.fileExists(atPath: path) {
                try FileManager.default.removeItem(atPath: path)
            }
            try FileManager.default.moveItem(atPath: tmp, toPath: path)
            return true
        } catch {
            return false
        }
    }
}
