//
//  TouchPadOverlayView.swift
//
//  The overlay half of retro_touch_pad: draws a layout over the picture and
//  turns fingers into presses. Ported from the Overlay class in Retro-
//  Saturn's frontend/touch_pad.cpp; the semantics are the same so the shared
//  layout file behaves identically here.
//
//  Directions are MERGED -- the stick and any "UP as a button" extra are
//  combined inside the engine, so the host never sees two sources fighting
//  over the same joystick bits.
//
//  SwiftUI gestures don't track several independent fingers well, so the
//  interactive surface is a UIView (isMultipleTouchEnabled = true), each
//  UITouch tracked by identity the way the C++ tracks SDL_FingerID. The
//  mouse-as-finger-0 path of the C++ has no meaning on iOS; its slot in the
//  structure is kept by treating an unclaimed first touch as the emulated
//  ST mouse instead (see TouchPadUIView).
//

import CoreGraphics
import SwiftUI
import UIKit

/// The host's end of the pad: pressed(action id, down) and
/// directions(u, d, l, r). Everything else is inside the engine.
struct PadSink {
    var directions: (_ up: Bool, _ down: Bool, _ left: Bool, _ right: Bool) -> Void
    var action: (_ id: String, _ down: Bool) -> Void
}

/// One pressable thing, in pixels, for the current area. kind is "stick",
/// "button" or "extra".
struct PadHit {
    var kind: String
    var id: String
    var centre: CGPoint
    var radius: CGFloat   // > 0 for circular hits
    var half: CGSize      // box half-extents for rectangular hits
}

private struct PadPointer {
    var pos: CGPoint
    var on: String = ""
    var stick = false
}

/// Room for a cluster's name above it while arranging. A constant, not the
/// font size: hits are tested between frames.
private let kLabelStrip: CGFloat = 18

/// An estimate, not a measurement: hit boxes must match what is drawn
/// whichever side computes them, and hit testing happens between draws when
/// no laid-out text exists to measure. Bold capitals in the UI font run at
/// about 0.62 em, and a pill is padded anyway.
private func padTextWidth(_ s: String, _ fontSize: CGFloat) -> CGFloat {
    CGFloat(s.count) * fontSize * 0.62
}

// MARK: - Engine (the C++ Overlay class, view-free)

final class TouchPadEngine {
    private(set) var profile: PadProfile?
    var layout = PadLayout()
    private(set) var editing = false
    var selected = ""             // editing: cluster id or "extra:<id>"
    var sink: PadSink?

    private var dirty = false
    private var hits: [PadHit] = []
    private var pointers: [ObjectIdentifier: PadPointer] = [:]
    private var held: [String: Int] = [:]       // action id -> pointer count
    private var sent = (up: false, down: false, left: false, right: false)
    private(set) var stickActive = false
    private var dragging = ""
    private var dragLast = CGPoint.zero
    private var lastArea = CGRect.zero

    /// Switching pad releases everything the old one held -- the caller
    /// releases first if it cares; set() itself just drops the state,
    /// exactly as the C++ does.
    func set(_ p: PadProfile, _ l: PadLayout) {
        profile = p
        layout = l
        pointers.removeAll(); held.removeAll()
        stickActive = false
        selected = ""; dragging = ""
        hits.removeAll()
        sent = (false, false, false, false)
    }

    /// Arranging: controls drag instead of press; a tap selects one for the
    /// size slider. The STDesk host releases everything BEFORE entering edit
    /// mode (the C++ relies on its host doing the same -- entering with a
    /// button held would strand it in held_ forever).
    func setEditing(_ on: Bool) {
        guard editing != on else { return }
        editing = on
        pointers.removeAll(); dragging = ""
        if !on { selected = "" }
    }

    /// True once a drag has ended since the last call -- the moment to save.
    func takeDirty() -> Bool {
        let d = dirty; dirty = false; return d
    }

    func clearHits() { hits.removeAll() }

    /// Let go of everything held: leaving the game, hiding the pad.
    func releaseAll() {
        guard let sink else { return }
        for (id, n) in held where n > 0 && !id.hasPrefix("dir:") {
            sink.action(id, false)
        }
        held.removeAll()
        pointers.removeAll()
        stickActive = false
        recompute()
    }

    // MARK: Hit building

