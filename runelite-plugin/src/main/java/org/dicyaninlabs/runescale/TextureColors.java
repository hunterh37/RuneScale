package org.oldschool.runescape.runescale;

import java.util.Arrays;
import net.runelite.api.TextureProvider;

/**
 * Average color per texture id. Textured faces carry only a lightness value (0..127) in their
 * HSL color, so converting that value directly gives white or gray. The headset has no texture
 * atlas; each textured face is drawn as the texture's average color scaled by that lightness.
 */
class TextureColors
{
	/** Used when a texture id is unknown or not loaded. */
	static final int FALLBACK = 0x808080;
	private static final int UNKNOWN = -1;

	private final TextureProvider provider;
	private final int[] cache = new int[512];

	TextureColors(TextureProvider provider)
	{
		this.provider = provider;
		Arrays.fill(cache, UNKNOWN);
	}

	/** Average RGB of texture {@code id}. Client thread only. */
	int average(int id)
	{
		if (id < 0) return FALLBACK;
		if (id < cache.length && cache[id] != UNKNOWN) return cache[id];
		int rgb = FALLBACK;
		boolean loaded = false;
		try
		{
			int[] px = provider == null ? null : provider.load(id);
			if (px != null)
			{
				int avg = average(px);
				if (avg >= 0)
				{
					rgb = avg;
					loaded = true;
				}
			}
		}
		catch (RuntimeException ignored)
		{
			// bad id or texture not in cache
		}
		if (loaded && id < cache.length) cache[id] = rgb;
		return rgb;
	}

	/** Mean of the non-transparent pixels (0 is transparent), or -1 when all are transparent. */
	static int average(int[] pixels)
	{
		long r = 0, g = 0, b = 0;
		int n = 0;
		for (int p : pixels)
		{
			if ((p & 0xFFFFFF) == 0) continue;
			r += (p >> 16) & 0xFF;
			g += (p >> 8) & 0xFF;
			b += p & 0xFF;
			n++;
		}
		if (n == 0) return -1;
		return (int) (r / n) << 16 | (int) (g / n) << 8 | (int) (b / n);
	}

	/** Texture color under the face lightness (low 7 bits of the face color), as the GPU plugin does. */
	static int shade(int rgb, int faceColor)
	{
		int l = faceColor & 127;
		int r = ((rgb >> 16) & 0xFF) * l / 127;
		int g = ((rgb >> 8) & 0xFF) * l / 127;
		int b = (rgb & 0xFF) * l / 127;
		return r << 16 | g << 8 | b;
	}
}
