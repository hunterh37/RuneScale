import Foundation

/// Decoder for the RuneScale Stream wire format (notes/PROTOCOL.md). Little-endian.
public enum RSProtocol {
    public static let magic: UInt16 = 0x5253
    public static let version: UInt8 = 1

    public struct Mesh: Sendable, Equatable {
        public var id: Int64
        public var transient: Bool
        public var vertices: [Int16]   // x,y,z triples, OSRS model units, y down
        public var indices: [UInt16]   // a,b,c per face
        public var colors: [UInt32]    // rgb per face corner
        public var alpha: [UInt8]      // per face
        public var faceCount: Int { indices.count / 3 }
    }

    public struct Tile: Sendable, Equatable {
        public var x: Int, y: Int, plane: Int
        public var heights: [Int32]    // sw, se, ne, nw
        public var colors: [UInt32]
    }

    public struct Instance: Sendable, Equatable {
        public var id: Int64, meshId: Int64
        public var x: Int32, y: Int32, z: Int32
        public var orientation: UInt16
    }

    public enum ActorKind: UInt8, Sendable { case local = 0, player = 1, npc = 2 }

    public struct Actor: Sendable, Equatable {
        public var key: UInt32
        public var kind: ActorKind
        public var x: Int32, y: Int32, z: Int32
        public var orientation: UInt16
        public var meshId: Int64
    }

    public struct Frame: Sendable, Equatable {
        public var tick: UInt32
        public var playerX: Int32, playerY: Int32, playerZ: Int32
        public var playerOrientation: UInt16, cameraYaw: UInt16
        public var plane: UInt8
        public var actors: [Actor]
    }

    public enum Message: Sendable, Equatable {
        case hello(radius: Int32)
        case reset(baseX: Int32, baseY: Int32, plane: UInt8)
        case mesh(Mesh)
        case terrain([Tile])
        case staticAdd([Instance])
        case staticRemove([Int64])
        case frame(Frame)
        case inputAck(InputAck)
        case uiFrame(UIFrame)
        case container(Container)
        case itemIcon(itemId: Int32, png: Data)
        case equipModel(slot: UInt8, itemId: Int32, meshId: Int64)
        /// Open game right-click menu, rows top to bottom; empty rows = closed.
        case menu(Menu)
    }

    public struct MenuRow: Sendable, Equatable {
        public var option: String, target: String
        public init(option: String, target: String) { self.option = option; self.target = target }
    }

    public struct Menu: Sendable, Equatable {
        public var seq: UInt32
        public var rows: [MenuRow]
        public init(seq: UInt32, rows: [MenuRow]) { self.seq = seq; self.rows = rows }
    }

    /// Headset to plugin: left click row `index` (top = 0) of open menu `menuSeq`.
    public static func encodeMenuSelect(seq: UInt32, menuSeq: UInt32, index: UInt8) -> Data {
        var w: [UInt8] = [0x53, 0x52, version, 67]
        for v in [seq, menuSeq] { for i in 0..<4 { w.append(UInt8((v >> (8 * UInt32(i))) & 0xFF)) } }
        w.append(index)
        return Data(w)
    }

    public enum ContainerKind: UInt8, Sendable { case inventory = 0, equipment = 1 }

    /// Item container snapshot. Slot i holds ids[i] x quantities[i]; id -1 is empty.
    public struct Container: Sendable, Equatable {
        public var kind: ContainerKind
        public var ids: [Int32]
        public var quantities: [Int32]
        public init(kind: ContainerKind, ids: [Int32], quantities: [Int32]) {
            self.kind = kind; self.ids = ids; self.quantities = quantities
        }
    }

    /// Headset to plugin: click one inventory or equipment slot widget.
    public static func encodeWidgetClick(seq: UInt32, button: Button, container: ContainerKind, slot: UInt8) -> Data {
        var w: [UInt8] = [0x53, 0x52, version, 66]
        for i in 0..<4 { w.append(UInt8((seq >> (8 * UInt32(i))) & 0xFF)) }
        w += [button.rawValue, container.rawValue, slot]
        return Data(w)
    }

    public enum Button: UInt8, Sendable { case left = 0, right = 1 }