    /// Every pressable thing, in pixels, for this area. Rebuilt each draw
    /// (and on demand by handle) because the window can change size under a
    /// finger.
    func rebuildHits(area: CGRect) {
        hits.removeAll()
        lastArea = area
        guard let prof = profile else { return }

        func centreOf(_ dx: Float, _ dy: Float) -> CGPoint {
            CGPoint(x: area.minX + CGFloat(dx) * area.width,
                    y: area.minY + CGFloat(dy) * area.height)
        }
        func addCircle(_ kind: String, _ id: String, _ c: CGPoint, _ r: CGFloat) {
            hits.append(PadHit(kind: kind, id: id, centre: c, radius: r, half: .zero))
        }
        func addBox(_ kind: String, _ id: String, _ c: CGPoint, _ half: CGSize) {
            hits.append(PadHit(kind: kind, id: id, centre: c, radius: 0, half: half))
        }

        for c in prof.clusters {
            guard let p = layout.clusters[c.id] else { continue }
            if !p.visible && !editing { continue }
            let cc = centreOf(p.dx, p.dy)
            let sc = CGFloat(p.scale)
            if c.isStick {
                addCircle("stick", c.id, cc, CGFloat(c.stickSize) * sc * 0.5)
                continue
            }
            // Per-cluster spacing multiplies the gap between buttons INSIDE
            // this cluster; combined with the cluster's own scale this lets
            // the user push buttons apart without disturbing the cluster's
            // position in the play area.
            let sp = CGFloat(p.spacing)
            let gap = 10 * sc * sp
            switch c.shape {
            case .column:
                var total: CGFloat = 0
                for b in c.buttons { total += CGFloat(b.size) * sc }
                total += gap * CGFloat(c.buttons.count - 1)
                var y = cc.y - total * 0.5
                for b in c.buttons {
                    let s = CGFloat(b.size) * sc
                    addCircle("button", b.id, CGPoint(x: cc.x, y: y + s * 0.5), s * 0.5)
                    y += s + gap
                }
            case .row:
                var widths: [CGFloat] = []
                var total: CGFloat = 0
                for b in c.buttons {
                    let s = CGFloat(b.size) * sc
                    let w = b.face == .pill
                        ? max(s, padTextWidth(b.label, s * 0.34) + s * 0.6) : s
                    widths.append(w); total += w
                }
                total += gap * CGFloat(c.buttons.count - 1)
                var x = cc.x - total * 0.5
                for (i, b) in c.buttons.enumerated() {
                    let s = CGFloat(b.size) * sc
                    let centre = CGPoint(x: x + widths[i] * 0.5, y: cc.y)
                    if b.face == .pill {
                        addBox("button", b.id, centre, CGSize(width: widths[i] * 0.5, height: s * 0.5))
                    } else {
                        addCircle("button", b.id, centre, s * 0.5)
                    }
                    x += widths[i] + gap
                }
            case .diamond:
                var d: CGFloat = 0
                for b in c.buttons { d = max(d, CGFloat(b.size) * sc) }
                let side = d * 2.7 * sp
                let at = [CGPoint(x: cc.x, y: cc.y - side * 0.5 + d * 0.5),
                          CGPoint(x: cc.x - side * 0.5 + d * 0.5, y: cc.y),
                          CGPoint(x: cc.x + side * 0.5 - d * 0.5, y: cc.y),
                          CGPoint(x: cc.x, y: cc.y + side * 0.5 - d * 0.5)]
                for i in 0..<min(c.buttons.count, 4) {
                    addCircle("button", c.buttons[i].id, at[i], CGFloat(c.buttons[i].size) * sc * 0.5)
                }
            case .grid3x2:
                for i in 0..<min(c.buttons.count, 6) {
                    let row = i / 3, col = i % 3
                    var roww: CGFloat = 0
                    var j = row * 3
                    while j < row * 3 + 3 && j < c.buttons.count {
                        roww += CGFloat(c.buttons[j].size) * sc + (j > row * 3 ? gap : 0)
                        j += 1
                    }
                    var toph: CGFloat = 0, both: CGFloat = 0
                    for k in 0..<min(3, c.buttons.count) { toph = max(toph, CGFloat(c.buttons[k].size) * sc) }
                    // 3..<n would trap when fewer than 4 buttons exist;
                    // the C++ loop condition handles it, so guard instead.
                    if c.buttons.count > 3 {
                        for k in 3..<min(6, c.buttons.count) { both = max(both, CGFloat(c.buttons[k].size) * sc) }
                    }
                    let totalH = toph + gap + both
                    let y = cc.y - totalH * 0.5 + (row == 0 ? toph * 0.5 : toph + gap + both * 0.5)
                    var x = cc.x - roww * 0.5
                    for k in 0..<col { x += CGFloat(c.buttons[row * 3 + k].size) * sc + gap }
                    x += CGFloat(c.buttons[i].size) * sc * 0.5
                    addCircle("button", c.buttons[i].id, CGPoint(x: x, y: y), CGFloat(c.buttons[i].size) * sc * 0.5)
                }
            }
        }
        for e in layout.extras {
            let s = 52 * CGFloat(e.scale)
            let w = max(s, padTextWidth(e.label, s * 0.3) + s * 0.6)
            addBox("extra", e.id, centreOf(e.dx, e.dy), CGSize(width: w * 0.5, height: s * 0.5))
        }
    }

    private func hitAt(_ p: CGPoint) -> PadHit? {
        // Extras were added last and sit on top.
        for h in hits.reversed() {
            if h.radius > 0 {
                let dx = p.x - h.centre.x, dy = p.y - h.centre.y
                // A little slack round a button: a thumb is not a point.
                let r = h.radius * (h.kind == "stick" ? 1.0 : 1.15)
                if dx * dx + dy * dy <= r * r { return h }
            } else {
                if abs(p.x - h.centre.x) <= h.half.width * 1.1 + 4 &&
                   abs(p.y - h.centre.y) <= h.half.height * 1.1 + 4 { return h }
            }
        }
        return nil
    }

