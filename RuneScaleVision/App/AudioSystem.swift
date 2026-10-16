import AVFoundation
import RealityKit
import RuneScaleCore

/// Game audio on the headset.
/// Sound effects: RealityKit SpatialAudioComponent on the source actor or scene point (head-tracked,
/// room acoustics) when spatial audio is on and a scene is open; AVAudioEngine stereo otherwise.
/// Music and headset UI sounds: AVAudioEngine, head-locked, looping music with crossfade.
@MainActor
final class AudioSystem {
    struct Settings {
        var master = true, music = true, effects = true, spatial = true, ui = true
        var musicVolume: Float = 0.5, effectsVolume: Float = 0.8
    }
    var settings = Settings() { didSet { applyMix() } }
    private(set) var nowPlaying = ""

    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: GameAudio.sampleRate, channels: 1)!
    private let musicBus = AVAudioMixerNode(), sfxBus = AVAudioMixerNode()
    private var musicPlayers: [AVAudioPlayerNode] = []
    private var activeMusic = 0
    private var sfxPool: [AVAudioPlayerNode] = []
    private var sfxNext = 0
    private var buffers: [Int: AVAudioPCMBuffer] = [:]          // sound id -> PCM
    private var uiBuffers: [GameAudio.UISound: AVAudioPCMBuffer] = [:]
    private var spatialRes: [Int: AudioBufferResource] = [:]
    private var liveSpatial = 0
    private static let maxSpatial = 24
    private var musicTask: Task<Void, Never>?
    private var started = false

    init() {
        engine.attach(musicBus); engine.attach(sfxBus)
        engine.connect(musicBus, to: engine.mainMixerNode, format: nil)
        engine.connect(sfxBus, to: engine.mainMixerNode, format: nil)
        for _ in 0..<2 { let p = AVAudioPlayerNode(); engine.attach(p); engine.connect(p, to: musicBus, format: format); musicPlayers.append(p) }
        for _ in 0..<8 { let p = AVAudioPlayerNode(); engine.attach(p); engine.connect(p, to: sfxBus, format: format); sfxPool.append(p) }
        applyMix()
    }

    private func start() {
        guard !started else { return }
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        engine.prepare()
        started = (try? engine.start()) != nil
    }

    private func applyMix() {
        musicBus.outputVolume = settings.master && settings.music ? settings.musicVolume : 0
        sfxBus.outputVolume = settings.master ? settings.effectsVolume : 0
        if !(settings.master && settings.music) { musicPlayers.forEach { $0.stop() } }
        else if !nowPlaying.isEmpty, musicPlayers.allSatisfy({ !$0.isPlaying }) { let t = nowPlaying; nowPlaying = ""; music(title: t) }
    }

    private func pcm(_ samples: [Float]) -> AVAudioPCMBuffer? {
        guard let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else { return nil }
        b.frameLength = b.frameCapacity
        samples.withUnsafeBufferPointer { src in b.floatChannelData![0].update(from: src.baseAddress!, count: samples.count) }
        return b
    }

    private func buffer(soundId: Int) -> AVAudioPCMBuffer? {
        if let b = buffers[soundId] { return b }
        let b = pcm(GameAudio.render(GameAudio.voice(soundId: soundId)))
        buffers[soundId] = b
        return b
    }

    // MARK: Headset UI

    func ui(_ s: GameAudio.UISound) {
        guard settings.master, settings.ui else { return }
        start()
        if uiBuffers[s] == nil { uiBuffers[s] = pcm(GameAudio.render(GameAudio.voice(ui: s))) }
        if let b = uiBuffers[s] { stereo(b, gain: 0.6) }
    }

    private func stereo(_ b: AVAudioPCMBuffer, gain: Float, delay: Double = 0) {
        guard started else { return }
        let p = sfxPool[sfxNext]; sfxNext = (sfxNext + 1) % sfxPool.count
        p.stop(); p.volume = gain
        p.scheduleBuffer(b, at: nil, completionHandler: nil)
        if delay > 0, let now = p.lastRenderTime ?? engine.outputNode.lastRenderTime {
            p.play(at: AVAudioTime(sampleTime: now.sampleTime + AVAudioFramePosition(delay * GameAudio.sampleRate), atRate: GameAudio.sampleRate))
        } else { p.play() }
    }

    // MARK: Game sound effects

    func play(_ snd: RSProtocol.Sound, scene: WorldScene?) {
        guard settings.master, settings.effects else { return }
        start()
        let id = Int(snd.soundId)
        let delay = GameAudio.delaySeconds(Int(snd.delay))
        if settings.spatial, let scene {
            playSpatial(id: id, snd: snd, scene: scene, delay: delay)
            return
        }
        guard let b = buffer(soundId: id) else { return }
        var gain: Float = 1
        if snd.area, let scene {
            let (parent, off) = scene.soundAnchor(snd)
            let p = parent.convert(position: off, to: scene.root)
            gain = GameAudio.areaGain(distance: simd_length(SIMD2(p.x, p.z)), range: Int(snd.range))
        }
        if gain > 0.01 { stereo(b, gain: gain, delay: delay) }
    }

    private func playSpatial(id: Int, snd: RSProtocol.Sound, scene: WorldScene, delay: Double) {
        guard liveSpatial < Self.maxSpatial else { return }
        if spatialRes[id] == nil, let b = buffer(soundId: id) {
            spatialRes[id] = try? AudioBufferResource(buffer: b, configuration: .init())
        }
        guard let res = spatialRes[id] else { return }
        let (parent, off) = scene.soundAnchor(snd)
        let e = Entity()
        e.position = off
        // tiles are meters at life size: let RealityKit attenuate within the game range
        var c = SpatialAudioComponent(gain: snd.area ? 0 : -4)
        c.distanceAttenuation = .rolloff(factor: snd.area ? Double(4) / Double(max(1, Int(snd.range))) : 0)
        e.components.set(c)
        parent.addChild(e)
        liveSpatial += 1
        let fire = { [weak self] in
            let ctl = e.playAudio(res)
            ctl.completionHandler = { e.removeFromParent(); self?.liveSpatial -= 1 }
        }
        if delay > 0 {
            Task { @MainActor in try? await Task.sleep(for: .seconds(delay)); fire() }
        } else { fire() }
    }

    // MARK: Music

    /// Switch to the procedural loop for a track title; same title is a no-op; empty fades out.
    func music(title: String) {
        guard title != nowPlaying else { return }
        nowPlaying = title
        musicTask?.cancel()
        let old = musicPlayers[activeMusic]
        guard settings.master, settings.music, !title.isEmpty else { fade(old, to: 0, stop: true); return }
        start()
        musicTask = Task { [weak self] in
            let samples = await Task.detached(priority: .utility) { GameAudio.render(GameAudio.track(title: title)) }.value
            guard let self, !Task.isCancelled, self.started, let b = self.pcm(samples) else { return }
            self.fade(old, to: 0, stop: true)
            self.activeMusic ^= 1
            let p = self.musicPlayers[self.activeMusic]
            p.stop(); p.volume = 0
            p.scheduleBuffer(b, at: nil, options: .loops, completionHandler: nil)
            p.play()
            self.fade(p, to: 1, stop: false)
        }
    }

    private func fade(_ p: AVAudioPlayerNode, to target: Float, stop: Bool, seconds: Double = 1.5) {
        let from = p.volume, steps = 30
        Task { @MainActor in
            for i in 1...steps {
                try? await Task.sleep(for: .seconds(seconds / Double(steps)))
                p.volume = from + (target - from) * Float(i) / Float(steps)
            }
            if stop { p.stop() }
        }
    }
}
