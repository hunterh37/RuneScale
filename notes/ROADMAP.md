# RuneScale roadmap

Goal: full play of OSRS from Apple Vision Pro. Headset gestures drive the character through real
mouse and keyboard input on the RuneLite canvas; the headset shows the 3D scene plus every
interface (inventory, equipment, prayer, spells, chat, dialogs, bank).

Status keys: `[x]` done, `[~]` claimed / in progress, `[ ]` open.

## Rules position

Headset input sends clicks that a human triggers one at a time (one tap, one click), the same model
as a remote desktop. No automation, no queued or repeated actions, no new menu actions. Plugins that
send input are not accepted on the Plugin Hub, so headset input lives behind the `remoteInput`
config flag (default off) and runs in developer mode. Account risk on sideloaded plugins stays as
written in notes/RESEARCH.md. A Hub-eligible build ships with the flag compiled out (M6).

## M0 Read-only stream (done, 3da7193)

- [x] Scene geometry, terrain, actors over LAN WebSocket, Bonjour, pairing token
- [x] Room-scale immersive and tabletop volume

## M1 Click input (claimed)

- [x] Protocol: CLICK (64, headset to plugin) and INPUT_ACK (8), notes/PROTOCOL.md
- [x] Plugin: `RemoteInput` projects the tapped 3D point with `Perspective.localToCanvas`,
      rejects points outside the viewport, maps stretched mode, dispatches
      moved/pressed/released/clicked `MouseEvent`s on `client.getCanvas()`; 100 ms rate floor
- [x] Plugin config `Headset input` (default off, warning dialog)
- [x] Headset: tap colliders (terrain exact mesh, objects and actors box), `SpatialTapGesture`
      converts the hit to scene units, toggle and last-ACK readout in the connect window
- [x] Tests: ProtocolTest click/ack/truncation/stretch (7/7), RSProtocolTests (8/8)
- [~] Live verification: walk-here on terrain, attack NPC, talk-to, open door, take ground item
- [~] Offscreen fallback: when the tapped point is outside the game camera view, rotate the game
      camera toward it (arrow-key events) or click the minimap at the tile; pick after live test
- [~] Camera sync: plugin sets nothing; headset reports which way it faces so the user can point the
      game camera to match (keeps projection hits on screen)

## M2 Menu and right click

- [ ] Long-press or pinch-hold = right click; stream the opened menu (`MenuOpened` entries,
      option + target text) to the headset
- [ ] Headset shows the menu as a floating SwiftUI list at the tap point; selecting an entry
      clicks the matching row on the canvas (canvas rect from `client.getMenu()` bounds)
- [ ] Hover feedback: mouse-move on gaze/hover so the top-left action text matches the target
- [ ] Shift-click and modifier keys (key events on the canvas)

## M3 Interface mirroring

- [ ] Widget stream: snapshot of visible widget roots (inventory 149, equipment 387, prayer 541,
      spellbook 218, combat 593, skills 320, chatbox 162, minimap orbs) as rects, sprites, item ids,
      quantities, text; diff per game tick
- [ ] Sprite and item icon transfer: `ItemManager.getImage` / `SpriteManager` PNGs, cached by id
- [ ] Headset UI: inventory 4x7 grid window, side tab bar, orbs (HP, prayer, run, spec)
- [ ] Widget click: tap a slot sends WIDGET_CLICK (group, child, slot); plugin clicks the widget
      bounds center on the canvas (requires the tab open; plugin presses the tab hotkey first)
- [x] Full interface panel: plugin streams the rendered canvas as JPEG UI_FRAME
      (`InterfaceCapture`, `DrawManager.requestNextFrameListener`, 10 fps, 1280 px); every tab,
      chatbox, minimap, orbs, dialogs and bank visible on the headset
- [x] Interface click input: panel tap sends UI_CLICK (canvas pixel), plugin dispatches on the
      canvas; Right click toggle makes the next tap a right click (game menu opens in the panel)
- [x] Tabletop: panel attachment on the volume front edge, tilted toward the viewer
- [x] Life scale: panel anchored 0.7 m in front of the user below eye level from the device pose
      (`WorldTrackingProvider`), Recenter button re-anchors
- [ ] Live verification: tab switching, inventory item use, prayer toggle, dialog continue
- [ ] H.264 (VideoToolbox) instead of JPEG if bandwidth over 1 MB/s matters
- [ ] Item drag (inventory rearrange): press, move, release sequence

## M3.5 Hand tracking gestures (VR feel over click input)

OSRS stays click based. Each physical gesture resolves to exactly one click (or one click plus one
menu-row click) that the same gesture would need with a mouse; the plugin protocol stays CLICK,
UI_CLICK, WIDGET_CLICK. Gestures pick the target; the game decides the outcome (attack speed,
pathing, hit roll). No gesture sends repeated or timed clicks.

