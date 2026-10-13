# RuneScale build status

Commit 3da7193. Not yet run against a live RuneLite session.

Plugin: ./gradlew build passes; ProtocolTest.java 4/4. Gradle 8.11.1, Java 11 target, RuneLite 1.13.1. Read-only: no menu entries, no input, inbound headset data ignored. WebSocket port 43595, LAN only, 6-digit pairing token, Bonjour _runescale._tcp or manual IP.

Vision app: xcodebuild visionOS 26.4 sim succeeds; RSProtocolTests.swift 5/5. Room-scale (1 tile = 1 m, slider) and tabletop modes; actor interpolation.

Docs: notes/RESEARCH.md (rules, Plugin Hub vs dev-mode sideload, risks, no Mac relay needed), notes/PROTOCOL.md, README.md.

Open gaps:
1. Rotation direction, wall/decoration placement, tile-model coordinates unverified on live data.
2. Flat per-triangle color via 128x128 palette texture; transparent faces dropped; textures and roofs unhandled.
3. Each actor pose sent as a new mesh; bandwidth and device frame rate unmeasured.
4. Upper planes can occlude the player indoors; bridges ignored.
5. Plugin Hub may reject the open port or bundled Java-WebSocket/jmDNS; fallback is manual IP only.
6. No public OSRS VR/AR prior art found; 117 HD model loading not documented in search results.

Paths: runelite-plugin/src/main/java/org/oldschool/runescape/runescale/, RuneScaleVision/{Core,App,Tests}/.
