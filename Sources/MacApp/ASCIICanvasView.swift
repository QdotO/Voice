import AppKit

// MARK: - Animation Mode

enum AnimationMode: Equatable {
    case fire
    case noise
}

// MARK: - Math Helpers

@inline(__always)
private func ihash(_ px: Int32, _ py: Int32) -> Float {
    var h = (UInt32(bitPattern: px) &* 1_836_311_903) ^ (UInt32(bitPattern: py) &* 2_971_215_073)
    h = h ^ (h >> 16)
    h = h &* 0x45d9f3b
    h = h ^ (h >> 16)
    h = h &* 0x45d9f3b
    return Float(h) / 4_294_967_296.0
}

private func valueNoise2D(_ x: Float, _ y: Float) -> Float {
    let ix = Int32(floor(x))
    let iy = Int32(floor(y))
    let fx = x - Float(ix)
    let fy = y - Float(iy)
    let ux = fx * fx * (3 - 2 * fx)
    let uy = fy * fy * (3 - 2 * fy)
    let a = ihash(ix, iy)
    let b = ihash(ix + 1, iy)
    let c = ihash(ix, iy + 1)
    let d = ihash(ix + 1, iy + 1)
    return a + (b - a) * ux + (c - a) * uy + (d - b - c + a) * ux * uy
}

private func fbm(_ x: Float, _ y: Float, octaves: Int) -> Float {
    var v: Float = 0
    var amp: Float = 0.5
    var freq: Float = 1
    for _ in 0..<octaves {
        v += valueNoise2D(x * freq, y * freq) * amp
        amp *= 0.5
        freq *= 2.07
    }
    return v
}

private func warpedNoise(_ x: Float, _ y: Float, t: Float, warpStr: Float) -> Float {
    let wx = fbm(x + t * 0.18, y, octaves: 2) * 2 - 1
    let wy = fbm(x + 3.7, y + t * 0.18, octaves: 2) * 2 - 1
    return fbm(x + wx * warpStr, y + wy * warpStr - t, octaves: 3)
}

@inline(__always)
private func lerpF(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }

// MARK: - Fire Palette

private func buildFirePalette() -> [NSColor] {
    (0..<256).map { i in
        let t = Float(i) / 255.0
        let r: Float
        let g: Float
        let b: Float
        if t < 0.25 {
            let u = t / 0.25
            r = u * 180 / 255
            g = 0
            b = 0
        } else if t < 0.5 {
            let u = (t - 0.25) / 0.25
            r = (180 + u * 75) / 255
            g = (u * 110) / 255
            b = 0
        } else if t < 0.75 {
            let u = (t - 0.5) / 0.25
            r = 1.0
            g = (110 + u * 120) / 255
            b = 0
        } else {
            let u = (t - 0.75) / 0.25
            r = 1.0
            g = (230 + u * 25) / 255
            b = (u * 255) / 255
        }
        return NSColor(calibratedRed: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: 1)
    }
}

// MARK: - ASCIICanvasView

/// Full-screen NSView that renders either a fire or noise ASCII animation,
/// voice-reactive via the `amplitude` property (0.0 – 1.0).
final class ASCIICanvasView: NSView {

    // MARK: Public

    var amplitude: Float = 0

    var mode: AnimationMode = .fire {
        didSet {
            guard oldValue != mode else { return }
            resetFireGrid()
        }
    }

    // MARK: Private — render timer (30 fps)

    private var renderTimer: Timer?
    private var startTime: CFTimeInterval = 0
    private var lastRenderTime: CFTimeInterval = 0

    // MARK: Private — typography

    private let fontSize: CGFloat = 7
    private var cellW: CGFloat = 0
    private var cellH: CGFloat = 0
    private var monoFont: NSFont!

    // Pre-built attribute dicts — never allocated in the draw loop
    private var noiseAttrs: [[NSAttributedString.Key: Any]] = []  // [dim, mid, bright]
    private var fireAttrs: [[NSAttributedString.Key: Any]] = []  // 256 entries

    // MARK: Private — noise params

