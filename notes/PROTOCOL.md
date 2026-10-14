# RuneScale Stream protocol v1

Transport: WebSocket, binary frames, one message per frame. Types 1-9 plugin to headset; 64-65 headset to plugin.
Connect to `ws://<mac-ip>:43595/?token=<6 digits>` or send header `X-RuneScale-Token`.
Bonjour type `_runescale._tcp`. All integers little-endian.

Header (4 bytes): `u16 magic 0x5253`, `u8 version 1`, `u8 type`.

| Type | Name | Body |
|---|---|---|
| 1 | HELLO | `i32 radius` |
| 2 | RESET | `i32 baseX, i32 baseY, u8 plane`. Drop all state. |
| 3 | MESH | `i64 id, u8 flags (1 = transient), u32 vcount, u32 fcount, vcount x (i16 x,y,z), fcount x (u16 a,b,c), fcount x 3 x (u8 r,g,b), fcount x u8 alpha` |
| 4 | TERRAIN | `u32 n`, n x (`u8 sceneX, u8 sceneY, u8 plane, 4 x i32 height (sw,se,ne,nw), 4 x rgb`) |
| 5 | STATIC_ADD | `u32 n`, n x (`i64 instanceId, i64 meshId, i32 x, i32 height, i32 z, u16 orientation`) |
| 6 | STATIC_REMOVE | `u32 n`, n x `i64 instanceId` |
| 8 | INPUT_ACK | `u32 seq, u8 result (0 ok, 1 input disabled, 2 offscreen, 3 rate limited, 4 not logged in), i32 canvasX, i32 canvasY` |
| 9 | UI_FRAME | `u32 seq, u16 canvasW, u16 canvasH, u32 len, len x u8` JPEG of the rendered client canvas |
| 10 | CONTAINER | `u8 kind (0 inventory, 1 equipment), u32 n`, n x (`i32 itemId (-1 empty), i32 qty`) |
| 11 | ITEM_ICON | `i32 itemId, u32 len, len x u8` PNG, sent once per id per connection before first use |
| 12 | EQUIP_MODEL | `u8 slot (EquipmentInventorySlot idx), i32 itemId, i64 meshId (0 empty)`; MESH precedes |
| 66 | WIDGET_CLICK (headset to plugin) | `u32 seq, u8 button, u8 container, u8 slot`; ACK 5 = widget hidden (tab closed) |
| 65 | UI_CLICK (headset to plugin) | `u32 seq, u8 button, i32 x, i32 y` game canvas pixels |
| 64 | CLICK (headset to plugin) | `u32 seq, u8 button (0 left, 1 right), i32 x, i32 height, i32 z` scene-local units |
| 7 | FRAME | `u32 tick, i32 px, i32 pheight, i32 pz, u16 playerOrientation, u16 cameraYaw, u8 plane, u32 n`, n x (`u32 key, u8 kind (0 local,1 player,2 npc), i32 x, i32 height, i32 z, u16 orientation, i64 meshId`) |

Coordinates are scene-local units (128 per tile). x east, z north, height positive downward
(OSRS convention). Mesh vertices are model units with the same axes. Instance ids below zero
are terrain tile models whose vertices are already scene-local (place at origin).
Mesh ids are FNV-1a 64 over vertices, indices, colors, alpha and flags. A MESH always precedes
the first STATIC_ADD or FRAME that references it. Static meshes live until RESET; transient
(actor pose) meshes may be evicted by the client (LRU 800).

Cadence: HELLO + RESET + full scene on each new connection; static diff every N game ticks
(default 5); FRAME at ~25 Hz from ClientTick.

Headset mapping: RealityKit = (x, -height, -z) / 128 meters per tile at life size 1.0.
Orientation o maps to yaw `-o * 2pi / 2048` about +Y. Winding is preserved (180 degree turn about X).

Input: CLICK is accepted only when the plugin option Headset input is on. The plugin projects the
point with `Perspective.localToCanvas`, drops it if outside the viewport, and dispatches one
press/release/click on the canvas. Minimum 100 ms between clicks. Every CLICK gets one INPUT_ACK.

Interface: UI_FRAME carries the whole rendered canvas (side tabs, chatbox, minimap, orbs, dialogs,
bank) at up to `Interface FPS` (default 10), scaled to `Interface width` (default 1280), one frame in
flight. canvasW/H are game canvas pixels; the headset maps a panel tap to those pixels and sends
UI_CLICK. UI_CLICK uses the same Headset input gate, 100 ms floor and INPUT_ACK (2 = outside canvas).

Recording (.rsrec): per message `u32 length` then the message bytes, plugin to headset types only.
Textured faces: color is lightness only; the plugin sends texture average RGB scaled by lightness / 127.