    /// Editing: which movable thing is under a point. Extras by themselves;
    /// a cluster by the whole framed box drawn round it, not just its
    /// buttons -- the middle of a diamond is empty, and a grab that misses
    /// there reads as a pad that will not move.
    private func selectAt(_ p: CGPoint) -> String {
        guard let prof = profile else { return "" }
        // Extras first: they can sit over a cluster.
        for e in layout.extras {
            let c = CGPoint(x: lastArea.minX + CGFloat(e.dx) * lastArea.width,
                            y: lastArea.minY + CGFloat(e.dy) * lastArea.height)
            let s = 52 * CGFloat(e.scale)
            let w = max(s, padTextWidth(e.label, s * 0.3) + s * 0.6)
            if abs(p.x - c.x) <= w * 0.5 + 12 && abs(p.y - c.y) <= s * 0.5 + 16 {
                return "extra:" + e.id
            }
        }
        for c in prof.clusters {
            var mn = CGPoint(x: CGFloat.greatestFiniteMagnitude, y: CGFloat.greatestFiniteMagnitude)
            var mx = CGPoint(x: -CGFloat.greatestFiniteMagnitude, y: -CGFloat.greatestFiniteMagnitude)
            var any = false
            for h in hits {
                var mine = h.kind == "stick" && h.id == c.id
                if !mine && h.kind == "button" {
                    mine = c.buttons.contains { $0.id == h.id }
                }
                guard mine else { continue }
                any = true
                let hx = h.radius > 0 ? h.radius : h.half.width
                let hy = h.radius > 0 ? h.radius : h.half.height
                mn.x = min(mn.x, h.centre.x - hx); mn.y = min(mn.y, h.centre.y - hy)
                mx.x = max(mx.x, h.centre.x + hx); mx.y = max(mx.y, h.centre.y + hy)
            }
            guard any else { continue }
            // The same padding the frame is drawn with, label strip included.
            if p.x >= mn.x - 10 && p.x <= mx.x + 10 &&
               p.y >= mn.y - 10 - kLabelStrip && p.y <= mx.y + 10 {
                return c.id
            }
        }
        return ""
    }

    // MARK: Presses and merged directions

    private func press(_ id: String, _ down: Bool) {
        guard let sink else { return }
        // held_ counting: two fingers on the same button press once and
        // release once -- the action fires on the 0->1 and 1->0 transitions.
        let old = held[id] ?? 0
        let n = max(0, old + (down ? 1 : -1))
        held[id] = n
        let was = old > 0
        let now = n > 0
        if was == now { return }
        if id.hasPrefix("dir:") { recompute(); return }
        sink.action(id, now)
    }

    /// The stick's four bits and the direction buttons, merged, sent on
    /// change.
    private func recompute() {
        guard let sink else { return }
        var u = false, d = false, l = false, r = false
        for (_, ptr) in pointers where ptr.stick {
            guard let h = hits.first(where: { $0.kind == "stick" }) else { continue }
            let dx = Float((ptr.pos.x - h.centre.x) / h.radius)
            let dy = Float((ptr.pos.y - h.centre.y) / h.radius)
            let dist = sqrt(dx * dx + dy * dy)
            if dist < 0.18 { continue }
            if layout.stick == .wobble {
                // Eight 45-degree sectors centred on the compass points.
                var deg = atan2(dy, dx) * 180 / .pi
                if deg < 0 { deg += 360 }
                let sector = Int(floor((deg + 22.5) / 45)) % 8
                // 0 R, 1 DR, 2 D, 3 DL, 4 L, 5 UL, 6 U, 7 UR
                r = r || sector == 0 || sector == 1 || sector == 7
                d = d || sector == 1 || sector == 2 || sector == 3
                l = l || sector == 3 || sector == 4 || sector == 5
                u = u || sector == 5 || sector == 6 || sector == 7
            } else {
                // Lower than 45 degrees on purpose: wider diagonal corners,
                // which are hard to hold on glass with no edge to find.
                let t: Float = 0.38
                if dx <= -t { l = true }
                if dx >= t  { r = true }
                if dy <= -t { u = true }
                if dy >= t  { d = true }
            }
        }
        u = u || (held["dir:up"] ?? 0) > 0
        d = d || (held["dir:down"] ?? 0) > 0
        l = l || (held["dir:left"] ?? 0) > 0
        r = r || (held["dir:right"] ?? 0) > 0
        stickActive = u || d || l || r
        if u == sent.up && d == sent.down && l == sent.left && r == sent.right { return }
        sent = (u, d, l, r)
        sink.directions(u, d, l, r)
    }

    // MARK: Touch entry point

    enum Phase { case down, moved, up }