    private let noiseChars: [Character] = Array("    ..,,::;/\\|/\\:-/\\+=*/\\#QUINCY")
    private var noiseFreq: Float = 0.38
    private var noiseSpeed: Float = 0.32
    private var noiseWarp: Float = 1.4

    // MARK: Private — fire params

    /// Virtual grid height in rows. Much taller than the window so the flame
    /// has room to develop structure; only the top rows (tips) are rendered.
    private let fireVirtualRows = 18

    private let fireChars: [Character] = Array("  .,'`^~+|*#%@W")
    private let firePalette: [NSColor] = buildFirePalette()
    private var fireGrid: [UInt8] = []
    private var fireCols: Int = 0
    private var fireRows: Int = 0
    private var fireCooling: Float = 20.0
    private var fireIgnition: Float = 0.13
    var fireWind: Int = 1
    private let fireWarpStr: Float = 0.5

    // MARK: Init

    init(mode: AnimationMode = .fire) {
        self.mode = mode
        super.init(frame: .zero)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        layer?.backgroundColor = .clear

        monoFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let advance = ("X" as NSString).size(withAttributes: [.font: monoFont!])
        cellW = advance.width
        cellH = advance.height

        noiseAttrs = [
            [.font: monoFont!, .foregroundColor: NSColor.white.withAlphaComponent(0.28)],
            [.font: monoFont!, .foregroundColor: NSColor.white.withAlphaComponent(0.62)],
            [.font: monoFont!, .foregroundColor: NSColor.white],
        ]
        fireAttrs = firePalette.map { c in [.font: monoFont!, .foregroundColor: c] }
    }

