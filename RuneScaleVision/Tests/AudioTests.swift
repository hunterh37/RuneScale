import XCTest
@testable import RuneScaleCore

final class AudioTests: XCTestCase {
    func testDecodeSoundAndMusic() throws {
        var d = Data([0x53, 0x52, 1, 16, 1])
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        u16(2266); u16(10); d.append(8); u32(UInt32(bitPattern: 640)); u32(UInt32(bitPattern: -128)); u32(0xFFFF_FFFF)
        XCTAssertEqual(try RSProtocol.decode(d), .sound(.init(area: true, soundId: 2266, delay: 10, range: 8, x: 640, z: -128, sourceKey: .max)))
        var m = Data([0x53, 0x52, 1, 17, 6, 0]); m.append(contentsOf: Array("Harmony".utf8.prefix(6)))
        XCTAssertEqual(try RSProtocol.decode(m), .music(title: "Harmon"))
        XCTAssertThrowsError(try RSProtocol.decode(Data([0x53, 0x52, 1, 16, 1, 0])))
    }

    func testAreaGain() {
        XCTAssertEqual(GameAudio.areaGain(distance: 0.5, range: 5), 1)
        XCTAssertEqual(GameAudio.areaGain(distance: 3.5, range: 5), 0.5, accuracy: 1e-5)
        XCTAssertEqual(GameAudio.areaGain(distance: 6, range: 5), 0)
        XCTAssertEqual(GameAudio.areaGain(distance: 2, range: 0), 0)
        XCTAssertEqual(GameAudio.decibels(1), 0, accuracy: 1e-9)
        XCTAssertEqual(GameAudio.decibels(0), -80)
        XCTAssertEqual(GameAudio.delaySeconds(25), 0.5, accuracy: 1e-9)
        XCTAssertEqual(GameAudio.delaySeconds(1000), 2)
    }

    func testVoicesDeterministicAndBounded() {
        XCTAssertEqual(GameAudio.voice(soundId: 2266), GameAudio.voice(soundId: 2266))
        XCTAssertNotEqual(GameAudio.voice(soundId: 1), GameAudio.voice(soundId: 2))
        for id in [0, 1, 2266, 65535] {
            let pcm = GameAudio.render(GameAudio.voice(soundId: id))
            XCTAssertGreaterThan(pcm.count, Int(0.07 * GameAudio.sampleRate))
            XCTAssertLessThanOrEqual(pcm.map(abs).max()!, 1)
            XCTAssertLessThan(abs(pcm.last!), 0.01, "decays to silence")
        }
        for ui in GameAudio.UISound.allCases { XCTAssertFalse(GameAudio.render(GameAudio.voice(ui: ui)).isEmpty) }
    }

    func testMusicLoop() {
        let t = GameAudio.track(title: "Harmony")
        XCTAssertEqual(t, GameAudio.track(title: "harmony"))
        XCTAssertNotEqual(t, GameAudio.track(title: "Newbie Melody"))
        let pcm = GameAudio.render(t)
        let expected = Int(60 / t.bpm * 4 * 2 * Double(t.progression.count) * GameAudio.sampleRate)
        XCTAssertEqual(pcm.count, expected)
        XCTAssertLessThanOrEqual(pcm.map(abs).max()!, 0.951)
        XCTAssertGreaterThan(pcm.map(abs).max()!, 0.05)
    }
}