    /// One touch event. Returns true when the touch was for the pad and the
    /// host should not also treat it as a mouse click. area is where the pad
    /// is laid out, in the view's pixels.
    func handle(_ phase: Phase, id: ObjectIdentifier, at p: CGPoint, area: CGRect) -> Bool {
        guard profile != nil else { return false }
        if hits.isEmpty || lastArea.size != area.size || lastArea.origin != area.origin {
            rebuildHits(area: area)
        }

        // ---- arranging ----
        if editing {
            switch phase {
            case .down:
                // A tap on an extra's red badge removes it.
                for e in layout.extras {
                    let c = CGPoint(x: area.minX + CGFloat(e.dx) * area.width,
                                    y: area.minY + CGFloat(e.dy) * area.height)
                    let s = 52 * CGFloat(e.scale)
                    let w = max(s, padTextWidth(e.label, s * 0.3) + s * 0.6)
                    let badge = CGPoint(x: c.x + w * 0.5 + 6, y: c.y - s * 0.5 - 6)
                    if abs(p.x - badge.x) <= 16 && abs(p.y - badge.y) <= 16 {
                        let gone = e.id
                        layout.extras.removeAll { $0.id == gone }
                        if selected == "extra:" + gone { selected = "" }
                        dirty = true
                        rebuildHits(area: area)
                        return true
                    }
                }
                let s = selectAt(p)
                if !s.isEmpty { selected = s; dragging = s; dragLast = p }
                return true
            case .moved:
                if !dragging.isEmpty {
                    let fx = Float((p.x - dragLast.x) / area.width)
                    let fy = Float((p.y - dragLast.y) / area.height)
                    dragLast = p
                    if dragging.hasPrefix("extra:") {
                        for i in layout.extras.indices where "extra:" + layout.extras[i].id == dragging {
                            layout.extras[i].dx = PadLimits.clamp(layout.extras[i].dx + fx,
                                                                  PadLimits.minPos, PadLimits.maxPos)
                            layout.extras[i].dy = PadLimits.clamp(layout.extras[i].dy + fy,
                                                                  PadLimits.minPos, PadLimits.maxPos)
                        }
                    } else if var placed = layout.clusters[dragging] {
                        placed.dx = PadLimits.clamp(placed.dx + fx, PadLimits.minPos, PadLimits.maxPos)
                        placed.dy = PadLimits.clamp(placed.dy + fy, PadLimits.minPos, PadLimits.maxPos)
                        layout.clusters[dragging] = placed
                    }
                    rebuildHits(area: area)
                }
                return true
            case .up:
                if !dragging.isEmpty { dragging = ""; dirty = true }
                return true
            }
        }

        // ---- playing ----
        switch phase {
        case .down:
            guard let h = hitAt(p) else { return false }
            var ptr = PadPointer(pos: p)
            if h.kind == "stick" {
                ptr.stick = true
                pointers[id] = ptr
                recompute()
            } else {
                ptr.on = h.id
                pointers[id] = ptr
                press(h.id, true)
            }
            return true
        case .moved:
            guard var ptr = pointers[id] else { return false }
            ptr.pos = p
            pointers[id] = ptr
            if ptr.stick {
                recompute()
            } else {
                // Sliding from one button onto the next changes the press
                // without lifting off, the way a thumb rolls across a pad.
                let h = hitAt(p)
                let now = (h != nil && h!.kind != "stick") ? h!.id : ptr.on
                if now != ptr.on {
                    press(ptr.on, false)
                    ptr.on = now
                    pointers[id] = ptr
                    press(now, true)
                }
            }
            return true
        case .up:
            guard let ptr = pointers[id] else { return false }
            pointers.removeValue(forKey: id)
            if ptr.stick {
                recompute()
            } else {
                press(ptr.on, false)
            }
            return true
        }
    }

    // MARK: Drawing

    private func withAlpha(_ c: UInt32, _ a: CGFloat) -> UIColor {
        let clamped = PadLimits.clamp(Float(a), 0, 1)
        return UIColor(red: CGFloat((c >> 24) & 0xFF) / 255,
                       green: CGFloat((c >> 16) & 0xFF) / 255,
                       blue: CGFloat((c >> 8) & 0xFF) / 255,
                       alpha: CGFloat(clamped))
    }

