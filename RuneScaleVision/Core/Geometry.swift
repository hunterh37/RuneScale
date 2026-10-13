import Foundation
import simd

/// Shared color palette: every mesh samples one 128x128 nearest-filtered texture,
/// so all geometry uses a single unlit material. 14-bit color (r5 g5 b4).
public enum Palette {
    public static let size = 128

    public static func index(rgb: UInt32) -> Int {
        let r = Int((rgb >> 16) & 0xFF) >> 3, g = Int((rgb >> 8) & 0xFF) >> 3, b = Int(rgb & 0xFF) >> 4
        return r << 9 | g << 4 | b
    }

    /// UV of a palette texel. Row 0 is the top row of the image; RealityKit v=1 is the top.
    public static func uv(rgb: UInt32) -> SIMD2<Float> {
        let i = index(rgb: rgb)
        let col = i % size, row = i / size
        return SIMD2(Float(col) + 0.5, Float(row) + 0.5) / Float(size) * SIMD2(1, -1) + SIMD2(0, 1)
    }

    /// RGBA8 bytes, row-major from the top row.
    public static func rgbaBytes() -> [UInt8] {
        var out = [UInt8](repeating: 255, count: size * size * 4)
        for i in 0..<(size * size) {
            let r = (i >> 9) & 31, g = (i >> 4) & 31, b = i & 15
            out[i * 4] = UInt8(r << 3 | r >> 2)
            out[i * 4 + 1] = UInt8(g << 3 | g >> 2)
            out[i * 4 + 2] = UInt8(b << 4 | b)
        }
        return out
    }

    static func average(_ a: UInt32, _ b: UInt32, _ c: UInt32) -> UInt32 {
        func ch(_ v: UInt32, _ s: UInt32) -> UInt32 { (v >> s) & 0xFF }
        let r = (ch(a, 16) + ch(b, 16) + ch(c, 16)) / 3
        let g = (ch(a, 8) + ch(b, 8) + ch(c, 8)) / 3
        let bl = (ch(a, 0) + ch(b, 0) + ch(c, 0)) / 3
        return r << 16 | g << 8 | bl
    }
}

/// Triangle soup ready for a RealityKit MeshDescriptor, in meters, RealityKit axes.
public struct Geometry: Sendable {
    public var positions: [SIMD3<Float>] = []
    public var uvs: [SIMD2<Float>] = []
    public var indices: [UInt32] = []
    public var isEmpty: Bool { indices.isEmpty }
}

/// OSRS units to RealityKit: x east -> +x, y down -> -y, z north -> -z (180 degree turn about X, keeps winding).
public enum Coordinates {
    public static let unitsPerTile: Float = 128

    public static func point(x: Float, y: Float, z: Float, metersPerUnit s: Float) -> SIMD3<Float> {
        SIMD3(x * s, -y * s, -z * s)
    }

    /// Inverse of `point`: RealityKit meters back to OSRS scene units.
    public static func units(_ p: SIMD3<Float>, metersPerUnit s: Float) -> (x: Int32, y: Int32, z: Int32) {
        (Int32((p.x / s).rounded()), Int32((-p.y / s).rounded()), Int32((-p.z / s).rounded()))
    }

    /// OSRS orientation (0..2047) to a RealityKit yaw in radians about +Y.
    public static func yaw(orientation: UInt16) -> Float {
        -Float(orientation & 2047) * (2 * .pi / 2048)
    }
}

public enum GeometryBuilder {
    /// Faces with alpha below this are dropped (transparency is not rendered).
    public static let minAlpha: UInt8 = 40

    public static func build(mesh: RSProtocol.Mesh, metersPerUnit s: Float) -> Geometry {
        var g = Geometry()
        let fc = mesh.faceCount
        g.positions.reserveCapacity(fc * 3); g.uvs.reserveCapacity(fc * 3); g.indices.reserveCapacity(fc * 3)
        let vcount = mesh.vertices.count / 3
        for f in 0..<fc where mesh.alpha[f] >= minAlpha {
            let ia = Int(mesh.indices[f * 3]), ib = Int(mesh.indices[f * 3 + 1]), ic = Int(mesh.indices[f * 3 + 2])
            guard ia < vcount, ib < vcount, ic < vcount else { continue }
            let uv = Palette.uv(rgb: Palette.average(mesh.colors[f * 3], mesh.colors[f * 3 + 1], mesh.colors[f * 3 + 2]))
            for v in [ia, ib, ic] {
                g.indices.append(UInt32(g.positions.count))
                g.positions.append(Coordinates.point(x: Float(mesh.vertices[v * 3]), y: Float(mesh.vertices[v * 3 + 1]), z: Float(mesh.vertices[v * 3 + 2]), metersPerUnit: s))
                g.uvs.append(uv)
            }
        }
        return g
    }

    /// Terrain tiles in scene-local positions (tile x,y * 128).
    public static func build(tiles: [RSProtocol.Tile], metersPerUnit s: Float) -> Geometry {
        var g = Geometry()
        let t = Coordinates.unitsPerTile
        for tile in tiles {
            let x0 = Float(tile.x) * t, z0 = Float(tile.y) * t
            let corners: [SIMD3<Float>] = [
                Coordinates.point(x: x0, y: Float(tile.heights[0]), z: z0, metersPerUnit: s),
                Coordinates.point(x: x0 + t, y: Float(tile.heights[1]), z: z0, metersPerUnit: s),
                Coordinates.point(x: x0 + t, y: Float(tile.heights[2]), z: z0 + t, metersPerUnit: s),
                Coordinates.point(x: x0, y: Float(tile.heights[3]), z: z0 + t, metersPerUnit: s),
            ]
            for tri in [[0, 1, 2], [0, 2, 3]] {
                let uv = Palette.uv(rgb: Palette.average(tile.colors[tri[0]], tile.colors[tri[1]], tile.colors[tri[2]]))
                for c in tri {
                    g.indices.append(UInt32(g.positions.count))
                    g.positions.append(corners[c])
                    g.uvs.append(uv)
                }
            }
        }
        return g
    }
}
