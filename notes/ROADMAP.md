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
- [ ] Fallback: mirrored canvas video (ScreenCaptureKit on the Mac, low-latency H.264) as a flat
      panel for interfaces not yet native
- [ ] Item drag (inventory rearrange): press, move, release sequence

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

1. `dispatchEvent` on the canvas vs `java.awt.Robot`: canvas events work with the window unfocused;
   confirm the game accepts them on macOS (live test in M1).
2. Fixed vs resizable mode viewport offsets; verify `getViewportXOffset` in each.