    private func drawLabel(_ text: String, at c: CGPoint, size: CGFloat, colour: UIColor) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: size),
            .foregroundColor: colour,
        ]
        let ts = (text as NSString).size(withAttributes: attrs)
        (text as NSString).draw(at: CGPoint(x: c.x - ts.width * 0.5, y: c.y - ts.height * 0.5),
                                withAttributes: attrs)
    }

    /// Draws the pad into the current context. Mirrors Overlay::draw.
    func draw(in ctx: CGContext, area: CGRect) {
        guard let prof = profile else { return }
        rebuildHits(area: area)
        let op = editing ? CGFloat(1) : CGFloat(layout.opacity)

        // Where the stick pointer is, for the knob.
        var knob = CGPoint.zero
        var haveKnob = false
        for (_, ptr) in pointers where ptr.stick { knob = ptr.pos; haveKnob = true }

        for h in hits {
            if h.kind == "stick" {
                let dim: CGFloat = (layout.clusters[h.id]?.visible ?? true) ? 1 : 0.3
                let r = h.radius
                let c = h.centre
                if layout.stick == .wobble {
                    ctx.setFillColor(withAlpha(0x5F6670FF, 0.27 * op * dim).cgColor)
                    ctx.fillEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
                    ctx.setStrokeColor(withAlpha(0xD6DADFFF, 0.6 * op * dim).cgColor)
                    ctx.setLineWidth(max(2, r * 0.04))
                    ctx.strokeEllipse(in: CGRect(x: c.x - (r - 2), y: c.y - (r - 2),
                                                 width: 2 * (r - 2), height: 2 * (r - 2)))
                    ctx.setStrokeColor(withAlpha(0xD6DADFFF, 0.2 * op * dim).cgColor)
                    ctx.setLineWidth(1)
                    for frac in [0.35, 0.68] as [CGFloat] {
                        ctx.strokeEllipse(in: CGRect(x: c.x - r * frac, y: c.y - r * frac,
                                                     width: 2 * r * frac, height: 2 * r * frac))
                    }
                    var off = CGSize.zero
                    if haveKnob {
                        off = CGSize(width: knob.x - c.x, height: knob.y - c.y)
                        let d = sqrt(off.width * off.width + off.height * off.height)
                        let maxd = r * 0.6
                        if d > maxd { off.width *= maxd / d; off.height *= maxd / d }
                    }
                    let kc = CGPoint(x: c.x + off.width, y: c.y + off.height)
                    let kr = r * 0.4
                    ctx.setFillColor(withAlpha(0x000000FF, 0.35 * op * dim).cgColor)
                    ctx.fillEllipse(in: CGRect(x: kc.x - off.width * 0.15 - kr * 0.95,
                                               y: kc.y - off.height * 0.15 + 3 - kr * 0.95,
                                               width: 2 * kr * 0.95, height: 2 * kr * 0.95))
                    ctx.setFillColor(withAlpha(stickActive ? PadColour.accent : 0xC5CBD3FF, 0.88 * op * dim).cgColor)
                    ctx.fillEllipse(in: CGRect(x: kc.x - kr, y: kc.y - kr, width: 2 * kr, height: 2 * kr))
                    ctx.setFillColor(withAlpha(0xFFFFFFFF, 0.45 * op * dim).cgColor)
                    ctx.fillEllipse(in: CGRect(x: kc.x - kr * 0.3 - kr * 0.35, y: kc.y - kr * 0.3 - kr * 0.35,
                                               width: 2 * kr * 0.35, height: 2 * kr * 0.35))
                    ctx.setStrokeColor(withAlpha(0xFFFFFFFF, 0.93 * op * dim).cgColor)
                    ctx.setLineWidth(max(1.5, r * 0.024))
                    ctx.strokeEllipse(in: CGRect(x: kc.x - kr, y: kc.y - kr, width: 2 * kr, height: 2 * kr))
                } else {
                    // The d-pad: two crossed arms, pressed arms highlighted,
                    // arrow glyphs at the tips.
                    let arm = r * 2.0 * 0.30
                    let fill = withAlpha(0xFFFFFFFF, 0.10 * op * dim)
                    let on = withAlpha(PadColour.accent, 0.55 * op * dim)
                    let line = withAlpha(0xFFFFFFFF, 0.55 * op * dim)
                    let rnd = arm * 0.25
                    let vRect = CGRect(x: c.x - arm / 2, y: c.y - r, width: arm, height: 2 * r)
                    let hRect = CGRect(x: c.x - r, y: c.y - arm / 2, width: 2 * r, height: arm)
                    fill.setFill()
                    UIBezierPath(roundedRect: vRect, cornerRadius: rnd).fill()
                    UIBezierPath(roundedRect: hRect, cornerRadius: rnd).fill()
                    on.setFill()
                    if sent.up {
                        UIBezierPath(roundedRect: CGRect(x: c.x - arm / 2, y: c.y - r,
                                                         width: arm, height: r - arm / 2),
                                     cornerRadius: rnd).fill()
                    }
                    if sent.down {
                        UIBezierPath(roundedRect: CGRect(x: c.x - arm / 2, y: c.y + arm / 2,
                                                         width: arm, height: r - arm / 2),
                                     cornerRadius: rnd).fill()
                    }
                    if sent.left {
                        UIBezierPath(roundedRect: CGRect(x: c.x - r, y: c.y - arm / 2,
                                                         width: r - arm / 2, height: arm),
                                     cornerRadius: rnd).fill()
                    }
                    if sent.right {
                        UIBezierPath(roundedRect: CGRect(x: c.x + arm / 2, y: c.y - arm / 2,
                                                         width: r - arm / 2, height: arm),
                                     cornerRadius: rnd).fill()
                    }
                    line.setStroke()
                    for rect in [vRect, hRect] {
                        let path = UIBezierPath(roundedRect: rect, cornerRadius: rnd)
                        path.lineWidth = 1.5
                        path.stroke()
                    }
                    let g = arm * 0.28
                    withAlpha(0xFFFFFFFF, 0.7 * op * dim).setFill()
                    for triangle in [
                        [CGPoint(x: c.x, y: c.y - r + g * 0.8), CGPoint(x: c.x - g, y: c.y - r + g * 2), CGPoint(x: c.x + g, y: c.y - r + g * 2)],
                        [CGPoint(x: c.x, y: c.y + r - g * 0.8), CGPoint(x: c.x + g, y: c.y + r - g * 2), CGPoint(x: c.x - g, y: c.y + r - g * 2)],
                        [CGPoint(x: c.x - r + g * 0.8, y: c.y), CGPoint(x: c.x - r + g * 2, y: c.y + g), CGPoint(x: c.x - r + g * 2, y: c.y - g)],
                        [CGPoint(x: c.x + r - g * 0.8, y: c.y), CGPoint(x: c.x + r - g * 2, y: c.y - g), CGPoint(x: c.x + r - g * 2, y: c.y + g)],
                    ] {
                        let path = UIBezierPath()
                        path.move(to: triangle[0])
                        path.addLine(to: triangle[1])
                        path.addLine(to: triangle[2])
                        path.close()
                        path.fill()
                    }
                }
                continue
            }

            // A button, from a cluster or an extra.
            var spec: PadButton?
            var owner: PadCluster?
            if h.kind == "button" {
                for c in prof.clusters {
                    for b in c.buttons where b.id == h.id { spec = b; owner = c }
                }
            }
            var extra: PadExtra?
            if h.kind == "extra" {
                extra = layout.extras.first { $0.id == h.id }
            }
            guard spec != nil || extra != nil else { continue }

            let down = (held[h.id] ?? 0) > 0
            var dim: CGFloat = 1
            if let owner, !(layout.clusters[owner.id]?.visible ?? true) { dim = 0.3 }
            let base = spec?.colour ?? (extra!.isDirection ? PadColour.accent : PadColour.extraDefault)
            let fill = withAlpha(base, (down ? 0.9 : 0.45) * op * dim)
            let edge = withAlpha(0xFFFFFFFF, (down ? 0.95 : 0.65) * op * dim)
            let ink = withAlpha(0xFFFFFFFF, op * dim)
            let s = h.radius > 0 ? h.radius * 2 : h.half.height * 2
            let label = spec?.label ?? extra!.label
            let fs = label.count > 3 ? s * 0.26 : s * (s < 50 ? 0.36 : 0.32)
            if h.radius > 0 && (spec == nil || spec!.face == .circle) {
                fill.setFill()
                ctx.fillEllipse(in: CGRect(x: h.centre.x - h.radius, y: h.centre.y - h.radius,
                                           width: 2 * h.radius, height: 2 * h.radius))
                edge.setStroke()
                ctx.setLineWidth(2)
                ctx.strokeEllipse(in: CGRect(x: h.centre.x - h.radius, y: h.centre.y - h.radius,
                                             width: 2 * h.radius, height: 2 * h.radius))
            } else {
                let rect = CGRect(x: h.centre.x - h.half.width, y: h.centre.y - h.half.height,
                                  width: h.half.width * 2, height: h.half.height * 2)
                let rnd = (spec != nil && spec!.face == .square) ? h.half.height * 0.36 : h.half.height
                fill.setFill()
                UIBezierPath(roundedRect: rect, cornerRadius: rnd).fill()
                edge.setStroke()
                let path = UIBezierPath(roundedRect: rect, cornerRadius: rnd)
                path.lineWidth = 2
                path.stroke()
            }
            drawLabel(label, at: h.centre, size: fs, colour: ink)
        }

        // ---- arranging chrome ----
        guard editing else { return }
        func frame(_ rect: CGRect, _ text: String, _ sel: Bool) {
            let col = withAlpha(sel ? PadColour.accent : 0xFFFFFFFF, sel ? 1 : 110.0 / 255.0)
            withAlpha(0x000000FF, 90.0 / 255.0).setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: 12).fill()
            col.setStroke()
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 12)
            path.lineWidth = 2
            path.stroke()
            if !text.isEmpty {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 13 * 0.8),
                    .foregroundColor: col,
                ]
                (text as NSString).draw(at: CGPoint(x: rect.minX + 8, y: rect.minY + 4), withAttributes: attrs)
            }
        }
        for c in prof.clusters {
            var mn = CGPoint(x: CGFloat.greatestFiniteMagnitude, y: CGFloat.greatestFiniteMagnitude)
            var mx = CGPoint(x: -CGFloat.greatestFiniteMagnitude, y: -CGFloat.greatestFiniteMagnitude)
            var any = false
            for h in hits {
                var mine = h.kind == "stick" && h.id == c.id
                if !mine && h.kind == "button" {
                    mine = c.buttons.contains { $0.id == h.id }
                }
                guard mine else { continue }
                any = true
                let hx = h.radius > 0 ? h.radius : h.half.width
                let hy = h.radius > 0 ? h.radius : h.half.height
                mn.x = min(mn.x, h.centre.x - hx); mn.y = min(mn.y, h.centre.y - hy)
                mx.x = max(mx.x, h.centre.x + hx); mx.y = max(mx.y, h.centre.y + hy)
            }
            guard any else { continue }
            frame(CGRect(x: mn.x - 10, y: mn.y - 10 - kLabelStrip,
                         width: mx.x - mn.x + 20, height: mx.y - mn.y + 20 + kLabelStrip),
                  c.label, selected == c.id)
        }
        for e in layout.extras {
            for h in hits where h.kind == "extra" && h.id == e.id {
                frame(CGRect(x: h.centre.x - h.half.width - 8, y: h.centre.y - h.half.height - 8,
                             width: h.half.width * 2 + 16, height: h.half.height * 2 + 16),
                      "", selected == "extra:" + e.id)
                // The red badge, inside room made for it.
                let badge = CGPoint(x: h.centre.x + h.half.width + 6, y: h.centre.y - h.half.height - 6)
                UIColor(red: 1, green: 82.0 / 255.0, blue: 82.0 / 255.0, alpha: 1).setFill()
                ctx.fillEllipse(in: CGRect(x: badge.x - 11, y: badge.y - 11, width: 22, height: 22))
                UIColor.white.setStroke()
                ctx.setLineWidth(2)
                ctx.move(to: CGPoint(x: badge.x - 4, y: badge.y - 4))
                ctx.addLine(to: CGPoint(x: badge.x + 4, y: badge.y + 4))
                ctx.move(to: CGPoint(x: badge.x - 4, y: badge.y + 4))
                ctx.addLine(to: CGPoint(x: badge.x + 4, y: badge.y - 4))
                ctx.strokePath()
            }
        }
    }
}

