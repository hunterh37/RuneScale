import XCTest
import simd
@testable import RuneScaleCore

final class GestureTests: XCTestCase {
    /// Open hand at `wrist`, fingers 9 cm from the palm, thumb 6 cm from the index tip.
    func hand(_ t: TimeInterval, wrist: SIMD3<Float> = [0, 1, -0.4], pinch: Float = 0.06, curl: Float = 0.09) -> HandSample {
        let palm = wrist + [0, 0, -0.08]
        let index = palm + [0, 0, -curl]
        return HandSample(time: t, wrist: wrist, palm: palm, thumbTip: index + [pinch, 0, 0], indexTip: index,
                          middleTip: palm + [0.01, 0, -curl], ringTip: palm + [0.02, 0, -curl], littleTip: palm + [0.03, 0, -curl])
    }

    func testPinchHysteresisEmitsOneBeganOneEnded() {
        var g = GestureRecognizer()
        var events = [GestureEvent]()
        let d: [Float] = [0.06, 0.01, 0.02, 0.012, 0.025, 0.04, 0.05]
        for (i, p) in d.enumerated() { events += g.update(hand(Double(i) / 90, pinch: p)) }
        XCTAssertEqual(events.filter { if case .pinchBegan = $0 { true } else { false } }.count, 1)
        XCTAssertEqual(events.filter { if case .pinchEnded = $0 { true } else { false } }.count, 1)
    }

    func testFistIsGrabNotPinch() {
        var g = GestureRecognizer()
        var events = g.update(hand(0))
        events += g.update(hand(0.011, pinch: 0.01, curl: 0.03))
        XCTAssertTrue(events.contains { if case .grabBegan = $0 { true } else { false } })
        XCTAssertFalse(events.contains { if case .pinchBegan = $0 { true } else { false } })
        events = g.update(hand(0.022, curl: 0.1))
        XCTAssertTrue(events.contains { if case .grabEnded = $0 { true } else { false } })
    }

    func testFastArcEmitsOneSwingSlowMoveNone() {
        var g = GestureRecognizer()
        var events = [GestureEvent]()
        // 0.5 m sideways in 0.2 s (2.5 m/s), then stop
        for i in 0...18 { events += g.update(hand(Double(i) / 90, wrist: [0.3 - Float(i) * 0.028, 1.2, -0.4])) }
        for i in 19...30 { events += g.update(hand(Double(i) / 90, wrist: [-0.204, 1.2, -0.4])) }
        XCTAssertEqual(events.filter { if case .swing = $0 { true } else { false } }.count, 1)

        var slow = GestureRecognizer()
        var none = [GestureEvent]()
        for i in 0...90 { none += slow.update(hand(Double(i) / 90, wrist: [Float(i) * 0.005, 1.2, -0.4])) } // 0.45 m/s
        XCTAssertTrue(none.isEmpty)
    }

    func testSwingThroughNpcAttacksIt() {
        let t = [GestureTarget(key: 7, center: [0, 1, -1], radius: 0.4), GestureTarget(key: 9, center: [3, 1, -1], radius: 0.4)]
        let i = IntentMapper.swing(from: [0.4, 1.2, -0.5], to: [-0.2, 1.0, -0.6], velocity: [-2, -0.5, -0.2], targets: t)
        XCTAssertEqual(i, .attack(actorKey: 7))
    }

    func testSwingAimedAtDistantNpc() {
        let t = [GestureTarget(key: 3, center: [0, 1, -2.5], radius: 0.3)]
        let i = IntentMapper.swing(from: [0, 1.2, -0.2], to: [0, 1.1, -0.5], velocity: [0, -0.1, -2], targets: t)
        XCTAssertEqual(i, .attack(actorKey: 3))
    }

    func testSwingAwayFromNpcsDoesNothing() {
        let t = [GestureTarget(key: 3, center: [0, 1, -2.5], radius: 0.3)]
        let i = IntentMapper.swing(from: [0, 1.2, -0.5], to: [0, 1.1, -0.2], velocity: [0, 0, 2], targets: t)
        XCTAssertEqual(i, .none)
    }

    func testBackpackReachBehindShoulder() {
        var head = matrix_identity_float4x4
        head.columns.3 = [0, 1.6, 0, 1] // facing -z
        XCTAssertTrue(IntentMapper.isBackpackReach(hand: [0.15, 1.55, 0.1], head: head))
        XCTAssertFalse(IntentMapper.isBackpackReach(hand: [0.15, 1.3, -0.4], head: head))
        XCTAssertFalse(IntentMapper.isBackpackReach(hand: [0.15, 1.0, 0.1], head: head))
    }

    func testContainerAndWidgetClickWire() throws {
        var bytes: [UInt8] = [0x53, 0x52, 1, 10, 0, 2, 0, 0, 0]
        for v: Int32 in [995, 1000, -1, 0] { withUnsafeBytes(of: v.littleEndian) { bytes += $0 } }
        guard case .container(let c) = try RSProtocol.decode(Data(bytes)) else { return XCTFail() }
        XCTAssertEqual(c.kind, .inventory)
        XCTAssertEqual(c.ids, [995, -1])
        XCTAssertEqual(c.quantities, [1000, 0])
        let w = RSProtocol.encodeWidgetClick(seq: 7, button: .left, container: .equipment, slot: 3)
        XCTAssertEqual([UInt8](w), [0x53, 0x52, 1, 66, 7, 0, 0, 0, 0, 1, 3])
    }
}
