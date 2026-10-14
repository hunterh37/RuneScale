# Input UX plan (2026-10-14)

Translation of OSRS click input to Apple Vision Pro. Every headset action resolves to the same
mouse/keyboard events a player would send for that action: one gesture, one click (or one click
plus one menu row). Rules position in notes/ROADMAP.md applies to every scheme below.

## What OSRS input needs

| Need | Desktop form | Rate |
|---|---|---|
| Left click top action | click on world, item, widget | 1 per tick (600 ms) common, more in PvM |
| Right click menu | open menu, pick row | several per minute |
| Hover text | top-left action text under cursor | continuous |
| Item on target (Use) | click item, click target | skilling, quests |
| Spell on target | click spell, click target | combat, alching |
| Tab switching | F-keys / tab stones | prayer swaps, inventory, spellbook |
| Prayer toggles | click prayer icon | 1-tick flicking needs 2 clicks per tick |
| Inventory rearrange | drag | rare |
| Camera | arrow keys, middle drag, scroll zoom | continuous |
| Text | chat, bank search, withdraw-X, GE search | occasional |
| Shift-drop, modifiers | shift + click | skilling |

Game tick is 0.6 s (runescape.wiki Tick_manipulation). Prayer drain applies at end of tick, so
on/off within a tick keeps the prayer (Pray flick). Input latency over ~150 ms costs ticks in PvM;
LAN budget stays 80 ms (M5).

## Platform inputs

| Input | visionOS access | Precision | Notes |
|---|---|---|---|
| Look + pinch | `SpatialTapGesture`, hover effects | high | Apps get no gaze vector; only the tap location and system hover highlight |
| Direct touch | `SpatialTapGesture` on near entities | high | Fingertip within reach of a collider |
| Hand skeleton | `HandTrackingProvider`, ImmersiveSpace only | medium | 27 joints, ~90 Hz; fails out of camera view |
| PS VR2 Sense | visionOS 26, GameController + `AccessoryTrackingProvider` | high | 6DoF, buttons, sticks, finger touch, rumble; no adaptive triggers (UploadVR, Road to VR) |
| Gamepad | GameController | n/a | Sticks for camera and menu |
| Keyboard / trackpad | Bluetooth, Mac Virtual Display | high | Fallback for text and power users |
| Voice | Speech framework | low | One phrase = one menu row of an already opened menu |

Gaze is private on visionOS. Hover text (desktop top-left action) cannot follow gaze directly;
the system hover effect can show a highlight but the app does not learn which entity is looked at
until the pinch. Hover text therefore comes from the hand ray, controller ray, or after tap.

## Input schemes

Three schemes share one intent layer (`IntentMapper`) and one protocol (CLICK, UI_CLICK,
WIDGET_CLICK, MENU_SELECT). Setting `Input scheme` picks one; mixed use allowed.

### A. Look and pinch (default, seated or standing)