// MARK: - Controller (owns the engine, wires the sink to the core)

final class TouchPadController: ObservableObject {
    let engine = TouchPadEngine()
    let profile: PadProfile

    /// Editing state lives here so the designer panel and the overlay agree;
    /// mirrored selection so SwiftUI can show the cluster panel.
    @Published private(set) var editing = false
    @Published private(set) var selection = ""

    private weak var core: AtariCore?
    /// The ST joystick port 1 mask is one value carrying directions AND fire,
    /// so the two sink callbacks share the push rather than each sending a
    /// partial state that would stomp the other.
    private var dirMask: Int32 = 0
    private var fireDown = false

    /// Layouts live with the rest of the user-visible data, in Files.
    static var layoutsDirectory: URL {
        AtariCore.rootDirectory.appendingPathComponent("Layouts", isDirectory: true)
    }

    init(core: AtariCore, profile: PadProfile = PadProfiles.atarist) {
        self.core = core
        self.profile = profile
        try? FileManager.default.createDirectory(at: Self.layoutsDirectory,
                                                 withIntermediateDirectories: true)
        engine.sink = PadSink(
            directions: { [weak self] u, d, l, r in
                guard let self else { return }
                var mask: Int32 = 0
                if u { mask |= ATARIST_JOY_UP }
                if d { mask |= ATARIST_JOY_DOWN }
                if l { mask |= ATARIST_JOY_LEFT }
                if r { mask |= ATARIST_JOY_RIGHT }
                self.dirMask = mask
                self.pushJoystick()
            },
            action: { [weak self] id, down in
                guard let self, let core = self.core else { return }
                if id == "fire" {
                    self.fireDown = down
                    self.pushJoystick()
                } else if id.hasPrefix("key:"), let code = Int32(id.dropFirst(4)) {
                    // "key:<decimal ST scancode>" -- how a user adds e.g. a
                    // Space button (0x39 = 57) as an extra.
                    if core.isRunning { atarist_core_key_event(code, down ? 1 : 0) }
                }
            })
        engine.set(profile, PadLayout.load(dir: Self.layoutsDirectory.path, for: profile))
    }

