import Foundation

/// Offline stream sources for the simulator and tests.
/// `.rsrec` files come from the plugin option "Record stream": per message a u32 LE length, then the bytes.
public enum Recording {
    public enum ReadError: Error, Equatable { case truncated(offset: Int) }

    public static func messages(from data: Data) throws -> [RSProtocol.Message] {
        var out: [RSProtocol.Message] = []
        let bytes = [UInt8](data)
        var i = 0
        while i < bytes.count {
            guard i + 4 <= bytes.count else { throw ReadError.truncated(offset: i) }
            let n = Int(bytes[i]) | Int(bytes[i + 1]) << 8 | Int(bytes[i + 2]) << 16 | Int(bytes[i + 3]) << 24
            i += 4
            guard n >= 0, i + n <= bytes.count else { throw ReadError.truncated(offset: i - 4) }
            // skip messages this build cannot decode instead of failing the whole file
            if let m = try? RSProtocol.decode(Data(bytes[i..<(i + n)])) { out.append(m) }
            i += n
        }
        return out
    }

    public static func encode(_ frames: [Data]) -> Data {
        var d = Data()
        for f in frames {
            let n = UInt32(f.count)
            d.append(contentsOf: [UInt8(n & 0xFF), UInt8(n >> 8 & 0xFF), UInt8(n >> 16 & 0xFF), UInt8(n >> 24 & 0xFF)])
            d.append(f)
        }
        return d
    }
}

/// Color checks for textured-face regressions. Textured faces decoded as plain HSL come out as
/// low-saturation light gray or white.
public enum ColorAudit {
    public static func isNearWhite(_ rgb: UInt32) -> Bool {
        let r = Int(rgb >> 16 & 0xFF), g = Int(rgb >> 8 & 0xFF), b = Int(rgb & 0xFF)
        return min(r, g, b) >= 200 && max(r, g, b) - min(r, g, b) <= 24
    }

    /// Fraction of faces whose average corner color is near white.
    public static func nearWhiteFraction(_ m: RSProtocol.Mesh) -> Double {
        let fc = m.faceCount
        guard fc > 0, m.colors.count >= fc * 3 else { return 0 }
        var n = 0
        for f in 0..<fc where isNearWhite(Palette.average(m.colors[f * 3], m.colors[f * 3 + 1], m.colors[f * 3 + 2])) { n += 1 }
        return Double(n) / Double(fc)
    }

    public struct Report: Sendable, Equatable {
        public var meshes = 0, whiteMeshes = 0, tiles = 0, whiteTiles = 0
        public var whiteMeshIds: [Int64] = []
    }

    /// Meshes with more than half their faces near white, and terrain tiles with any near-white corner.
    public static func report(_ messages: [RSProtocol.Message]) -> Report {
        var r = Report()
        for m in messages {
            switch m {
            case .mesh(let mesh):
                r.meshes += 1
                if nearWhiteFraction(mesh) > 0.5 { r.whiteMeshes += 1; r.whiteMeshIds.append(mesh.id) }
            case .terrain(let tiles):
                r.tiles += tiles.count
                r.whiteTiles += tiles.filter { $0.colors.contains(where: isNearWhite) }.count
            default: break
            }
        }
        return r
    }
}

/// Synthetic Lumbridge-like scene: grass terrain with a dirt path, a stone courtyard of tile models,
/// trees, a wall and the local player. `legacy` adds a second row of trees and floor colored the way
/// textured faces arrived before the texture fix (lightness read as HSL), for side-by-side comparison.
public enum MockWorld {
    public static let baseX: Int32 = 3200, baseY: Int32 = 3200
    static let center = 52 // scene tile of the player

