# ASCII Animation — Swift Port Guide
## Voice-Reactive Dictation Session Background

This document is a complete technical specification for porting the two ASCII canvas
animations built for the web app into a Swift (UIKit/SwiftUI) iOS/macOS project, with
a voice-reactivity layer added for use during dictation sessions.

---

## 1. Animations at a Glance

| Mode | Algorithm | Best for voice |
|------|-----------|----------------|
| **Noise** | Domain-warped fractional Brownian motion (fBm) mapped to characters | Ambient energy; quiet sessions look calm, loud speech swirls |
| **Fire** | Doom-fire cellular automaton | Most dramatic; amplitude visibly feeds the flames |

Both render a full-screen grid of monospace characters on a `Canvas` / `CGContext`,
updated at 30 fps via `CADisplayLink`.

---

## 2. Shared Concepts

### 2.1 Cell Grid

Divide the screen into a grid of equal cells:

```swift
let fontSize: CGFloat = 12          // pt
let cellW: CGFloat    = fontSize * 0.6   // ≈ 7.2 pt  (monospace advance)
let cellH: CGFloat    = fontSize         // line height
```

Calculate on every resize:
```swift
let cols = Int(ceil(viewWidth  / cellW))
let rows = Int(ceil(viewHeight / cellH))
```

Drawing one character `char` at logical cell `(col, row)`:
```swift
char.draw(at: CGPoint(x: CGFloat(col) * cellW, y: CGFloat(row) * cellH),
          withAttributes: attrs)
```

### 2.2 Integer Hash (no trigonometry)

Used everywhere as a fast, deterministic pseudo-random function.

**Web original (JavaScript):**
```js
const ihash = (px, py) => {
  let h = (Math.imul(px|0, 1836311903) ^ Math.imul(py|0, 2971215073)) | 0
  h = Math.imul(h ^ (h >>> 16), 0x45d9f3b) | 0
  h = Math.imul(h ^ (h >>> 16), 0x45d9f3b) | 0
  return (h >>> 0) / 4294967296
}
```

**Swift equivalent (returns 0.0 … 1.0):**
```swift
@inline(__always)
func ihash(_ px: Int32, _ py: Int32) -> Float {
    var h = Int32(bitPattern: UInt32(bitPattern: Int32(bitPattern: UInt32(bitPattern: px) &* 1836311903))
                              ^ UInt32(bitPattern: Int32(bitPattern: UInt32(bitPattern: py) &* 2971215073)))
    h ^= h >> 16
    h = Int32(bitPattern: UInt32(bitPattern: h) &* 0x45d9f3b)
    h ^= h >> 16
    h = Int32(bitPattern: UInt32(bitPattern: h) &* 0x45d9f3b)
    return Float(UInt32(bitPattern: h)) / 4_294_967_296.0
}
```

### 2.3 Bilinear Value Noise

Smoothly interpolates four corner hashes:

```swift
func valueNoise2D(_ x: Float, _ y: Float) -> Float {
    let ix = Int32(floor(x)), iy = Int32(floor(y))
    let fx = x - Float(ix),   fy = y - Float(iy)
    // Smoothstep
    let ux = fx * fx * (3 - 2 * fx)
    let uy = fy * fy * (3 - 2 * fy)
    let a = ihash(ix,     iy)
    let b = ihash(ix + 1, iy)
    let c = ihash(ix,     iy + 1)
    let d = ihash(ix + 1, iy + 1)
    return a + (b - a) * ux + (c - a) * uy + (d - b - c + a) * ux * uy
}
```

### 2.4 Fractional Brownian Motion (fBm)

Stacks multiple octaves of noise for organic, cloud-like detail:

```swift
func fbm(_ x: Float, _ y: Float, octaves: Int) -> Float {
    var v: Float = 0, amp: Float = 0.5, freq: Float = 1
    for _ in 0..<octaves {
        v    += valueNoise2D(x * freq, y * freq) * amp
        amp  *= 0.5
        freq *= 2.07     // slightly inharmonic — prevents diagonal grid artifacts
    }
    return v
}
```

---

## 3. Mode A — Noise/fBm Animation

### 3.1 Character Set

```swift
let chars = "    ..,,::;/\\|/\\:-/\\+=*/\\#QUINCY"
let charCount = chars.count
```

Reading left → right: sparse/background → dense/foreground.
- Spaces at the start = invisible (background bleeds through)
- `/ \ |` in the mid-density range = the "electrical interference" texture
- Brand letters `QUINCY` at peak density pool into readable clusters

### 3.2 Domain-Warped fBm

This is the heart of the organic, non-repeating quality:

```swift
func warpedNoise(_ x: Float, _ y: Float, t: Float, warpStr: Float) -> Float {
    // Two cheap warp-vector fields (1 octave each)
    let wx = fbm(x + t * 0.18, y + 0.0,      octaves: 2) * 2 - 1
    let wy = fbm(x + 3.7,      y + t * 0.18, octaves: 2) * 2 - 1
    // Main field sampled at warped position; subtracting t from Y → rises upward
    return fbm(
        x + wx * warpStr,
        y + wy * warpStr - t,   // ← this is why it looks like heat rising
        octaves: 3
    )
}
```

**What each parameter does:**
| Parameter | Default | Effect |
|-----------|---------|--------|
| `frequency` | 0.38 | Lower = large blobs; higher = tight grain |
| `speed` | 0.32 | Multiplier on time `t` |
| `warpStrength` | 1.4 | 0 = plain fBm; 2+ = heavy swirling folds |

### 3.3 Three-Level Alpha Depth

```swift
let idxDimMax  = Int(Float(charCount) * 0.28)  // sparse chars → 28% alpha
let idxMidMax  = Int(Float(charCount) * 0.62)  // mid chars    → 62% alpha
// peak chars → 100% alpha
```

In your drawing loop:
```swift
if charIdx < idxDimMax {
    attrs[.foregroundColor] = UIColor.white.withAlphaComponent(0.28)
} else if charIdx < idxMidMax {
    attrs[.foregroundColor] = UIColor.white.withAlphaComponent(0.62)
} else {
    attrs[.foregroundColor] = UIColor.white
}
```

### 3.4 Full Render Loop (Swift pseudocode)

```swift
// Called by CADisplayLink at 30fps
func drawNoiseFrame(in ctx: CGContext, timestamp: CFTimeInterval) {
    let t    = Float(timestamp - startTime) * Float(speed)
    let cols = Int(ceil(viewWidth  / cellW))
    let rows = Int(ceil(viewHeight / cellH))

    ctx.clear(CGRect(origin: .zero, size: viewSize))

    for row in 0..<rows {
        for col in 0..<cols {
            // Map cell coordinates into noise space
            let nx = Float(col) * (frequency * Float(cellW) / Float(viewWidth))  * 14
            let ny = Float(row) * (frequency * Float(cellH) / Float(viewHeight)) * 14

            let density = warpedNoise(nx, ny, t: t, warpStr: warpStrength)
            let clamped = max(0, min(0.9999, density))
            let charIdx = Int(clamped * Float(charCount))
            let char    = chars[charIdx]   // index into the string

            if char == " " { continue }

            let alpha: CGFloat = charIdx < idxDimMax ? 0.28
                               : charIdx < idxMidMax ? 0.62
                               : 1.0

            String(char).draw(
                at: CGPoint(x: CGFloat(col) * cellW, y: CGFloat(row) * cellH),
                withAttributes: [
                    .font: monoFont,
                    .foregroundColor: UIColor.white.withAlphaComponent(alpha)
                ]
            )
        }
    }
}
```

---

## 4. Mode B — Doom-Fire Cellular Automaton

### 4.1 Character Set

```swift
let fireChars = "  .,'`^~+|*#%@W"
```

Sparse (space) = cool/black → dense (`W`) = white-hot.

### 4.2 256-Color Fire Palette

Pre-compute once at startup. The palette runs:
**black → deep crimson → orange → amber yellow → white hot**

```swift
func buildFirePalette() -> [UIColor] {
    (0..<256).map { i in
        let t = Float(i) / 255.0
        let r, g, b: Float
        if t < 0.25 {
            r = (t / 0.25) * 180 / 255; g = 0; b = 0
        } else if t < 0.5 {
            let u = (t - 0.25) / 0.25
            r = (180 + u * 75) / 255; g = (u * 110) / 255; b = 0
        } else if t < 0.75 {
            let u = (t - 0.5) / 0.25
            r = 1.0; g = (110 + u * 120) / 255; b = 0
        } else {
            let u = (t - 0.75) / 0.25
            r = 1.0; g = (230 + u * 25) / 255; b = (u * 255) / 255
        }
        return UIColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: 1)
    }
}
```

For **monochrome mode** (grayscale): `UIColor(white: CGFloat(i)/255, alpha: 1)`.

### 4.3 Grid (Cellular Automaton State)

```swift
var grid = [UInt8](repeating: 0, count: cols * rows)

