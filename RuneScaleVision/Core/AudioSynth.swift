import Foundation

/// Game sound and music as data: event mapping, distance gain and procedural PCM.
/// The plugin forwards sound ids (SOUND) and the music tab title (MUSIC); OSRS synth data stays in the
/// client cache, so the headset renders each id and each track title to a seeded procedural voice.
public enum GameAudio {
    public static let sampleRate: Double = 44_100

    /// Linear gain for an area sound `distance` tiles away with the game's `range` in tiles.
    /// Full volume inside one tile, linear falloff to 0 at range + 1 (OSRS area sounds fade the same way).
    public static func areaGain(distance: Float, range: Int) -> Float {
        let r = Float(max(range, 1))
        if distance <= 1 { return 1 }
        return max(0, 1 - (distance - 1) / r)
    }

    /// Linear gain to RealityKit decibels; silence clamps to -80 dB.
    public static func decibels(_ linear: Float) -> Double {
        linear <= 0.0001 ? -80 : Double(20 * log10(linear))
    }

    /// Delay field (client cycles of 20 ms) to seconds, capped at 2 s.
    public static func delaySeconds(_ delay: Int) -> Double { min(2, Double(max(0, delay)) * 0.02) }

    // MARK: Sound effects

    public enum Wave: Int, Sendable { case sine, square, saw, noise }

    public struct Voice: Sendable, Equatable {
        public var wave: Wave
        public var startHz: Double, endHz: Double
        public var duration: Double, attack: Double
        public var noiseMix: Double
    }

    /// Deterministic voice for one sound id.
    public static func voice(soundId: Int) -> Voice {
        var rng = SeededRNG(seed: UInt64(truncatingIfNeeded: soundId) &* 0x9E37_79B9_7F4A_7C15 &+ 1)
        let wave = Wave(rawValue: Int(rng.next() % 4))!
        let start = 140 * pow(2, rng.unit() * 3.2)          // 140 Hz .. ~1.3 kHz
        let bend = pow(2, (rng.unit() - 0.6) * 2)           // mostly downward sweeps
        return Voice(wave: wave, startHz: start, endHz: start * bend,
                     duration: 0.08 + rng.unit() * 0.32, attack: 0.002 + rng.unit() * 0.02,
                     noiseMix: wave == .noise ? 1 : rng.unit() * 0.25)
    }

    /// Mono PCM in -1...1 for a voice.
    public static func render(_ v: Voice) -> [Float] {
        let n = Int(v.duration * sampleRate)
        var out = [Float](repeating: 0, count: n)
        var phase = 0.0
        var rng = SeededRNG(seed: UInt64(v.startHz * 1000))
        for i in 0..<n {
            let t = Double(i) / sampleRate, u = t / v.duration
            let hz = v.startHz * pow(v.endHz / v.startHz, u)
            phase += hz / sampleRate
            phase -= phase.rounded(.down)
            let tone: Double
            switch v.wave {
            case .sine: tone = sin(2 * .pi * phase)
            case .square: tone = phase < 0.5 ? 0.6 : -0.6
            case .saw: tone = (2 * phase - 1) * 0.7
            case .noise: tone = 0
            }
            let noise = rng.unit() * 2 - 1
            let env = min(1, t / v.attack) * pow(1 - u, 2)
            out[i] = Float(((1 - v.noiseMix) * tone + v.noiseMix * noise) * env * 0.8)
        }
        return out
    }

    // MARK: UI sounds (headset-side interactions)

    public enum UISound: Int, CaseIterable, Sendable { case tap, open, close, confirm, deny }

    public static func voice(ui: UISound) -> Voice {
        switch ui {
        case .tap: Voice(wave: .sine, startHz: 1400, endHz: 1100, duration: 0.05, attack: 0.001, noiseMix: 0.05)
        case .open: Voice(wave: .sine, startHz: 520, endHz: 880, duration: 0.14, attack: 0.004, noiseMix: 0)
        case .close: Voice(wave: .sine, startHz: 880, endHz: 520, duration: 0.12, attack: 0.004, noiseMix: 0)
        case .confirm: Voice(wave: .sine, startHz: 660, endHz: 990, duration: 0.18, attack: 0.003, noiseMix: 0)
        case .deny: Voice(wave: .square, startHz: 220, endHz: 180, duration: 0.16, attack: 0.003, noiseMix: 0)
        }
    }