    public static func messages(legacy: Bool = true) -> [RSProtocol.Message] {
        var out: [RSProtocol.Message] = [.hello(radius: 24), .reset(baseX: baseX, baseY: baseY, plane: 0)]
        out.append(.terrain(terrain()))

        let tree = treeMesh(id: 1001, leaf: 0x3C6E28, trunk: 0x5A3C1E)
        let player = boxMesh(id: 9001, size: 50, height: 190, color: 0x2850A0, transient: true)
        let wall = boxMesh(id: 1100, size: 128, height: 300, color: 0x8C8C84, transient: false, depth: 24)
        out += [.mesh(tree), .mesh(player), .mesh(wall)]
        let floor = courtyardMesh(id: 1200, colorFor: { x, y in (x + y) % 2 == 0 ? 0x6E6A62 : 0x5E5A54 })
        out.append(.mesh(floor))

        var inst: [RSProtocol.Instance] = []
        var nextId: Int64 = 1
        func place(_ mesh: Int64, _ tx: Int, _ ty: Int, _ o: UInt16 = 0) {
            inst.append(.init(id: nextId, meshId: mesh, x: Int32(tx * 128 + 64), y: height(tx, ty), z: Int32(ty * 128 + 64), orientation: o))
            nextId += 1
        }
        for (i, tx) in stride(from: center - 8, through: center + 8, by: 4).enumerated() { place(tree.id, tx, center + 5, UInt16(i * 300 % 2048)) }
        for tx in (center - 3)...(center + 3) { place(wall.id, tx, center - 4) }
        inst.append(.init(id: -1, meshId: floor.id, x: 0, y: 0, z: 0, orientation: 0))

        if legacy {
            // white leaves and gray-white floor: the reported symptom
            let bad = treeMesh(id: 2001, leaf: 0xF0F0F0, trunk: 0x5A3C1E)
            let badFloor = courtyardMesh(id: 2200, offsetY: 8, colorFor: { x, y in (x * 7 + y * 3) % 5 == 0 ? 0xFFFFFF : 0xD8D8D8 })
            out += [.mesh(bad), .mesh(badFloor)]
            for tx in stride(from: center - 8, through: center + 8, by: 4) { place(bad.id, tx, center + 9) }
            inst.append(.init(id: -2, meshId: badFloor.id, x: 0, y: 0, z: 0, orientation: 0))
        }
        out.append(.staticAdd(inst))

        let px = Int32(center * 128 + 64), pz = Int32(center * 128 + 64)
        out.append(.frame(.init(tick: 1, playerX: px, playerY: height(center, center), playerZ: pz, playerOrientation: 0, cameraYaw: 0, plane: 0,
                                actors: [.init(key: 1, kind: .local, x: px, y: height(center, center), z: pz, orientation: 0, meshId: player.id)])))
        return out
    }

    /// Flat field of pseudo-random tile colors: every adjacent palette texel differs, so any
    /// block compression of the palette texture shows as off-color tiles.
    public static func paletteTest() -> [RSProtocol.Message] {
        var tiles: [RSProtocol.Tile] = []
        var r: UInt32 = 0x9E3779B9
        for x in (center - 24)...(center + 24) {
            for y in (center - 24)...(center + 24) {
                r ^= r << 13; r ^= r >> 17; r ^= r << 5
                let c = r & 0xFFFFFF
                tiles.append(.init(x: x, y: y, plane: 0, heights: [0, 0, 0, 0], colors: [c, c, c, c]))
            }
        }
        let px = Int32(center * 128 + 64)
        return [.hello(radius: 24), .reset(baseX: baseX, baseY: baseY, plane: 0), .terrain(tiles),
                .frame(.init(tick: 1, playerX: px, playerY: 0, playerZ: px, playerOrientation: 0, cameraYaw: 0, plane: 0, actors: []))]
    }

    /// Gentle hills, height positive downward.
    static func height(_ x: Int, _ y: Int) -> Int32 {
        Int32(-40 * sin(Double(x) * 0.35) - 30 * cos(Double(y) * 0.27))
    }