// Seed bottom two rows fully hot on init
for c in 0..<cols {
    grid[(rows - 1) * cols + c] = 255
    grid[(rows - 2) * cols + c] = 255
}
```

### 4.4 Per-Frame Heat Propagation

**Step 1 — Re-seed the bottom row:**
```swift
for c in 0..<cols {
    let idx = (rows - 1) * cols + c
    if Float.random(in: 0..<1) < ignitionRate {
        grid[idx] = UInt8(210 + Int.random(in: 0...45))  // 210–255
    } else {
        grid[idx] = UInt8(max(0, Int(grid[idx]) - 8))    // ember / gap
    }
}
```

**Step 2 — Propagate upward:**
```swift
let t = timestamp - startTime   // seconds elapsed

for r in 0..<(rows - 1) {
    for c in 0..<cols {
        let decay = Int.random(in: 0...Int(cooling))

        // Random micro-wind drift
        let wind = windStrength > 0
            ? Int.random(in: 0...(windStrength * 2)) - windStrength
            : 0

        // Optional domain-warp for organic swirl
        let warpOffset = warpStrength > 0
            ? Int((valueNoise2D(Float(c) * 0.07 + Float(t) * 0.25,
                                Float(r) * 0.07) * 2 - 1) * Float(warpStrength) + 0.5)
            : 0

        let srcRow = r + 1
        let srcCol = min(max(c + wind + warpOffset, 0), cols - 1)
        let heat   = Int(grid[srcRow * cols + srcCol])
        grid[r * cols + c] = UInt8(max(0, heat - decay))
    }
}
```

**Step 3 — Render:**
```swift
let renderThreshold: UInt8 = 12

for r in 0..<rows {
    for c in 0..<cols {
        let heat = grid[r * cols + c]
        guard heat >= renderThreshold else { continue }

        let charIdx = min(fireChars.count - 1, Int(Float(heat) / 255 * Float(fireChars.count)))
        let char    = fireChars[charIdx]
        guard char != " " else { continue }

        let color = palette[Int(heat)]

        String(char).draw(
            at: CGPoint(x: CGFloat(c) * cellW, y: CGFloat(r) * cellH),
            withAttributes: [.font: monoFont, .foregroundColor: color]
        )
    }
}
```

---

## 5. Voice Reactivity Layer

### 5.1 Audio Capture with AVAudioEngine

```swift
import AVFoundation

class VoiceAmplitudeMonitor {
    private let engine = AVAudioEngine()
    // Smoothed RMS, updated ~60 fps from audio thread, read on main thread
    private(set) var smoothedAmplitude: Float = 0   // 0.0 – 1.0
    private let smoothing: Float = 0.85             // higher = slower response

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement,
                                options: [.defaultToSpeaker, .mixWithOthers])
        try session.setActive(true)

        let input  = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            let rms = self.rms(buffer: buffer)
            // Boost quiet signals (dictation doesn't shout)
            let boosted = min(rms * 6.0, 1.0)
            // Exponential smoothing on audio thread — atomic float is fine here
            self.smoothedAmplitude = self.smoothedAmplitude * self.smoothing
                                   + boosted * (1 - self.smoothing)
        }

        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    private func rms(buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<count { sum += data[i] * data[i] }
        return sqrt(sum / Float(count))
    }
}
```

> **Permission needed:** Add `NSMicrophoneUsageDescription` to `Info.plist`.

### 5.2 Mapping Amplitude → Fire Parameters

The fire mode is the most dramatic voice reactor. Map `amplitude` (0–1) like this:

```swift
// Called each render frame before Step 1 (re-seed)
func applyVoiceToFire(amplitude: Float) {
    // Louder voice → hotter, taller flames
    cooling      = 2.0  - amplitude * 1.8   // range: 2.0 (quiet) → 0.2 (loud)
    ignitionRate = 0.6  + amplitude * 0.4   // range: 0.6 → 1.0
    // Optional: widen the ignition band with volume
    ignitionBandWidth = 1 + Int(amplitude * Float(cols / 3))
}
```

**Bonus — syllable pulse:** For a pronounced staccato effect, also briefly spike
`cooling` to a negative value (e.g. `-1`) when amplitude crosses a rising threshold,
then let it decay back. This creates a "breath of fire" burst per syllable.

### 5.3 Mapping Amplitude → Noise Parameters

```swift
func applyVoiceToNoise(amplitude: Float) {
    speed        = 0.32 + amplitude * 1.5   // louder = faster animation
    warpStrength = 1.4  + amplitude * 2.0   // louder = more swirling
    // Optional: frequency can shift slightly for texture change
    // frequency = 0.38 + amplitude * 0.2
}
```

### 5.4 Suggested UX for Dictation Mode

```
State: IDLE      → fire mode, cooling=4, ignitionRate=0.3  (dim embers)
State: LISTENING → fire mode, voice-reactive params above
State: PROCESSING→ noise mode, warpStrength=2.5, speed=0.8 (thinking swirl)
State: DONE      → transition both speed/cooling toward idle over ~1 second
```

Animate parameter transitions with linear interpolation each frame:
```swift
cooling = lerp(cooling, targetCooling, dt * 3.0)   // dt = frame delta seconds
```

---

## 6. Swift Architecture Recommendations

### 6.1 CADisplayLink Render Loop

```swift
class ASCIICanvasView: UIView {
    private var displayLink: CADisplayLink?
    private var startTime: CFTimeInterval = 0

