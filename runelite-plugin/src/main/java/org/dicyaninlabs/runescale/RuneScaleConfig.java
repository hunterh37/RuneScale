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

	@ConfigItem(keyName = "token", name = "", description = "", hidden = true)
	default String token() { return ""; }
}