    static func terrain() -> [RSProtocol.Tile] {
        var tiles: [RSProtocol.Tile] = []
        for x in (center - 24)...(center + 24) {
            for y in (center - 24)...(center + 24) {
                if abs(x - center) <= 3 && (center - 3...center + 1).contains(y) { continue } // courtyard tile models
                let path = abs(x - center - 6) <= 1
                let shade = UInt32((x * 13 + y * 7) % 16)
                let c: UInt32 = path ? 0x8C6E46 + shade * 0x010100 : 0x3C7828 + shade * 0x000200
                tiles.append(.init(x: x, y: y, plane: 0,
                                   heights: [height(x, y), height(x + 1, y), height(x + 1, y + 1), height(x, y + 1)],
                                   colors: [c, c, c, c]))
            }
        }
        return tiles
    }

    /// Scene-local tile model mesh covering the courtyard, two triangles per tile.
    static func courtyardMesh(id: Int64, offsetY: Int = 0, colorFor: (Int, Int) -> UInt32) -> RSProtocol.Mesh {
        var v: [Int16] = [], idx: [UInt16] = [], col: [UInt32] = []
        let y0 = offsetY == 0 ? center - 3 : center + 7
        for x in (center - 3)...(center + 3) {
            for y in y0...(y0 + 4) {
                let base = UInt16(v.count / 3)
                for (dx, dy) in [(0, 0), (1, 0), (1, 1), (0, 1)] {
                    v += [Int16((x + dx) * 128), Int16(height(x + dx, y + dy) - 2), Int16((y + dy) * 128)]
                }
                idx += [base, base + 1, base + 2, base, base + 2, base + 3]
                let c = colorFor(x, y)
                col += Array(repeating: c, count: 6)
            }
        }
        return .init(id: id, transient: false, vertices: v, indices: idx, colors: col, alpha: Array(repeating: 255, count: idx.count / 3))
    }

    /// Trunk box plus a two-tier octahedron canopy.
    static func treeMesh(id: Int64, leaf: UInt32, trunk: UInt32) -> RSProtocol.Mesh {
        var m = boxMesh(id: id, size: 36, height: 220, color: trunk, transient: false)
        func octa(_ r: Int16, _ cy: Int16, _ h: Int16, _ c: UInt32) {
            let b = UInt16(m.vertices.count / 3)
            m.vertices += [r, cy, 0, 0, cy, r, -r, cy, 0, 0, cy, -r, 0, cy - h, 0, 0, cy + h / 2, 0]
            for i in 0..<4 {
                let a = b + UInt16(i), n = b + UInt16((i + 1) % 4)
                m.indices += [a, n, b + 4, n, a, b + 5]
                let lit = i % 2 == 0 ? c : c &- 0x0C0C0C
                m.colors += Array(repeating: lit, count: 6)
                m.alpha += [255, 255]
            }
        }
        octa(150, -200, 140, leaf)
        octa(100, -320, 120, leaf)
        return m
    }

    static func boxMesh(id: Int64, size: Int16, height: Int16, color: UInt32, transient: Bool, depth: Int16? = nil) -> RSProtocol.Mesh {
        let sx = size / 2, sz = (depth ?? size) / 2
        var v: [Int16] = []
        for y in [0, -height] { v += [-sx, y, -sz, sx, y, -sz, sx, y, sz, -sx, y, sz] }
        let quads: [[UInt16]] = [[0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7], [4, 5, 6, 7]]
        var idx: [UInt16] = [], col: [UInt32] = []
        for (i, q) in quads.enumerated() {
            idx += [q[0], q[1], q[2], q[0], q[2], q[3]]
            let c = i % 2 == 0 ? color : Palette.average(color, color, 0x202020)
            col += Array(repeating: c, count: 6)
        }
        return .init(id: id, transient: transient, vertices: v, indices: idx, colors: col, alpha: Array(repeating: 255, count: idx.count / 3))
    }
}