    override func didMoveToWindow() {
        super.didMoveToWindow()
        startTime = CACurrentMediaTime()
        displayLink = CADisplayLink(target: self, selector: #selector(tick))
        displayLink?.preferredFrameRateRange = .init(minimum: 30, maximum: 30, preferred: 30)
        displayLink?.add(to: .main, forMode: .common)
    }

    override func removeFromSuperview() {
        displayLink?.invalidate()
        super.removeFromSuperview()
    }

    @objc private func tick(_ link: CADisplayLink) {
        let t = link.timestamp - startTime
        setNeedsDisplay()   // triggers drawRect
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        ctx.setFillColor(UIColor.black.cgColor)
        ctx.fill(rect)
        // delegate to fire or noise renderer
    }
}
```

### 6.2 SwiftUI Wrapper

```swift
struct ASCIICanvasRepresentable: UIViewRepresentable {
    @Binding var amplitude: Float
    var mode: AnimationMode

    func makeUIView(context: Context) -> ASCIICanvasView {
        ASCIICanvasView(mode: mode)
    }

    func updateUIView(_ uiView: ASCIICanvasView, context: Context) {
        uiView.amplitude = amplitude
        uiView.mode      = mode
    }
}
```

### 6.3 Performance Notes

- **Pre-compute** the `fireChars` character array and fire palette at init — never inside the draw loop.
- **Use a flat `[UInt8]` array** (not 2D) for the fire grid; index math (`r * cols + c`) is fast.
- **Cache `NSAttributedString` attribute dictionaries** — allocating a new `[NSAttributedStringKey: Any]` dict 10,000× per frame is expensive. Pre-build one dict per color (or per alpha level for noise mode) at the start.
- For fire, **batch by color:** collect all cell positions per heat value, set fill color once, then draw all characters of that heat level. Reduces `CTFontSetFillColor` calls from N×M down to ~32 (fire has ~16 effective heat buckets).
- Target **30 fps** for ASCII animations. Text rendering is not cheap; 60 fps will drain battery significantly.
- On **M-chip Macs / modern iPhones** this runs fine single-threaded. On older A-series devices, consider computing the grid on a background thread and double-buffering.

---

## 7. Parameters Quick Reference

### Fire Mode
| Parameter | Type | Default | Voice mapping |
|-----------|------|---------|---------------|
| `cooling` | Float 0–20 | 2.0 | Decrease with amplitude → taller flames |
| `ignitionRate` | Float 0–1 | 0.9 | Increase with amplitude → fewer gaps |
| `windStrength` | Int 0–3 | 1 | Can stay fixed during dictation |
| `warpStrength` | Float 0–3 | 0 | Increase slightly with amplitude for swirl |
| `monochrome` | Bool | false | Toggle for stylistic preference |

### Noise Mode
| Parameter | Type | Default | Voice mapping |
|-----------|------|---------|---------------|
| `frequency` | Float 0.1–0.8 | 0.38 | Slight increase with amplitude |
| `speed` | Float 0.05–1.5 | 0.32 | Increase with amplitude |
| `warpStrength` | Float 0–3 | 1.4 | Increase with amplitude |
| `opacity` | Float 0–1 | 1.0 | Can stay fixed |

---

## 8. Complete Porting Checklist

- [ ] `ihash()` — integer hash, returns 0..1
- [ ] `valueNoise2D()` — bilinear noise, built on `ihash`
- [ ] `fbm()` — 3-octave fBm, built on `valueNoise2D`
- [ ] `warpedNoise()` — domain-warped fBm (used only in Noise mode)
- [ ] Fire palette array (256 `UIColor`s), built once at startup
- [ ] Fire grid (`[UInt8]`, flat array, `cols × rows`)
- [ ] Fire propagation loop (re-seed → propagate → render)
- [ ] Noise render loop (per-cell noise → char → 3-level alpha)
- [ ] `CADisplayLink` at 30 fps
- [ ] `AVAudioEngine` tap → RMS → `smoothedAmplitude`
- [ ] Amplitude → parameter mapping (fire or noise)
- [ ] Parameter lerp/smoothing so changes feel fluid
- [ ] `NSMicrophoneUsageDescription` in `Info.plist`
- [ ] Graceful stop/start for dictation session lifecycle
