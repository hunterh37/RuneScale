package org.oldschool.runescape.runescale;

import net.runelite.client.RuneLite;
import net.runelite.client.externalplugins.ExternalPluginManager;

public class RuneScaleStreamPluginTest
{
	public static void main(String[] args) throws Exception
	{
		ExternalPluginManager.loadBuiltin(RuneScaleStreamPlugin.class);
		RuneLite.main(args);
	}
}
