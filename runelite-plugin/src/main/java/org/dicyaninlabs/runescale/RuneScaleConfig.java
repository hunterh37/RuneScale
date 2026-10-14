package org.oldschool.runescape.runescale;

import net.runelite.client.config.Config;
import net.runelite.client.config.ConfigGroup;
import net.runelite.client.config.ConfigItem;
import net.runelite.client.config.Range;

@ConfigGroup(RuneScaleConfig.GROUP)
public interface RuneScaleConfig extends Config
{
	String GROUP = "runescalestream";

	@ConfigItem(keyName = "port", name = "Port", description = "Local WebSocket port", position = 1)
	@Range(min = 1024, max = 65535)
	default int port() { return 43595; }

	@ConfigItem(keyName = "radius", name = "Radius (tiles)", description = "Scene radius streamed around the player", position = 2)
	@Range(min = 4, max = 52)
	default int radius() { return 24; }

	@ConfigItem(keyName = "staticInterval", name = "Static rescan (ticks)", description = "Game ticks between static scene rescans", position = 3)
	@Range(min = 1, max = 50)
	default int staticInterval() { return 5; }

	@ConfigItem(keyName = "bonjour", name = "Advertise via Bonjour", description = "Publish _runescale._tcp on the local network", position = 4)
	default boolean bonjour() { return true; }

	@ConfigItem(keyName = "remoteInput", name = "Headset input",
		description = "Let the paired headset click in the game view (one tap = one click). Developer mode only; not Plugin Hub compliant.",
		position = 5, warning = "Headset taps will send real mouse clicks to the game. Plugins that send input are not allowed on the Plugin Hub. Enable?")
	default boolean remoteInput() { return false; }

	@ConfigItem(keyName = "streamInterface", name = "Stream interface",
		description = "Send the client view (tabs, chat, minimap, dialogs) to the headset as a video panel", position = 6)
	default boolean streamInterface() { return true; }

	@ConfigItem(keyName = "interfaceFps", name = "Interface FPS", description = "Interface panel frames per second", position = 7)
	@Range(min = 1, max = 30)
	default int interfaceFps() { return 10; }

	@ConfigItem(keyName = "interfaceWidth", name = "Interface width (px)", description = "Max width of streamed interface frames", position = 8)
	@Range(min = 320, max = 2560)
	default int interfaceWidth() { return 1280; }

	@ConfigItem(keyName = "recordStream", name = "Record stream",
		description = "Write the scene stream to .runelite/runescale/capture-*.rsrec for headset replay (-replay <path>)", position = 9)
	default boolean recordStream() { return false; }

	@ConfigItem(keyName = "token", name = "", description = "", hidden = true)
	default String token() { return ""; }
}
