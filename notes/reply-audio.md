# Audio system

Plugin (Stream audio, on by default) forwards SoundEffectPlayed and AreaSoundEffectPlayed as SOUND (16) and the
Music tab title as MUSIC (17). Mute client sound effects consumes the events so they play on the headset only.

Headset: App/AudioSystem.swift. Game effects play through RealityKit SpatialAudioComponent on the source actor, or on
the scene point for area sounds, with rolloff scaled to the game range. Spatial audio off falls back to AVAudioEngine
stereo with the OSRS linear area falloff. Music loops head-locked and crossfades over 1.5 s on track change.
Interface sounds play on tab, tap, backpack open/close and failed click acks.

Settings window, Audio section: Sound, Music + volume, Sound effects + volume, Spatial audio, Interface sounds.
Hand menu: mute button, plus the now-playing title on the Music tab.

Limitation: the client never exposes OSRS PCM or MIDI. Effects are seeded procedural voices per sound id, and music
is a seeded procedural loop per track title (Core/AudioSynth.swift). Real audio needs a port of the OSRS synth and
MIDI player reading cache indices 4, 6 and 15 in the plugin, with PCM sent once per id the same way ITEM_ICON works.

Tests: Tests/AudioTests.swift, 4 pass (40 total). Plugin compileJava BUILD SUCCESSFUL.
