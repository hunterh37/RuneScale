import XCTest
import simd
@testable import RuneScaleCore

final class BodyLayoutTests: XCTestCase {
    func head(y: Float = 1.6, yaw: Float = 0) -> simd_float4x4 {
        var m = simd_float4x4(simd_quatf(angle: yaw, axis: [0, 1, 0]))
        m.columns.3 = [0.5, y, 2, 1]
        return m
    }

    func testAnchorsShieldOffHandWeaponSwordHand() {
        XCTAssertEqual(EquipSlot.weapon.anchor, .swordHand)
        XCTAssertEqual(EquipSlot.shield.anchor, .offHand)
        XCTAssertEqual(EquipSlot.body.anchor, .body)
        XCTAssertNil(BodyLayout.transform(.weapon, head: head()))
    }

    func testBootsOnFloorBodyBelowHead() throws {
        let boots = try XCTUnwrap(BodyLayout.transform(.boots, head: head()))
        XCTAssertEqual(boots.columns.3.y, 0.08, accuracy: 0.01)
        let body = try XCTUnwrap(BodyLayout.transform(.body, head: head()))
        XCTAssertEqual(body.columns.3.y, 1.12, accuracy: 0.01)
        let legs = try XCTUnwrap(BodyLayout.transform(.legs, head: head()))
        XCTAssertTrue(legs.columns.3.y < body.columns.3.y && legs.columns.3.y > boots.columns.3.y)
    }

    func testCapeBehindWhenTurned() throws {
        // facing +x (yaw -90 deg): back is -x
        let cape = try XCTUnwrap(BodyLayout.transform(.cape, head: head(yaw: -.pi / 2)))
        XCTAssertLessThan(cape.columns.3.x, 0.5 - 0.1)
    }

    func testScaleFitsLongestExtent() {
        XCTAssertEqual(BodyLayout.scale(extents: [0.1, 1.8, 0.2], slot: .weapon), 0.5, accuracy: 1e-5)
        XCTAssertEqual(BodyLayout.scale(extents: .zero, slot: .weapon), 0)
    }

    func testEquipModelDecode() throws {
        var b: [UInt8] = [0x53, 0x52, 1, 12, 5]
        withUnsafeBytes(of: Int32(1201).littleEndian) { b += $0 }
        withUnsafeBytes(of: Int64(-9).littleEndian) { b += $0 }
        XCTAssertEqual(try RSProtocol.decode(Data(b)), .equipModel(slot: 5, itemId: 1201, meshId: -9))
    }
}