    public enum AckResult: UInt8, Sendable {
        case ok = 0, disabled = 1, offscreen = 2, rateLimited = 3, notLoggedIn = 4, widgetHidden = 5, noMenu = 6, unknown = 255
    }

    public struct InputAck: Sendable, Equatable {
        public var seq: UInt32
        public var result: AckResult
        public var canvasX: Int32, canvasY: Int32
    }

    /// Rendered client canvas as JPEG. canvasWidth/Height are game canvas pixels for UI_CLICK.
    public struct UIFrame: Sendable, Equatable {
        public var seq: UInt32
        public var canvasWidth: Int, canvasHeight: Int
        public var jpeg: Data
    }

    /// Headset to plugin: click at a game canvas pixel (interface panel).
    public static func encodeUIClick(seq: UInt32, button: Button, x: Int32, y: Int32) -> Data {
        var w = [UInt8]()
        w.reserveCapacity(17)
        func put32(_ v: UInt32) { for i in 0..<4 { w.append(UInt8((v >> (8 * UInt32(i))) & 0xFF)) } }
        w += [0x53, 0x52, version, 65]
        put32(seq)
        w.append(button.rawValue)
        put32(UInt32(bitPattern: x)); put32(UInt32(bitPattern: y))
        return Data(w)
    }

    /// Headset to plugin: click at a scene-local point (units, OSRS axes: x east, y height down, z north).
    public static func encodeClick(seq: UInt32, button: Button, x: Int32, y: Int32, z: Int32) -> Data {
        var w = [UInt8]()
        w.reserveCapacity(21)
        func put32(_ v: UInt32) { for i in 0..<4 { w.append(UInt8((v >> (8 * UInt32(i))) & 0xFF)) } }
        w += [0x53, 0x52, version, 64]
        put32(seq)
        w.append(button.rawValue)
        put32(UInt32(bitPattern: x)); put32(UInt32(bitPattern: y)); put32(UInt32(bitPattern: z))
        return Data(w)
    }

    public enum DecodeError: Error, Equatable {
        case truncated, badMagic, badVersion(UInt8), unknownType(UInt8)
    }