    private func pushJoystick() {
        guard let core, core.isRunning, MachineSettings.load().joystickEnabled else { return }
        var mask = dirMask
        if fireDown { mask |= ATARIST_JOY_FIRE }
        atarist_core_joystick(1, mask)
    }

    /// Entering edit mode releases everything first: arranging with a fire
    /// button logically held would strand it pressed in the emulated
    /// machine with no finger left to lift.
    func setEditing(_ on: Bool) {
        guard editing != on else { return }
        if on { engine.releaseAll() }
        editing = on
        engine.setEditing(on)
        selection = engine.selected
    }

    /// Called after overlay touches are processed: mirrors the engine's
    /// selection into the @Published property and saves when a drag ended.
    func touchesSettled() {
        if engine.takeDirty() { save() }
        if selection != engine.selected { selection = engine.selected }
    }

    func releaseAll() { engine.releaseAll() }

    @discardableResult
    func save() -> Bool {
        engine.layout.save(dir: Self.layoutsDirectory.path)
    }

    private func changed() {
        engine.clearHits()
        save()
        objectWillChange.send()
    }

    // MARK: Designer operations (the C++ designer_controls / cluster_panel)

    var stickStyle: PadStick {
        get { engine.layout.stick }
        set {
            engine.layout.stick = newValue
            // The style change re-keys the stick hit, so anything held on
            // the old one must be let go before it is redrawn.
            engine.releaseAll()
            changed()
        }
    }

    var opacity: Float {
        get { engine.layout.opacity }
        set {
            engine.layout.opacity = PadLimits.clamp(newValue, PadLimits.minOpacity, PadLimits.maxOpacity)
            changed()
        }
    }

    var allowDirectionButtons: Bool { profile.allowDirectionButtons }

    /// Add a button: a direction (where the stick is a joystick) or a second
    /// copy of any of the pad's own buttons, placed independently. Adding
    /// selects the new extra, which is what brings the cluster panel up.
    func addExtra(id: String, label: String) {
        guard !engine.layout.extras.contains(where: { $0.id == id }) else { return }
        let n = engine.layout.extras.count
        let e = PadExtra(id: id, label: label,
                         dx: PadLimits.clamp(0.30 + 0.10 * Float(n % 5), PadLimits.minPos, PadLimits.maxPos),
                         dy: PadLimits.clamp(0.12 + 0.14 * Float(n / 5), PadLimits.minPos, PadLimits.maxPos))
        engine.layout.extras.append(e)
        engine.selected = "extra:" + id
        selection = engine.selected
        changed()
    }

    func resetLayout() {
        engine.layout = PadLayout.defaults(for: profile)
        engine.selected = ""
        selection = ""
        changed()
    }

    // Selected-cluster panel: Size, Spacing, Shown, Remove.
    var selectedScale: Float {
        get { selectedPlacement()?.scale ?? 1 }
        set { mutateSelected { $0.scale = PadLimits.clamp(newValue, PadLimits.minScale, PadLimits.maxScale) } }
    }

    var selectedSpacing: Float {
        get { selectedPlacement()?.spacing ?? 1 }
        set { mutateSelected { $0.spacing = PadLimits.clamp(newValue, PadLimits.minSpacing, PadLimits.maxSpacing) } }
    }

    var selectedVisible: Bool {
        get { selection.isEmpty || selection.hasPrefix("extra:")
                ? true : (engine.layout.clusters[selection]?.visible ?? true) }
        set {
            guard !selection.isEmpty, !selection.hasPrefix("extra:") else { return }
            engine.layout.clusters[selection]?.visible = newValue
            changed()
        }
    }

    var selectedTitle: String {
        if selection.hasPrefix("extra:") {
            let id = String(selection.dropFirst(6))
            return engine.layout.extras.first { $0.id == id }?.label ?? id
        }
        return profile.cluster(selection)?.label ?? selection
    }

    var selectedIsExtra: Bool { selection.hasPrefix("extra:") }

    func removeSelected() {
        guard selection.hasPrefix("extra:") else { return }
        let gone = String(selection.dropFirst(6))
        engine.layout.extras.removeAll { $0.id == gone }
        engine.selected = ""
        selection = ""
        changed()
    }

    func clearSelection() {
        engine.selected = ""
        selection = ""
        objectWillChange.send()
    }

    private func selectedPlacement() -> (scale: Float, spacing: Float)? {
        if selection.hasPrefix("extra:") {
            let id = String(selection.dropFirst(6))
            guard let e = engine.layout.extras.first(where: { $0.id == id }) else { return nil }
            return (e.scale, e.spacing)
        }
        guard let p = engine.layout.clusters[selection] else { return nil }
        return (p.scale, p.spacing)
    }

