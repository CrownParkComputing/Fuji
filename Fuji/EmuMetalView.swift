//
//  EmuMetalView.swift
//
//  Presents the core's framebuffer through Metal. The core owns the pixels
//  and bumps a frame counter once per completed frame; this view polls that
//  counter on a 50 Hz display link (the ST is a PAL machine) and uploads only
//  when the counter moved -- a GEM desktop sitting idle is byte-identical for
//  minutes at a time, and re-uploading it would be pure battery drain.
//

import MetalKit
import QuartzCore
import SwiftUI
import UIKit

struct EmuMetalView: UIViewRepresentable {
    @ObservedObject var core: AtariCore

    func makeCoordinator() -> Coordinator {
        Coordinator(core: core)
    }

    func makeUIView(context: Context) -> EmuMTKView {
        let view = EmuMTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.coordinator = context.coordinator
        context.coordinator.attach(to: view)
        return view
    }

    func updateUIView(_ uiView: EmuMTKView, context: Context) {
        context.coordinator.core = core
    }

    static func dismantleUIView(_ uiView: EmuMTKView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator: NSObject, MTKViewDelegate {
        var core: AtariCore

        private weak var view: EmuMTKView?
        private var commandQueue: MTLCommandQueue?
        private var pipeline: MTLRenderPipelineState?
        private var texture: MTLTexture?
        private var uploadedFrame: Int64 = -1
        private var displayLink: CADisplayLink?

        init(core: AtariCore) {
            self.core = core
        }

        func attach(to view: EmuMTKView) {
            self.view = view
            guard let device = view.device else { return }
            commandQueue = device.makeCommandQueue()
            view.delegate = self
            view.colorPixelFormat = .bgra8Unorm
            // Driven manually by the display link below, so nothing draws
            // unless a new frame actually arrived from the core.
            view.isPaused = true
            view.enableSetNeedsDisplay = false

            // The shader is compiled from bundled source at runtime rather
            // than from a precompiled .metallib: CMake's Xcode generator does
            // not know the .metal file type, and a shader that silently never
            // compiles reads as "black screen", the hardest emulator bug to
            // diagnose. The source is 30 lines; runtime compile is instant.
            guard let shaderURL = Bundle.main.url(forResource: "EmuShaders", withExtension: "metal"),
                  let shaderSource = try? String(contentsOf: shaderURL, encoding: .utf8),
                  let library = try? device.makeLibrary(source: shaderSource, options: nil),
               let vertex = library.makeFunction(name: "emuVertex"),
               let fragment = library.makeFunction(name: "emuFragment") else {
                print("Fuji: Metal shader failed to compile -- the screen will stay black")
                return
            }
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertex
            descriptor.fragmentFunction = fragment
            descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
            pipeline = try? device.makeRenderPipelineState(descriptor: descriptor)

            // 50 Hz preferred: a PAL ST frame is 20 ms, and sampling at 60 Hz
            // both uploads duplicate frames and judders scrolling demos.
            let link = CADisplayLink(target: self, selector: #selector(tick))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 40, maximum: 60, preferred: 50)
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        func detach() {
            displayLink?.invalidate()
            displayLink = nil
        }

        @objc private func tick() {
            guard let view else { return }
            let generation = atarist_core_frame_counter()
            guard generation != uploadedFrame else { return }
            if uploadFrame() {
                uploadedFrame = generation
            }
            // draw() with isPaused=true runs the delegate once, on demand.
            view.draw()
        }

        /// Copies the core's current frame into a texture. Returns false when
        /// there is nothing sane to upload yet (core still in TOS startup).
        private func uploadFrame() -> Bool {
            guard let device = view?.device else { return false }
            var width: Int32 = 0
            var height: Int32 = 0
            var pitch: Int32 = 0
            guard let pixels = atarist_core_get_framebuffer(&width, &height, &pitch),
                  width > 0, height > 0, pitch >= width * 4 else { return false }

            if texture == nil || texture?.width != Int(width) || texture?.height != Int(height) {
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                    // RGBA8, matching what the native C++ frontend uploads:
                    // the bridge's 32-bit pixels are handed to Metal verbatim,
                    // with no swizzle.
                    pixelFormat: .rgba8Unorm,
                    width: Int(width),
                    height: Int(height),
                    mipmapped: false)
                descriptor.usage = .shaderRead
                descriptor.storageMode = .shared
                texture = device.makeTexture(descriptor: descriptor)
            }
            guard let texture else { return false }

            // pitch is BYTES, not pixels: Hatari's surface is padded, and
            // treating pitch as a pixel count is what produces the classic
            // diagonally-sheared emulator screenshot. Handing the stride to
            // replaceRegion directly also saves the repacking copy the old
            // frontend used to do.
            texture.replace(region: MTLRegionMake2D(0, 0, Int(width), Int(height)),
                            mipmapLevel: 0,
                            withBytes: pixels,
                            bytesPerRow: Int(pitch))
            return true
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            guard let texture,
                  let pipeline,
                  let commandQueue,
                  let pass = view.currentRenderPassDescriptor,
                  let drawable = view.currentDrawable,
                  let buffer = commandQueue.makeCommandBuffer(),
                  let encoder = buffer.makeRenderCommandEncoder(descriptor: pass)
            else { return }

            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)

            // Aspect-correct fit. atarist_core_pixel_aspect is the DISPLAY
            // aspect of the current mode, not width/height: ST low resolution
            // is 320x200 pixels on a 4:3 monitor, so squaring the pixels would
            // squash the picture. 4/3 is the fallback the old frontend used.
            let aspect = atarist_core_pixel_aspect()
            let contentAspect = Float(aspect > 0 ? aspect : 4.0 / 3.0)
            let viewAspect = Float(view.drawableSize.width / max(view.drawableSize.height, 1))
            var halfSize = SIMD2<Float>(1, 1)
            if viewAspect > contentAspect {
                halfSize.x = contentAspect / viewAspect
            } else {
                halfSize.y = viewAspect / contentAspect
            }
            var params = EmuDrawParams(center: SIMD2<Float>(0, 0), halfSize: halfSize)

            encoder.setRenderPipelineState(pipeline)
            encoder.setVertexBytes(&params, length: MemoryLayout<EmuDrawParams>.stride, index: 0)
            encoder.setFragmentTexture(texture, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            encoder.endEncoding()
            buffer.present(drawable)
            buffer.commit()
        }
    }
}

/// Matches `EmuDrawParams` in EmuShaders.metal.
struct EmuDrawParams {
    var center: SIMD2<Float>
    var halfSize: SIMD2<Float>
}

/// MTKView subclass so touches can drive the emulated mouse directly on the
/// picture: drag moves the mouse relative (in ST pixels), a tap clicks the
/// left button. Joystick control lives in ControlsOverlay's d-pad instead --
/// mixing both onto the same surface made accidental joystick wiggles while
/// mousing inevitable.
final class EmuMTKView: MTKView {
    weak var coordinator: EmuMetalView.Coordinator?
    private var lastTouchLocation: CGPoint?
    private var touchStartLocation: CGPoint?
    private var touchStartTime: TimeInterval = 0

    override init(frame frameRect: CGRect, device: MTLDevice?) {
        super.init(frame: frameRect, device: device)
        isMultipleTouchEnabled = false
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
    }

    /// Scale from view points to ST pixels so a finger drag of N points moves
    /// the pointer by the distance it *looks* like on the emulated screen.
    private func motionScale() -> CGSize {
        guard let texture = coordinatorTextureSize() else {
            return CGSize(width: 1, height: 1)
        }
        return CGSize(width: texture.width / max(bounds.width, 1),
                      height: texture.height / max(bounds.height, 1))
    }

    private func coordinatorTextureSize() -> CGSize? {
        var width: Int32 = 0
        var height: Int32 = 0
        var pitch: Int32 = 0
        guard atarist_core_get_framebuffer(&width, &height, &pitch) != nil,
              width > 0, height > 0 else { return nil }
        return CGSize(width: CGFloat(width), height: CGFloat(height))
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        lastTouchLocation = location
        touchStartLocation = location
        touchStartTime = touch.timestamp
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first,
              let last = lastTouchLocation else { return }
        let location = touch.location(in: self)
        let scale = motionScale()
        let dx = Int32((location.x - last.x) * scale.width)
        let dy = Int32((location.y - last.y) * scale.height)
        if dx != 0 || dy != 0 {
            coordinator?.core.mouseMotion(dx: dx, dy: dy)
        }
        lastTouchLocation = location
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        defer {
            lastTouchLocation = nil
            touchStartLocation = nil
        }
        guard let touch = touches.first,
              let start = touchStartLocation else { return }
        let location = touch.location(in: self)
        let moved = hypot(location.x - start.x, location.y - start.y)
        let held = touch.timestamp - touchStartTime
        // A short, nearly stationary touch is a click; make AND break are both
        // delivered because games poll the IKBD, not an event queue.
        if moved < 12, held < 0.4 {
            coordinator?.core.mouseButton(0, pressed: true)
            coordinator?.core.mouseButton(0, pressed: false)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        lastTouchLocation = nil
        touchStartLocation = nil
    }
}
