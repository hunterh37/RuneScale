package org.oldschool.runescape.runescale;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotEquals;
import org.junit.Test;

public class TextureColorsTest
{
	@Test
	public void averageSkipsTransparent()
	{
		assertEquals(0x204060, TextureColors.average(new int[]{0, 0x103050, 0x305070, 0}));
		assertEquals(-1, TextureColors.average(new int[]{0, 0}));
	}

	@Test
	public void shadeScalesByLightness()
	{
		assertEquals(0x406020, TextureColors.shade(0x406020, 127));
		assertEquals(0x1F2F0F, TextureColors.shade(0x406020, 63));
		assertEquals(0, TextureColors.shade(0xFFFFFF, 0));
	}

	@Test
	public void texturedFaceIsNotLightnessGray()
	{
		// lightness-only color 100: as HSL it is near-white gray; textured it is shaded fallback
		int raw = JagexColor.toRgb(100);
		int textured = SceneCapture.faceRgb(100, 5, null);
		assertNotEquals(raw, textured);
		assertEquals(TextureColors.shade(TextureColors.FALLBACK, 100), textured);
		assertEquals(raw, SceneCapture.faceRgb(100, -1, null));
	}

	@Test
	public void buildUsesFaceTextures()
	{
		Protocol.Mesh m = SceneCapture.build(3, 2,
			new float[]{0, 128, 0}, new float[]{0, 0, 0}, new float[]{0, 0, 128},
			new int[]{0, 0}, new int[]{1, 1}, new int[]{2, 2},
			new int[]{0x1234, 90}, new int[]{0, 0}, new int[]{-1, -1},
			null, 0, new short[]{-1, 7}, null);
		assertEquals(2, m.faceCount());
		assertEquals(JagexColor.toRgb(0x1234), m.colors[0]);
		assertEquals(TextureColors.shade(TextureColors.FALLBACK, 90), m.colors[3]);
	}
}