    private func mutateSelected(_ f: (inout PadPlaced) -> Void) {
        guard !selection.isEmpty else { return }
        if selection.hasPrefix("extra:") {
            let id = String(selection.dropFirst(6))
            guard let i = engine.layout.extras.firstIndex(where: { $0.id == id }) else { return }
            var p = PadPlaced(dx: engine.layout.extras[i].dx, dy: engine.layout.extras[i].dy,
                              scale: engine.layout.extras[i].scale,
                              spacing: engine.layout.extras[i].spacing)
            f(&p)
            engine.layout.extras[i].scale = p.scale
            engine.layout.extras[i].spacing = p.spacing
        } else if var p = engine.layout.clusters[selection] {
            f(&p)
            engine.layout.clusters[selection] = p
        }
        changed()
    }
}

// MARK: - The interactive surface

/// The multi-touch UIView. Fingers are tracked by UITouch identity the way
/// the C++ tracks SDL_FingerID. A touch the pad does not claim falls through
/// to the emulated ST mouse (drag = relative motion, tap = left click) --
/// the overlay covers the whole picture, so the mouse handling that used to
/// live on the MTKView has to happen here or it happens nowhere.
final class TouchPadUIView: UIView {
    let engine: TouchPadEngine
    var onTouchesSettled: () -> Void = {}
    var mouseMotion: (Int32, Int32) -> Void = { _, _ in }
    var mouseClick: () -> Void = {}

    /// The touch currently driving the mouse, if any.
    private var mouseTouch: ObjectIdentifier?
    private var lastMouseLocation = CGPoint.zero
    private var mouseDownLocation = CGPoint.zero
    private var mouseDownTime: TimeInterval = 0

    init(engine: TouchPadEngine) {
        self.engine = engine
        super.init(frame: .zero)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
        isOpaque = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    /// The pad's play area: the view inset by the safe area, so the on-screen
    /// pad never sits under the cutout or the home indicator (the lesson the
    /// old app learned about the Dynamic Island eating the UI).
    private var padArea: CGRect {
        bounds.inset(by: safeAreaInsets)
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        engine.draw(in: ctx, area: padArea)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        var claimed = false
        for touch in touches {
            let p = touch.location(in: self)
            if engine.handle(.down, id: ObjectIdentifier(touch), at: p, area: padArea) {
                claimed = true
            } else if mouseTouch == nil {
                mouseTouch = ObjectIdentifier(touch)
                lastMouseLocation = p
                mouseDownLocation = p
                mouseDownTime = touch.timestamp
            }
        }
        finish(claimed)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        var claimed = false
        for touch in touches {
            let id = ObjectIdentifier(touch)
            let p = touch.location(in: self)
            if engine.handle(.moved, id: id, at: p, area: padArea) {
                claimed = true
            } else if id == mouseTouch {
                let scale = motionScale()
                let dx = Int32((p.x - lastMouseLocation.x) * scale.width)
                let dy = Int32((p.y - lastMouseLocation.y) * scale.height)
                if dx != 0 || dy != 0 { mouseMotion(dx, dy) }
                lastMouseLocation = p
            }
        }
        finish(claimed)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        endTouches(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        endTouches(touches)
    }

    private func endTouches(_ touches: Set<UITouch>) {
        var claimed = false
        for touch in touches {
            let id = ObjectIdentifier(touch)
            let p = touch.location(in: self)
            if engine.handle(.up, id: id, at: p, area: padArea) {
                claimed = true
            }
            if id == mouseTouch {
                // A short, nearly stationary touch is a click.
                let moved = hypot(p.x - mouseDownLocation.x, p.y - mouseDownLocation.y)
                if moved < 12 && touch.timestamp - mouseDownTime < 0.4 {
                    mouseClick()
                }
                mouseTouch = nil
            }
        }
        finish(claimed)
    }

    private func finish(_ claimed: Bool) {
        _ = claimed // the return value matters to hosts that share the event
                    // stream; here the pad owns every touch on the picture
        setNeedsDisplay()
        onTouchesSettled()
    }

    /// Scale from view points to ST pixels so a finger drag of N points moves
    /// the pointer by the distance it *looks* like on the emulated screen.
    private func motionScale() -> CGSize {
        var width: Int32 = 0
        var height: Int32 = 0
        var pitch: Int32 = 0
        guard atarist_core_get_framebuffer(&width, &height, &pitch) != nil,
              width > 0, height > 0 else { return CGSize(width: 1, height: 1) }
        return CGSize(width: CGFloat(width) / max(bounds.width, 1),
                      height: CGFloat(height) / max(bounds.height, 1))
    }
}

// MARK: - SwiftUI wrapper

struct TouchPadOverlayView: UIViewRepresentable {
    @ObservedObject var pad: TouchPadController
    var core: AtariCore

    func makeUIView(context: Context) -> TouchPadUIView {
        let view = TouchPadUIView(engine: pad.engine)
        view.onTouchesSettled = { [weak pad] in pad?.touchesSettled() }
        view.mouseMotion = { [weak core] dx, dy in core?.mouseMotion(dx: dx, dy: dy) }
        view.mouseClick = { [weak core] in
            // Make AND break are both delivered because games poll the IKBD,
            // not an event queue.
            core?.mouseButton(0, pressed: true)
            core?.mouseButton(0, pressed: false)
        }
        return view
    }

    func updateUIView(_ uiView: TouchPadUIView, context: Context) {
        uiView.setNeedsDisplay()
    }

    static func dismantleUIView(_ uiView: TouchPadUIView, coordinator: ()) {
        uiView.engine.releaseAll()
    }
}
