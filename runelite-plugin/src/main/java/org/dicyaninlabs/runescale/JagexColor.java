package org.oldschool.runescape.runescale;

/** Converts packed 16-bit Jagex HSL (6 bit hue, 3 bit saturation, 7 bit lightness) to 24-bit RGB. */
public final class JagexColor
{
	private static final int[] TABLE = new int[65536];

	static
	{
		for (int i = 0; i < 65536; i++)
		{
			TABLE[i] = compute(i);
		}
	}

	private JagexColor() { }

	public static int toRgb(int hsl)
	{
		return TABLE[hsl & 0xFFFF];
	}

	static int compute(int hsl)
	{
		double h = ((hsl >> 10) & 63) / 64.0 + 0.0078125;
		double s = ((hsl >> 7) & 7) / 8.0 + 0.0625;
		double l = (hsl & 127) / 128.0;
		double r = l, g = l, b = l;
		if (s != 0)
		{
			double q = l < 0.5 ? l * (1 + s) : l + s - l * s;
			double p = 2 * l - q;
			r = hue(p, q, h + 1.0 / 3);
			g = hue(p, q, h);
			b = hue(p, q, h - 1.0 / 3);
		}
		int ri = clamp((int) (r * 256)), gi = clamp((int) (g * 256)), bi = clamp((int) (b * 256));
		return (ri << 16) | (gi << 8) | bi;
	}

	private static double hue(double p, double q, double t)
	{
		if (t < 0) t += 1;
		if (t > 1) t -= 1;
		if (6 * t < 1) return p + (q - p) * 6 * t;
		if (2 * t < 1) return q;
		if (3 * t < 2) return p + (q - p) * (2.0 / 3 - t) * 6;
		return p;
	}

	private static int clamp(int v)
	{
		return v < 0 ? 0 : Math.min(255, v);
	}
}