    public static func decode(_ data: Data) throws -> Message {
        var r = ByteReader(data)
        guard try r.u16() == magic else { throw DecodeError.badMagic }
        let v = try r.u8()
        guard v == version else { throw DecodeError.badVersion(v) }
        let type = try r.u8()
        switch type {
        case 1:
            return .hello(radius: try r.i32())
        case 2:
            return .reset(baseX: try r.i32(), baseY: try r.i32(), plane: try r.u8())
        case 3:
            let id = try r.i64()
            let flags = try r.u8()
            let vc = Int(try r.u32()), fc = Int(try r.u32())
            var verts = [Int16](); verts.reserveCapacity(vc * 3)
            for _ in 0..<(vc * 3) { verts.append(Int16(bitPattern: try r.u16())) }
            var idx = [UInt16](); idx.reserveCapacity(fc * 3)
            for _ in 0..<(fc * 3) { idx.append(try r.u16()) }
            var cols = [UInt32](); cols.reserveCapacity(fc * 3)
            for _ in 0..<(fc * 3) { cols.append(try r.rgb()) }
            let alpha = try r.bytes(fc)
            return .mesh(Mesh(id: id, transient: flags & 1 != 0, vertices: verts, indices: idx, colors: cols, alpha: alpha))
        case 4:
            let n = Int(try r.u32())
            var tiles = [Tile](); tiles.reserveCapacity(n)
            for _ in 0..<n {
                let x = Int(try r.u8()), y = Int(try r.u8()), p = Int(try r.u8())
                let h = [try r.i32(), try r.i32(), try r.i32(), try r.i32()]
                let c = [try r.rgb(), try r.rgb(), try r.rgb(), try r.rgb()]
                tiles.append(Tile(x: x, y: y, plane: p, heights: h, colors: c))
            }
            return .terrain(tiles)
        case 5:
            let n = Int(try r.u32())
            var list = [Instance](); list.reserveCapacity(n)
            for _ in 0..<n {
                list.append(Instance(id: try r.i64(), meshId: try r.i64(), x: try r.i32(), y: try r.i32(), z: try r.i32(), orientation: try r.u16()))
            }
            return .staticAdd(list)
        case 6:
            let n = Int(try r.u32())
            var ids = [Int64]()
            for _ in 0..<n { ids.append(try r.i64()) }
            return .staticRemove(ids)
        case 7:
            let tick = try r.u32()
            let px = try r.i32(), py = try r.i32(), pz = try r.i32()
            let po = try r.u16(), yaw = try r.u16(), plane = try r.u8()
            let n = Int(try r.u32())
            var actors = [Actor](); actors.reserveCapacity(n)
            for _ in 0..<n {
                let key = try r.u32()
                let kind = ActorKind(rawValue: try r.u8()) ?? .npc
                actors.append(Actor(key: key, kind: kind, x: try r.i32(), y: try r.i32(), z: try r.i32(), orientation: try r.u16(), meshId: try r.i64()))
            }
            return .frame(Frame(tick: tick, playerX: px, playerY: py, playerZ: pz, playerOrientation: po, cameraYaw: yaw, plane: plane, actors: actors))
        case 8:
            let seq = try r.u32()
            let res = AckResult(rawValue: try r.u8()) ?? .unknown
            return .inputAck(InputAck(seq: seq, result: res, canvasX: try r.i32(), canvasY: try r.i32()))
        case 9:
            let seq = try r.u32()
            let w = Int(try r.u16()), h = Int(try r.u16())
            let n = Int(try r.u32())
            return .uiFrame(UIFrame(seq: seq, canvasWidth: w, canvasHeight: h, jpeg: Data(try r.bytes(n))))
        case 10:
            let kind = ContainerKind(rawValue: try r.u8()) ?? .inventory
            let n = Int(try r.u32())
            var ids = [Int32](), qty = [Int32]()
            for _ in 0..<n { ids.append(try r.i32()); qty.append(try r.i32()) }
            return .container(Container(kind: kind, ids: ids, quantities: qty))
        case 12:
            return .equipModel(slot: try r.u8(), itemId: try r.i32(), meshId: try r.i64())
        case 11:
            let id = try r.i32()
            let n = Int(try r.u32())
            return .itemIcon(itemId: id, png: Data(try r.bytes(n)))
        case 13:
            let seq = try r.u32()
            let n = Int(try r.u8())
            var rows = [MenuRow]()
            func str() throws -> String { String(decoding: try r.bytes(Int(try r.u16())), as: UTF8.self) }
            for _ in 0..<n { rows.append(MenuRow(option: try str(), target: try str())) }
            return .menu(Menu(seq: seq, rows: rows))
        default:
            throw DecodeError.unknownType(type)
        }
    }
}

struct ByteReader {
    private let bytes: [UInt8]
    private var pos = 0
    init(_ data: Data) { bytes = [UInt8](data) }

    mutating func u8() throws -> UInt8 {
        guard pos < bytes.count else { throw RSProtocol.DecodeError.truncated }
        defer { pos += 1 }
        return bytes[pos]
    }
    mutating func u16() throws -> UInt16 {
        guard pos + 2 <= bytes.count else { throw RSProtocol.DecodeError.truncated }
        defer { pos += 2 }
        return UInt16(bytes[pos]) | UInt16(bytes[pos + 1]) << 8
    }
    mutating func u32() throws -> UInt32 {
        guard pos + 4 <= bytes.count else { throw RSProtocol.DecodeError.truncated }
        var v: UInt32 = 0
        for i in 0..<4 { v |= UInt32(bytes[pos + i]) << (8 * UInt32(i)) }
        pos += 4
        return v
    }
    mutating func i32() throws -> Int32 { Int32(bitPattern: try u32()) }
    mutating func i64() throws -> Int64 {
        let lo = UInt64(try u32()), hi = UInt64(try u32())
        return Int64(bitPattern: lo | hi << 32)
    }
    mutating func rgb() throws -> UInt32 {
        let r = UInt32(try u8()), g = UInt32(try u8()), b = UInt32(try u8())
        return r << 16 | g << 8 | b
    }
    mutating func bytes(_ n: Int) throws -> [UInt8] {
        guard pos + n <= bytes.count else { throw RSProtocol.DecodeError.truncated }
        defer { pos += n }
        return Array(bytes[pos..<pos + n])
    }
}