- Pinch on terrain = walk here. Pinch on NPC/object/item = top action (left click).
- Pinch-hold 350 ms = right click. MENU stream opens a ring menu around the target (see Menus).
- Hover text: after a pinch-hold starts, the ring shows the menu options; for left-click preview
  the plugin returns the top option in INPUT_ACK so the tap flashes its action label ("Attack
  Goblin (level-2)") at the hit point.
- Tiny targets (ground items in a pile, tiles at range): pinch-hold opens the menu, which lists
  every entry on the tile. Same as the desktop right click.
- Zoom-to-pick: second hand pinch-drag scales the world volume around the gaze point
  (tabletop) to enlarge small targets before tapping. Scaling is headset only, no game input.

### B. Hand tracking direct (immersive, room scale)

Physical actions bound to one click each. Already partly built (M3.5).

| Gesture | Target | Clicks |
|---|---|---|
| Swing weapon through NPC | attackable NPC | 1 left click on NPC (Attack) |
| Point (index extended) + pinch thumb | anything at ray hit | 1 left click at hit |
| Pinch-hold with point | anything | right click, ring menu |
| Grab (fist) on ground item | item | 1 click (Take top option), checked against MENU top row |
| Grab door/lever/ladder | object | 1 click (top option) |
| Reach behind shoulder + grab | backpack | opens inventory grid (headset only) |
| Pinch item in grid, release over target | item, then target | 2 clicks: Use, then target |
| Pinch item in grid, tap | item | 1 click (Eat/Wield/Drink) |
| Throw item down | item | right click + Drop row |
| Palm up (off hand) | none | spellbook/prayer ring opens (headset only) |
| Pinch spell rune, point at NPC | spell, NPC | 2 clicks |
| Wrist flip on prayer ring | prayer slot | 1 WIDGET_CLICK per flip |
| Look at palm | none | hand menu (side tabs) |

Ranged: bow pose (off hand forward, draw hand back to the cheek, release) = 1 click on the NPC
the arrow points at. Magic: staff point. Melee: swing. All three resolve to the same Attack click
and the game decides the hit; the headset shows the game's hitsplat, never a predicted result.

### C. PS VR2 Sense controllers

For long sessions and PvM, where hands tire and tracking drops at the hip.

| Control | Action |
|---|---|
| Right trigger on ray | left click |
| Right grip | right click (ring menu) |
| Right stick flick on ring | pick menu row |
| Left trigger | Use / modifier (shift) held |
| Left stick | camera yaw/pitch (arrow keys) and zoom |
| Face buttons | F-key tab binds (inventory, prayer, spellbook, equipment) |
| Left Y | hand menu / interface panel |
| Touch sensors | show ray only while finger rests on trigger |
| Rumble | INPUT_ACK ok (short), hitsplat on local player (long) |

Gamepad (no tracking): left stick moves a world cursor on the terrain grid one tile per flick,
A = click, X = right click; panel focus moves with the D-pad.

## Menus

Desktop menus are a vertical list at the cursor. In VR:

- Ring menu: up to 8 options in a ring at the target, top option at 12 o'clock, "Cancel" in the
  center. Pick by gaze + pinch, by hand flick toward the slice (direction past 4 cm), or by stick.
  Over 8 entries (stacked items, crowded tiles) falls back to a scrolling list.
- Option text verbatim from MENU stream; color tags from the game (NPC yellow, item orange).
- Selection sends MENU_SELECT(menuSeq, index). Plugin clicks the row rect in `client.getMenu()`.
  Stale menu (menuSeq mismatch) returns ACK noMenu and the ring closes.
- Research basis: radial vs panel study (IEEE Access 2019) favors radial for small option sets;
  wrist-rotation radial selection (ACM 2023) and Look & Turn (ETRA 2022) support hand-attached
  rings without ray casting.

## Interfaces

| Surface | Placement | Input |
|---|---|---|
| Inventory | backpack grid (B), hand menu, panel | pinch slot = WIDGET_CLICK |
| Prayer | ring on off-hand wrist, quick-prayer orb on panel | pinch / wrist flip |
| Spellbook | palm-up ring, filtered to castable spells | pinch spell |
| Equipment | worn models on body; grab to remove | WIDGET_CLICK group 387 |
| Orbs (HP, prayer, run, spec) | wrist watch on off hand | pinch run/spec/quick-prayer |
| Minimap | tabletop disc at waist; pinch = walk to tile | click minimap pixel |
| Chatbox, dialogs | panel below eye level; dialog options also floating over the NPC | tap or 1-5 keys |
| Bank, shop, GE | large window, native grid from widget stream | pinch slot, ring menu for X |
| XP drops, hitsplats, overheads | world-space at the actor | read only |

Full canvas panel (UI_FRAME) stays as fallback for any widget not mirrored natively.

## Camera and locomotion

The game's 3D camera only matters for projection hits; the headset view is independent.

- Offscreen target: plugin clicks the minimap tile for walk, else rotates the game camera with
  arrow keys until the point projects inside the viewport, then clicks (M1 open item).
- Room scale (life size): the user stands on the player tile; the world slides when the player
  walks (no headset locomotion). Comfort: vignette during slides over 1 tile/tick, snap option.
- Tabletop: world is a diorama; pinch-drag pans, two-hand scale zooms. No game input.
- Follow mode: tabletop recenters on the player each tick.

## Text

Chat and numeric entry use the system keyboard in a floating field; each character becomes a
KEY event on the canvas. Withdraw-X shows a numeric pad with quick values (1, 5, 10, X, All).
Voice dictation fills the same field; the user taps Send. No voice commands that pick targets.

## Feedback

- Tap acknowledgment: spatial click sound + ring at the hit point; red ring on ACK error.
- Action label from INPUT_ACK top option at the tap point for 0.8 s.
- Tick metronome option (subtle) for prayer flicking.
- Hitsplats and HP bars from the game only. No predictions, no indicators the client does not draw.

## Accessibility and comfort

- Seated mode: all actions reachable within 60 cm; backpack and hand menu move to the lap.
- One-hand mode: hand menu on the same hand, pinch-hold replaces two-hand actions.
- Tap-only mode: disables swing, grab and throw; scheme A only.
- Left-handed swap. Swing sensitivity 1.0 to 2.5 m/s. Pinch-hold 250 to 600 ms.
- Sessions: hand tracking scheme B is fatiguing over 20 min; prompt nothing, but default PvM to C.

## Rules check per scheme

| Item | Clicks per gesture | Status |
|---|---|---|
| Pinch / trigger | 1 | same as mouse |
| Ring menu row | 1 (right click already sent) | same as menu |
| Swing / bow / staff | 1 | review: physical motion, 1 click |
| Use-drag | 2 (item, target) | review: one gesture, two clicks |
| Spell-point | 2 | same as Use-drag |
| Drop throw | 2 (right click, row) | review |
| Prayer wrist flip | 1 | same as click |

Rows marked review need a decision before any public build (ROADMAP open question 3). Option:
split 2-click gestures into two separate physical events (pinch item, then pinch target).

## Sources

uploadvr.com/visionos-26-out-now-apple-vision-pro; roadtovr.com/vision-pro-psvr-2-controller-logitech-muse-visionos-26;
runescape.wiki/w/Tick_manipulation; oldschoolrunescape.fandom.com/wiki/Pray_flick;
repositorio.inesctec.pt (Radial and Panel Menus in VR, IEEE Access 2019);
doi 10.1145/3625008.3625022 (wrist radial menus); mmi.ifi.lmu.de reiter2022etra (Look & Turn);
roadtovr.com/design-implementation-of-hand-tracking-in-myst-oculus-quest.