    // MARK: Render Timer Lifecycle

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, renderTimer == nil else { return }
        startTime = CACurrentMediaTime()
        lastRenderTime = startTime
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let now = CACurrentMediaTime()
            let dt = Float(now - self.lastRenderTime)
            self.lastRenderTime = now
            self.smoothParams(dt: dt)
            self.needsDisplay = true
        }
        RunLoop.main.add(t, forMode: .common)
        renderTimer = t
    }

    override func removeFromSuperview() {
        renderTimer?.invalidate()
        renderTimer = nil
        super.removeFromSuperview()
    }

    // MARK: Layout

    override func layout() {
        super.layout()
        resetFireGrid()
    }

    private func resetFireGrid() {
        guard cellW > 0, cellH > 0, bounds.width > 0, bounds.height > 0 else { return }
        fireCols = Int(ceil(bounds.width / cellW))
        // Virtual height: tall enough for flame structure to develop above the base.
        // The window only shows the top `visibleRows` rows (the tips).
        let visibleRows = Int(ceil(bounds.height / cellH))
        fireRows = max(visibleRows, fireVirtualRows)
        fireGrid = [UInt8](repeating: 0, count: fireCols * fireRows)
        for c in 0..<fireCols {
            fireGrid[(fireRows - 1) * fireCols + c] = 255
            if fireRows >= 2 {
                fireGrid[(fireRows - 2) * fireCols + c] = 255
            }
        }
    }

    // MARK: Parameter Smoothing

    private func smoothParams(dt: Float) {
        // AudioCapture already applies exponential smoothing (0.8/0.2).
        // Apply a power curve here so mid-level speech (~0.6 raw) feels loud.
        let boosted = min(1.0, pow(amplitude, 0.55) * 1.3)
        switch mode {
        case .fire:
            // Slightly lower cooling so yellow survives at the base; gaps remain at top.
            fireCooling = 32.0
            // Steeper power curve so mid-level speech feels noticeably louder.
            let voiced = min(1.0, pow(boosted, 0.7) * 1.2)
            fireIgnition = lerpF(0.02, 0.80, voiced)
        case .noise:
            let tSpeed = 0.32 + boosted * 1.5
            let tWarp = 1.4 + boosted * 2.0
            let rate = dt * 8.0  // faster snap for noise mode
            noiseSpeed = lerpF(noiseSpeed, tSpeed, rate)
            noiseWarp = lerpF(noiseWarp, tWarp, rate)
        }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(bounds)
        let t = Float(CACurrentMediaTime() - startTime)
        switch mode {
        case .fire: drawFire(t: t)
        case .noise: drawNoise(t: t)
        }
    }

    // MARK: Fire Renderer

    private func drawFire(t: Float) {
        let cols = fireCols
        let rows = fireRows
        guard cols > 0, rows > 0 else { return }

        // Step 1 — Re-seed bottom row; seed temperature scales with voice level
        let boosted = min(1.0, pow(amplitude, 0.55) * 1.3)
        let baseHeat = Int(200 + boosted * 55)  // 200 quiet → 255 loud
        for c in 0..<cols {
            let idx = (rows - 1) * cols + c
            if Float.random(in: 0..<1) < fireIgnition {
                fireGrid[idx] = UInt8(min(255, baseHeat + Int.random(in: 0...10)))
            } else {
                fireGrid[idx] = UInt8(max(0, Int(fireGrid[idx]) - 8))
            }
        }

        // Step 2 — Propagate upward
        let maxCooling = max(0, Int(fireCooling))
        for r in 0..<(rows - 1) {
            for c in 0..<cols {
                let decay = maxCooling > 0 ? Int.random(in: 0...maxCooling) : 0
                let wind = fireWind > 0 ? Int.random(in: 0...(fireWind * 2)) - fireWind : 0
                let warp =
                    fireWarpStr > 0
                    ? Int(
                        (valueNoise2D(
                            Float(c) * 0.07 + t * 0.25,
                            Float(r) * 0.07) * 2 - 1)
                            * fireWarpStr + 0.5)
                    : 0
                let srcCol = min(max(c + wind + warp, 0), cols - 1)
                let heat = Int(fireGrid[(r + 1) * cols + srcCol])
                fireGrid[r * cols + c] = UInt8(max(0, heat - decay))
            }
        }

        // Step 3 — Render only the top (visible) rows — the flame tips.
        // The hot base rows near fireRows-1 are simulated but off-screen.
        let visibleRows = Int(ceil(bounds.height / cellH))
        let threshold: UInt8 = 12
        let charCount = fireChars.count
        for r in 0..<visibleRows {
            for c in 0..<cols {
                let heat = fireGrid[r * cols + c]
                guard heat >= threshold else { continue }
                let ci = min(charCount - 1, Int(Float(heat) / 255 * Float(charCount)))
                let ch = fireChars[ci]
                guard ch != " " else { continue }
                (String(ch) as NSString).draw(
                    at: CGPoint(x: CGFloat(c) * cellW, y: CGFloat(visibleRows - 1 - r) * cellH),
                    withAttributes: fireAttrs[Int(heat)]
                )
            }
        }
    }

    // MARK: Noise Renderer

    private func drawNoise(t: Float) {
        let cols = Int(ceil(bounds.width / cellW))
        let rows = Int(ceil(bounds.height / cellH))
        let charCount = noiseChars.count
        let idxDimMax = Int(Float(charCount) * 0.28)
        let idxMidMax = Int(Float(charCount) * 0.62)
        let scaledT = t * noiseSpeed

        for row in 0..<rows {
            for col in 0..<cols {
                let nx = Float(col) * (noiseFreq * Float(cellW) / Float(bounds.width)) * 14
                let ny = Float(row) * (noiseFreq * Float(cellH) / Float(bounds.height)) * 14
                let density = warpedNoise(nx, ny, t: scaledT, warpStr: noiseWarp)
                let clamped = max(0, min(0.9999, density))
                let ci = Int(clamped * Float(charCount))
                let ch = noiseChars[ci]
                guard ch != " " else { continue }
                let ai = ci < idxDimMax ? 0 : ci < idxMidMax ? 1 : 2
                // NSView's coordinate origin is bottom-left; flip row for top-down rendering
                (String(ch) as NSString).draw(
                    at: CGPoint(x: CGFloat(col) * cellW, y: CGFloat(rows - 1 - row) * cellH),
                    withAttributes: noiseAttrs[ai]
                )
            }
        }
    }
}
