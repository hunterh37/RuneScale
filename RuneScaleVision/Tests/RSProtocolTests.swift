import XCTest
import simd
@testable import RuneScaleCore

final class RSProtocolTests: XCTestCase {
    private struct W {
        var d = Data()
        mutating func u8(_ v: UInt8) { d.append(v) }
        mutating func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        mutating func i16(_ v: Int16) { u16(UInt16(bitPattern: v)) }
        mutating func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        mutating func i32(_ v: Int32) { u32(UInt32(bitPattern: v)) }
        mutating func i64(_ v: Int64) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        mutating func rgb(_ v: UInt32) { u8(UInt8(v >> 16 & 0xFF)); u8(UInt8(v >> 8 & 0xFF)); u8(UInt8(v & 0xFF)) }
        mutating func header(_ t: UInt8) { u16(0x5253); u8(1); u8(t) }
    }

    func testMesh() throws {
        var w = W(); w.header(3)
        w.i64(-7); w.u8(1); w.u32(3); w.u32(1)
        for v: Int16 in [0, 0, 0, 128, -64, 0, 0, 0, 128] { w.i16(v) }
        for i: UInt16 in [0, 1, 2] { w.u16(i) }
        for c: UInt32 in [0xFF0000, 0x00FF00, 0x0000FF] { w.rgb(c) }
        w.u8(255)
        guard case .mesh(let m) = try RSProtocol.decode(w.d) else { return XCTFail() }
        XCTAssertEqual(m.id, -7)
        XCTAssertTrue(m.transient)
        XCTAssertEqual(m.vertices[4], -64)
        XCTAssertEqual(m.colors, [0xFF0000, 0x00FF00, 0x0000FF])

        let g = GeometryBuilder.build(mesh: m, metersPerUnit: 1.0 / 128)
        XCTAssertEqual(g.indices.count, 3)
        XCTAssertEqual(g.positions[1], SIMD3<Float>(1, 0.5, 0)) // y down -> up
        XCTAssertEqual(g.positions[2].z, -1) // north -> -z
    }

    func testFrameAndStatic() throws {
        var w = W(); w.header(7)
        w.u32(5); w.i32(6400); w.i32(-200); w.i32(3200); w.u16(1024); w.u16(2047); w.u8(0)
        w.u32(1); w.u32(0x10003); w.u8(2); w.i32(1); w.i32(2); w.i32(3); w.u16(512); w.i64(99)
        guard case .frame(let f) = try RSProtocol.decode(w.d) else { return XCTFail() }
        XCTAssertEqual(f.playerY, -200)
        XCTAssertEqual(f.actors.first?.kind, .npc)
        XCTAssertEqual(f.actors.first?.meshId, 99)

        var s = W(); s.header(5); s.u32(1); s.i64(Int64.max); s.i64(4); s.i32(1); s.i32(-2); s.i32(3); s.u16(2047)
        guard case .staticAdd(let list) = try RSProtocol.decode(s.d) else { return XCTFail() }
        XCTAssertEqual(list.first?.id, Int64.max)
        XCTAssertEqual(list.first?.orientation, 2047)
    }

    func testTerrainGeometry() throws {
        var w = W(); w.header(4); w.u32(1)
        w.u8(2); w.u8(3); w.u8(0)
        for h: Int32 in [0, 0, -128, -128] { w.i32(h) }
        for _ in 0..<4 { w.rgb(0x336633) }
        guard case .terrain(let tiles) = try RSProtocol.decode(w.d) else { return XCTFail() }
        let g = GeometryBuilder.build(tiles: tiles, metersPerUnit: 1.0 / 128)
        XCTAssertEqual(g.indices.count, 6)
        XCTAssertEqual(g.positions[0], SIMD3<Float>(2, 0, -3))
        XCTAssertEqual(g.positions[2], SIMD3<Float>(3, 1, -4))
    }

    func testErrors() {
        XCTAssertThrowsError(try RSProtocol.decode(Data([0x53, 0x52, 1, 1]))) // truncated hello
        XCTAssertThrowsError(try RSProtocol.decode(Data([0, 0, 1, 1, 0, 0, 0, 0])))
        var w = W(); w.header(99)
        XCTAssertEqual((try? RSProtocol.decode(w.d)) == nil, true)
    }

    func testPalette() {
        XCTAssertEqual(Palette.rgbaBytes().count, 128 * 128 * 4)
        let uv = Palette.uv(rgb: 0xFFFFFF)
        XCTAssertGreaterThan(uv.x, 0.99)
        XCTAssertLessThan(uv.y, 0.01)
        XCTAssertEqual(Coordinates.yaw(orientation: 512), -.pi / 2, accuracy: 1e-5)
    }

    func testClickEncodingLayout() {
        let d = RSProtocol.encodeClick(seq: 0x01020304, button: .right, x: 6464, y: -312, z: -1)
        XCTAssertEqual(d.count, 21)
        XCTAssertEqual(Array(d.prefix(4)), [0x53, 0x52, 1, 64])
        XCTAssertEqual(Array(d[4..<8]), [4, 3, 2, 1])
        XCTAssertEqual(d[8], 1)
        XCTAssertEqual(Array(d[9..<13]), [0x40, 0x19, 0, 0])
        XCTAssertEqual(Array(d[17..<21]), [0xFF, 0xFF, 0xFF, 0xFF])
    }

    func testAckDecode() throws {
        let bytes: [UInt8] = [0x53, 0x52, 1, 8, 7, 0, 0, 0, 2, 0xFF, 0xFF, 0xFF, 0xFF, 0x2C, 1, 0, 0]
        XCTAssertEqual(try RSProtocol.decode(Data(bytes)),
                       .inputAck(.init(seq: 7, result: .offscreen, canvasX: -1, canvasY: 300)))
    }

    func testUnitsInvertsPoint() {
        let s: Float = 1 / 128
        let p = Coordinates.point(x: 6464, y: -312, z: 6592, metersPerUnit: s)
        let u = Coordinates.units(p, metersPerUnit: s)
        XCTAssertEqual(u.x, 6464); XCTAssertEqual(u.y, -312); XCTAssertEqual(u.z, 6592)
    }
}
