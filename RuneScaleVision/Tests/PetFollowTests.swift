import XCTest
import simd
@testable import RuneScaleCore

final class PetFollowTests: XCTestCase {
    func testTargetBehindAndRight() {
        let t = PetFollow.target(head: [0, 0], forward: [0, -2], distance: 1, side: 0.5)
        XCTAssertEqual(t.x, 0.5, accuracy: 1e-5) // right of -Z forward is +X
        XCTAssertEqual(t.y, 1, accuracy: 1e-5)  // behind is +Z
    }

    func testIdleInsideDeadZoneFacesViewer() {
        let s = PetFollow.State(position: [0, 1], yaw: 0)
        let n = PetFollow.step(s, goal: [0.1, 1], head: [0, 0], dt: 0.04)
        XCTAssertEqual(n.position, s.position)
        XCTAssertEqual(n.yaw, PetFollow.yawFacing([0, -1], fallback: 0), accuracy: 1e-5)
    }

    func testMovesTowardGoalWithoutOvershoot() {
        var s = PetFollow.State(position: [0, 0], yaw: 0)
        for _ in 0..<200 { s = PetFollow.step(s, goal: [3, 0], head: [3, -1], dt: 0.04) }
        XCTAssertLessThanOrEqual(simd_distance(s.position, [3, 0]), 0.35)
        XCTAssertLessThan(s.position.x, 3)
    }

    func testTeleportsWhenFar() {
        let n = PetFollow.step(.init(position: [0, 0], yaw: 0), goal: [10, 0], head: [10, 1], dt: 0.04)
        XCTAssertEqual(n.position, [10, 0])
    }

    func testYawMatchesOrientationConvention() {
        // orientation 0 faces south (+Z), 512 faces west (-X)
        XCTAssertEqual(PetFollow.yawFacing([0, 1], fallback: 9), Coordinates.yaw(orientation: 0), accuracy: 1e-5)
        XCTAssertEqual(PetFollow.yawFacing([-1, 0], fallback: 9), Coordinates.yaw(orientation: 512), accuracy: 1e-5)
    }

    func testPetKinds() {
        XCTAssertTrue(RSProtocol.ActorKind.ownPet.isPet)
        XCTAssertTrue(RSProtocol.ActorKind.pet.isPet)
        XCTAssertFalse(RSProtocol.ActorKind.npc.isPet)
    }
}