    // MARK: Music

    public struct Track: Sendable, Equatable {
        public var rootMidi: Int
        public var mode: [Int]          // scale steps from root
        public var bpm: Double
        public var progression: [Int]   // scale degrees, one per bar
        public var seed: UInt64
    }

    static let modes: [[Int]] = [[0, 2, 3, 5, 7, 9, 10], [0, 2, 3, 5, 7, 8, 10], [0, 2, 4, 5, 7, 9, 11], [0, 2, 4, 5, 7, 9, 10]]

    /// Deterministic track parameters from the game's track title.
    public static func track(title: String) -> Track {
        var h: UInt64 = 0xCBF2_9CE4_8422_2325
        for b in title.lowercased().utf8 { h = (h ^ UInt64(b)) &* 0x100_0000_01B3 }
        var rng = SeededRNG(seed: h)
        let progs: [[Int]] = [[0, 5, 3, 4], [0, 3, 4, 0], [0, 6, 5, 4], [0, 4, 5, 3]]
        return Track(rootMidi: 45 + Int(rng.next() % 12), mode: modes[Int(rng.next() % 4)],
                     bpm: 64 + Double(rng.next() % 24), progression: progs[Int(rng.next() % 4)], seed: h)
    }

    static func hz(_ midi: Int) -> Double { 440 * pow(2, Double(midi - 69) / 12) }

    /// Seamless loop: 4 bars per chord, pad triads plus a sparse plucked melody. Mono, -1...1.
    public static func render(_ t: Track) -> [Float] {
        let beat = 60 / t.bpm, bar = beat * 4
        let barsPerChord = 2
        let total = bar * Double(barsPerChord * t.progression.count)
        let n = Int(total * sampleRate)
        var out = [Float](repeating: 0, count: n)
        func note(_ degree: Int, octave: Int) -> Int {
            let d = ((degree % 7) + 7) % 7
            return t.rootMidi + 12 * (octave + degree / 7) + t.mode[d]
        }
        // pad
        for (ci, deg) in t.progression.enumerated() {
            let start = Double(ci * barsPerChord) * bar, len = Double(barsPerChord) * bar
            for (k, off) in [0, 2, 4].enumerated() {
                let f = hz(note(deg + off, octave: 0)), f2 = f * 1.003
                let s0 = Int(start * sampleRate), s1 = min(n, Int((start + len) * sampleRate))
                for i in s0..<s1 {
                    let tt = Double(i) / sampleRate - start
                    let env = min(1, tt / 0.6) * min(1, (len - tt) / 0.6)
                    let v = (sin(2 * .pi * f * tt) + sin(2 * .pi * f2 * tt + Double(k))) * 0.5
                    out[i] += Float(v * env * 0.08)
                }
            }
        }
        // melody: eighth-note grid, ~40% density
        var rng = SeededRNG(seed: t.seed ^ 0xA5A5)
        let steps = Int(total / (beat / 2))
        var deg = 4
        for s in 0..<steps where rng.unit() < 0.4 {
            deg = max(0, min(11, deg + Int(rng.next() % 5) - 2))
            let f = hz(note(deg, octave: 1))
            let s0 = Int(Double(s) * beat / 2 * sampleRate)
            let len = Int(beat * 1.5 * sampleRate)
            for j in 0..<len {
                let i = (s0 + j) % n           // wrap tail so the loop is seamless
                let tt = Double(j) / sampleRate
                out[i] += Float(sin(2 * .pi * f * tt) * exp(-tt * 4) * 0.12)
            }
        }
        let peak = out.reduce(0) { max($0, abs($1)) }
        if peak > 0.95 { let g = 0.95 / peak; for i in out.indices { out[i] *= g } }
        return out
    }
}

/// SplitMix64.
public struct SeededRNG: Sendable {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    public mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
}
