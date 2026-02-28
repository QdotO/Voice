import UIKit

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
        freq *= 2.07  // slightly inharmonic — prevents diagonal grid artifacts
    }
    return v
}

private func warpedNoise(_ x: Float, _ y: Float, t: Float, warpStr: Float) -> Float {
    let wx = fbm(x + t * 0.18, y, octaves: 2) * 2 - 1
    let wy = fbm(x + 3.7, y + t * 0.18, octaves: 2) * 2 - 1
    // Subtracting t from Y → heat-rising illusion
    return fbm(x + wx * warpStr, y + wy * warpStr - t, octaves: 3)
}

@inline(__always)
private func lerpF(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }

// MARK: - Fire Palette

private func buildFirePalette() -> [UIColor] {
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
        return UIColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: 1)
    }
}

// MARK: - ASCIICanvasView

/// A full-screen UIView that renders either a fire or noise ASCII animation,
/// voice-reactive via the `amplitude` property (0.0 – 1.0).
final class ASCIICanvasView: UIView {

    // MARK: Public

    /// Current voice amplitude (0–1). Updated from outside each display frame.
    var amplitude: Float = 0

    var mode: AnimationMode = .fire {
        didSet {
            guard oldValue != mode else { return }
            resetFireGrid()
        }
    }

    // MARK: Private — display link

    private var displayLink: CADisplayLink?
    private var startTime: CFTimeInterval = 0
    private var lastTimestamp: CFTimeInterval = 0

    // MARK: Private — typography

    private let fontSize: CGFloat = 11
    private var cellW: CGFloat = 0
    private var cellH: CGFloat = 0
    private var monoFont: UIFont!

    // Pre-built attribute dictionaries — never allocated inside the draw loop
    private var noiseAttrs: [[NSAttributedString.Key: Any]] = []  // [dim, mid, bright]
    private var fireAttrs: [[NSAttributedString.Key: Any]] = []  // 256 entries

    // MARK: Private — noise params (lerp targets driven by amplitude)

    private let noiseChars: [Character] = Array("    ..,,::;/\\|/\\:-/\\+=*/\\#QUINCY")
    private var noiseFreq: Float = 0.38
    private var noiseSpeed: Float = 0.32
    private var noiseWarp: Float = 1.4

    // MARK: Private — fire params

    private let fireChars: [Character] = Array("  .,'`^~+|*#%@W")
    private let firePalette: [UIColor] = buildFirePalette()
    private var fireGrid: [UInt8] = []
    private var fireCols: Int = 0
    private var fireRows: Int = 0
    private var fireCooling: Float = 2.0
    private var fireIgnition: Float = 0.9
    private let fireWind: Int = 1
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
        backgroundColor = .clear
        isOpaque = false
        contentMode = .redraw
        isUserInteractionEnabled = false

        monoFont = UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let advance = "X".size(withAttributes: [.font: monoFont!])
        cellW = advance.width
        cellH = advance.height

        // Three alpha levels for noise mode
        noiseAttrs = [
            [.font: monoFont!, .foregroundColor: UIColor.white.withAlphaComponent(0.28)],
            [.font: monoFont!, .foregroundColor: UIColor.white.withAlphaComponent(0.62)],
            [.font: monoFont!, .foregroundColor: UIColor.white],
        ]

        // One attr dict per palette entry for fire mode
        fireAttrs = firePalette.map { c in [.font: monoFont!, .foregroundColor: c] }
    }

    // MARK: Display Link Lifecycle

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, displayLink == nil else { return }
        startTime = CACurrentMediaTime()
        lastTimestamp = startTime
        displayLink = CADisplayLink(target: self, selector: #selector(tick))
        displayLink?.preferredFrameRateRange = .init(minimum: 30, maximum: 30, preferred: 30)
        displayLink?.add(to: .main, forMode: .common)
    }

    override func removeFromSuperview() {
        displayLink?.invalidate()
        displayLink = nil
        super.removeFromSuperview()
    }

    @objc private func tick(_ link: CADisplayLink) {
        let dt = Float(link.timestamp - lastTimestamp)
        lastTimestamp = link.timestamp
        smoothParams(dt: dt)
        setNeedsDisplay()
    }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        resetFireGrid()
    }

    private func resetFireGrid() {
        guard cellW > 0, cellH > 0, bounds.width > 0, bounds.height > 0 else { return }
        fireCols = Int(ceil(bounds.width / cellW))
        fireRows = Int(ceil(bounds.height / cellH))
        fireGrid = [UInt8](repeating: 0, count: fireCols * fireRows)
        // Seed bottom two rows
        for c in 0..<fireCols {
            fireGrid[(fireRows - 1) * fireCols + c] = 255
            if fireRows >= 2 {
                fireGrid[(fireRows - 2) * fireCols + c] = 255
            }
        }
    }

    // MARK: Parameter Smoothing (voice reactivity)

    private func smoothParams(dt: Float) {
        let amp = amplitude
        let rate: Float = dt * 3.0
        switch mode {
        case .fire:
            let tCooling = lerpF(2.0, 0.2, amp)  // loud → cooler=0.2 → taller flames
            let tIgnition = 0.6 + amp * 0.4
            fireCooling = lerpF(fireCooling, tCooling, rate)
            fireIgnition = lerpF(fireIgnition, tIgnition, rate)
        case .noise:
            let tSpeed = 0.32 + amp * 1.5
            let tWarp = 1.4 + amp * 2.0
            noiseSpeed = lerpF(noiseSpeed, tSpeed, rate)
            noiseWarp = lerpF(noiseWarp, tWarp, rate)
        }
    }

    // MARK: Drawing

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.clear(rect)
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

        // Step 1 — Re-seed bottom row
        for c in 0..<cols {
            let idx = (rows - 1) * cols + c
            if Float.random(in: 0..<1) < fireIgnition {
                fireGrid[idx] = UInt8(min(255, 210 + Int.random(in: 0...45)))
            } else {
                fireGrid[idx] = UInt8(max(0, Int(fireGrid[idx]) - 8))
            }
        }

        // Step 2 — Propagate upward
        let maxCooling = max(0, Int(fireCooling))
        for r in 0..<(rows - 1) {
            for c in 0..<cols {
                let decay = maxCooling > 0 ? Int.random(in: 0...maxCooling) : 0
                let wind =
                    fireWind > 0
                    ? Int.random(in: 0...(fireWind * 2)) - fireWind
                    : 0
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

        // Step 3 — Render
        let threshold: UInt8 = 12
        let charCount = fireChars.count
        for r in 0..<rows {
            for c in 0..<cols {
                let heat = fireGrid[r * cols + c]
                guard heat >= threshold else { continue }
                let ci = min(charCount - 1, Int(Float(heat) / 255 * Float(charCount)))
                let ch = fireChars[ci]
                guard ch != " " else { continue }
                String(ch).draw(
                    at: CGPoint(x: CGFloat(c) * cellW, y: CGFloat(r) * cellH),
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
                String(ch).draw(
                    at: CGPoint(x: CGFloat(col) * cellW, y: CGFloat(row) * cellH),
                    withAttributes: noiseAttrs[ai]
                )
            }
        }
    }
}