- [x] `HandTrackingProvider` session in the ImmersiveSpace (`NSHandsTrackingUsageDescription`),
      joint poses per frame, fallback to `SpatialTapGesture` when tracking is lost or denied
- [x] `GestureRecognizer` (Core, unit-tested on recorded joint traces): pinch, pinch-hold, grab
      (all fingertips to palm), release, point (index extended ray), swing (wrist speed over
      1.5 m/s along an arc), palm-up, two-hand pinch; hysteresis and 250 ms debounce
- [~] `IntentMapper`: swing to Attack done (blade-path hit, then 25 degree aim cone); pinch-hold and
      grab-to-Take open. Gesture + target to one action. Swing through or toward an NPC collider =
      one left click on that NPC (Attack); point + pinch = click at ray hit; pinch-hold = right
      click and menu (M2); grab on ground item = Take; grab on door/lever = top action
- [ ] Target resolution: swing hit volume (capsule along the blade path), nearest attackable NPC
      by angle, cancel when the top menu option is not Attack (needs MENU stream, M2)
- [x] Held weapon model: equipped weapon mesh (from equipment widget item id, M3 sprite/model
      transfer) parented to the hand anchor; sword, bow, staff poses
- [ ] Combat feedback: hand haptic substitute (spatial click sound), hit flash on the NPC from
      HITSPLAT/actor events, swing trail; game attack cooldown shown as a ring on the weapon
- [x] Backpack: 3D bag anchored over the shoulder/hip (body anchor from device pose), reach behind
      plus grab opens a 4x7 spatial inventory grid from the widget stream (M3, group 149)
- [ ] Backpack actions: pinch an item = WIDGET_CLICK slot (eat, wield, drink); drag item onto an
      NPC/object/item = Use (two clicks: item, then target); drop out of hand = Drop via menu row
- [x] Worn models: EQUIP_MODEL streams inventory models per slot; `EquipmentRig` puts the weapon in
      the sword hand, shield in the off hand, gloves on both hands, amulet/body/cape/legs/boots from the
      head pose (`BodyLayout`), helm hidden. Model axis alignment needs live tuning per item
- [~] Backpack slot tap = WIDGET_CLICK (inventory and equipment, tab must be open; ACK 5 otherwise)
- [ ] Equipment on body: helm at head, shield on off-hand; grab to remove = WIDGET_CLICK on
      equipment group 387
- [ ] Spells: palm-up summons spellbook ring, pinch a rune icon then point at target = cast
      (spell widget click, then target click); prayer ring on the off-hand wrist
- [ ] Locomotion: point at ground + pinch = walk here; teleport-style arc preview of the tile
- [ ] Settings: handedness, gesture set toggles, swing sensitivity, tap-only mode
- [x] Tests: GestureRecognizerTests on recorded traces, IntentMapperTests (gesture to click count)
- [ ] Live verification: swing kills a chicken, eat food from backpack, wield from backpack,
      use item on object, cast Wind Strike by gesture

Dependencies: M2 menu stream (top option check, menu rows), M3 widget stream (item ids, slots,
WIDGET_CLICK), equipped item model export (M5 textures).

## M4 Dialogs, bank, chat, keyboard

- [ ] NPC dialog / options (widget groups 231, 217, 219) as headset panels, tap or number key
- [ ] Bank, shop, GE: scrollable item grids, withdraw-X numeric entry
- [ ] Chat: visionOS keyboard text field sends key events; public/clan/private tabs read-only first
- [ ] Hotkeys row: F-keys, space, escape, number keys

## M5 Play feel

- [ ] Latency budget: tap to click under 80 ms LAN; measure with ACK round trip
- [ ] Hit marks, overhead text, HP bars, projectiles as headset overlays (only what the game draws)
- [ ] Actor animation via pose mesh caching (bandwidth), textures, roofs, transparency
- [ ] Indoor plane culling and bridges
- [ ] Spatial audio from game sound effects (plugin forwards sound ids)
- [ ] Game camera follows headset yaw option

## M6 Distribution

- [ ] Hub-eligible flavor: input code excluded at build time
- [ ] Dev-mode flavor with input; install guide
- [ ] TestFlight build of RuneScale (org.oldschool.runescape.runescale)

## Open questions

3. Gesture-to-click mapping must keep one human action per click (Jagex third-party rules); review
   swing and Use-drag against the rules position before any public build.

1. `dispatchEvent` on the canvas vs `java.awt.Robot`: canvas events work with the window unfocused;
   confirm the game accepts them on macOS (live test in M1).
2. Fixed vs resizable mode viewport offsets; verify `getViewportXOffset` in each.
