import XCTest
@testable import RuneScaleCore

final class ReplayTests: XCTestCase {
    func testRecordingRoundTrip() throws {
        let hello = Data([0x53, 0x52, 1, 1, 24, 0, 0, 0])
        let reset = Data([0x53, 0x52, 1, 2, 0x80, 0x0C, 0, 0, 0x80, 0x0C, 0, 0, 0])
        let msgs = try Recording.messages(from: Recording.encode([hello, reset]))
        XCTAssertEqual(msgs, [.hello(radius: 24), .reset(baseX: 3200, baseY: 3200, plane: 0)])
    }

    func testRecordingTruncatedThrows() {
        var d = Recording.encode([Data([0x53, 0x52, 1, 1, 24, 0, 0, 0])])
        d.removeLast()
        XCTAssertThrowsError(try Recording.messages(from: d))
    }

    func testRecordingSkipsUnknownType() throws {
        let unknown = Data([0x53, 0x52, 1, 200])
        let hello = Data([0x53, 0x52, 1, 1, 8, 0, 0, 0])
        XCTAssertEqual(try Recording.messages(from: Recording.encode([unknown, hello])), [.hello(radius: 8)])
    }

    func testNearWhite() {
        XCTAssertTrue(ColorAudit.isNearWhite(0xF0F0F0))
        XCTAssertTrue(ColorAudit.isNearWhite(0xD8D8D8))
        XCTAssertFalse(ColorAudit.isNearWhite(0x3C6E28))
        XCTAssertFalse(ColorAudit.isNearWhite(0xFFE080)) // saturated yellow
    }

    func testMockWorldAuditFlagsLegacyRowsOnly() {
        let clean = ColorAudit.report(MockWorld.messages(legacy: false))
        XCTAssertEqual(clean.whiteMeshes, 0)
        XCTAssertEqual(clean.whiteTiles, 0)
        XCTAssertGreaterThan(clean.tiles, 1000)
        let legacy = ColorAudit.report(MockWorld.messages(legacy: true))
        XCTAssertEqual(Set(legacy.whiteMeshIds), [2001, 2200])
        // legacy tree: leaves white, trunk brown -> canopy faces dominate
        let bad = MockWorld.messages(legacy: true).compactMap { m -> RSProtocol.Mesh? in
            if case .mesh(let x) = m, x.id == 2001 { return x }; return nil
        }.first!
        XCTAssertGreaterThan(ColorAudit.nearWhiteFraction(bad), 0.5)
    }

    func testMockWorldGeometryBuilds() {
        for m in MockWorld.messages() {
            if case .mesh(let mesh) = m {
                let g = GeometryBuilder.build(mesh: mesh, metersPerUnit: 1 / 128)
                XCTAssertEqual(g.indices.count, mesh.faceCount * 3, "mesh \(mesh.id)")
                XCTAssertTrue(mesh.indices.allSatisfy { Int($0) < mesh.vertices.count / 3 })
            }
        }
    }
}
