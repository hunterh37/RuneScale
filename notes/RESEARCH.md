# Research notes (2026-10-13)

## Prior art for reading geometry

- RuneLite GPU plugin (`runelite-client/src/main/java/net/runelite/client/plugins/gpu`) uploads scene tiles and models every frame. It reads `SceneTilePaint` (four corner HSL colors, `12345678` = hidden tile), `SceneTileModel` (vertex X/Y/Z, face X/Y/Z, triangle color A/B/C), and `Model` vertex arrays, face indices and face colors. `faceColors3 == -1` means flat shaded with `faceColors1`; `faceColors3 == -2` means the face is not drawn. Models are rotated by orientation (0..2047, 2048 = full turn) around the vertical axis at draw time.
- 117 HD (rlhd) extends the same path with its own scene uploader and model cache keyed by model hash. It shows that caching static geometry by content/identity and streaming only dynamic actor models per frame is workable at RuneLite frame rates. Its source has no public write-up of the upload path; behavior above comes from the GPU plugin it forked.
- Jagex HSL is packed 16-bit: hue 6 bits, saturation 3 bits, lightness 7 bits (OSRS wiki, Colour Customiser). Model face colors are already lit, so an unlit material reproduces the game look.
- RuneLite API 1.13.1 (resolved by Gradle here) exposes `Mesh.getVerticesX/Y/Z()` as `float[]`, `getFaceIndices1/2/3()`, `Model.getFaceColors1/2/3()`, `getFaceTransparencies()`, `WorldView.players()/npcs()`, `TileObject.getZ()` (tile height), `GameObject.getModelOrientation()`.
- Model export: ConnorDY's OSRS-Environment-Exporter exports regions from the cache to Blender. It reads the cache directly, which this project avoids. Plugin Hub has model-export style plugins that read `Model` from the live client; same read path as here.
- VR/AR: no maintained OSRS VR or AR project found. No RuneLite plugin streams geometry to a headset.

## Rules

- Jagex Third Party Client Guidelines: approved clients include RuneLite. Prohibited features include boss-fight aids (next-attack prediction, projectile/impact locations, prayer-switch indicators, automatic tile indicators), menu changes that send new actions to the server, and some PvP/Construction menu changes. Automation and input injection are bannable under the game rules.
- RuneLite Plugin Hub: third-party plugins are reviewed by RuneLite developers for game rules and safety before listing. Plugins must not automate, inject input, or reveal hidden information. Network access and bundled dependencies are reviewed; extra dependencies (Java-WebSocket, jmDNS) need justification and may be rejected.

## Design inside the rules

- Read-only: the plugin calls getters on the client thread, never mutates client state, adds no menu entries, sends no input, draws no overlays.
- The headset sends nothing back. `StreamServer.onMessage` ignores inbound data. The visionOS client never writes to the socket.
- Information shown is what the game already renders around the player at the same radius. No hidden information (no projectile prediction, no indicators).
- LAN only: connections from non-local addresses are closed; pairing token required. Personal use.

## Legal path and risk

- Plugin Hub submission is the supported path for normal accounts. Running an unreviewed plugin requires RuneLite developer mode (`--developer-mode`, sideloading), meant for development. Sideloaded plugins are outside RuneLite review; use on a main account carries account risk if Jagex or RuneLite considers the plugin non-compliant.
- Risk items for Hub review: opening a listening socket, Bonjour multicast, and bundled jars. Fallback if rejected: drop jmDNS (manual IP only).
- No cache or asset redistribution: geometry exists only in memory on the user's own Mac and headset during a session.

## Relay decision

No Mac relay app. The plugin runs on the same Mac and can serve WebSocket directly on the LAN. A relay would only be needed if Plugin Hub rejects in-plugin server sockets; then a small local Mac process would accept a loopback connection from the plugin and serve the headset.

Sources: oldschool.runescape.wiki/w/Update:Third_Party_Client_Guidelines, oldschool.runescape.wiki/w/RuneLite, static.runelite.net/runelite-api/apidocs, runescape.wiki/w/Colour_Customiser, github.com/ConnorDY (OSRS-Environment-Exporter), github.com/runelite/runelite (gpu plugin), github.com/117HD/RLHD.
