package org.oldschool.runescape.runescale;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotNull;
import java.util.Arrays;
import java.util.Collections;
import org.junit.Test;

public class ProtocolTest
{
	@Test
	public void meshRoundTrip()
	{
		Protocol.Mesh m = SceneCapture.build(3, 2,
			new float[]{0, 128, 0}, new float[]{0, -64.4f, 0}, new float[]{0, 0, 128},
			new int[]{0, 0}, new int[]{1, 2}, new int[]{2, 1},
			new int[]{0x1234, 0x2000}, new int[]{0x1235, 0}, new int[]{-1, -2},
			new byte[]{0, 0}, 0);
		assertNotNull(m);
		assertEquals(1, m.faceCount()); // hidden face dropped
		Protocol.Decoded d = Protocol.decode(Protocol.mesh(m));
		assertEquals(Protocol.MESH, d.type);
		assertEquals(m.id, d.mesh.id);
		assertArrayEquals(m.vertices, d.mesh.vertices);
		assertEquals(-64, d.mesh.vertices[4]);
		assertArrayEquals(m.indices, d.mesh.indices);
		assertArrayEquals(m.colors, d.mesh.colors);
		assertEquals(m.colors[0], m.colors[1]); // flat shaded face
		assertArrayEquals(m.alpha, d.mesh.alpha);
		assertEquals(m.id, SceneCapture.hash(d.mesh));
	}

	@Test
	public void frameRoundTrip()
	{
		Protocol.Frame f = new Protocol.Frame();
		f.tick = 99; f.playerX = 6400; f.playerY = -240; f.playerZ = 6528; f.playerOrientation = 1536; f.cameraYaw = 2047; f.plane = 1;
		Protocol.Actor a = new Protocol.Actor();
		a.key = 0x10005; a.kind = Protocol.KIND_NPC; a.x = 6000; a.y = -10; a.z = 7000; a.orientation = 512; a.meshId = -42L;
		f.actors.add(a);
		Protocol.Frame g = Protocol.decode(Protocol.frame(f)).frame;
		assertEquals(99, g.tick);
		assertEquals(-240, g.playerY);
		assertEquals(2047, g.cameraYaw);
		assertEquals(1, g.actors.size());
		assertEquals(-42L, g.actors.get(0).meshId);
		assertEquals(0x10005, g.actors.get(0).key);
	}

	@Test
	public void terrainAndStaticRoundTrip()
	{
		Protocol.Tile t = new Protocol.Tile();
		t.x = 103; t.y = 7; t.plane = 2; t.heights = new int[]{-1, -2, -3, -4}; t.colors = new int[]{0xFF0000, 0x00FF00, 0x0000FF, 0xABCDEF};
		Protocol.Tile u = Protocol.decode(Protocol.terrain(Collections.singletonList(t))).tiles.get(0);
		assertEquals(103, u.x);
		assertArrayEquals(t.heights, u.heights);
		assertArrayEquals(t.colors, u.colors);

		Protocol.Instance i = new Protocol.Instance();
		i.id = Long.MAX_VALUE; i.meshId = 7; i.x = 1; i.y = -2; i.z = 3; i.orientation = 2047;
		Protocol.Instance j = Protocol.decode(Protocol.staticAdd(Collections.singletonList(i))).instances.get(0);
		assertEquals(Long.MAX_VALUE, j.id);
		assertEquals(2047, j.orientation);
		assertEquals(Arrays.asList(5L, -9L), Protocol.decode(Protocol.staticRemove(Arrays.asList(5L, -9L))).removed);

		Protocol.Reset r = new Protocol.Reset();
		r.baseX = 3200; r.baseY = 3200; r.plane = 0;
		assertEquals(3200, Protocol.decode(Protocol.reset(r)).reset.baseY);
		assertEquals(24, Protocol.decode(Protocol.hello(24)).radius);
	}

	@Test
	public void jagexColor()
	{
		assertEquals(0, JagexColor.toRgb(0) >> 16);
		int white = JagexColor.toRgb(127);
		assertEquals(true, (white & 0xFF) > 240 && ((white >> 16) & 0xFF) > 240);
	}

	@Test
	public void clickAndAckRoundTrip()
	{
		Protocol.Click c = new Protocol.Click();
		c.seq = 7; c.button = Protocol.BUTTON_RIGHT; c.x = 6464; c.y = -312; c.z = 6592;
		Protocol.Decoded d = Protocol.decode(Protocol.click(c));
		assertEquals(Protocol.CLICK, d.type);
		assertEquals(7, d.click.seq);
		assertEquals(Protocol.BUTTON_RIGHT, d.click.button);
		assertEquals(6464, d.click.x);
		assertEquals(-312, d.click.y);
		assertEquals(6592, d.click.z);

		Protocol.Ack a = new Protocol.Ack();
		a.seq = 7; a.result = Protocol.ACK_OFFSCREEN; a.canvasX = -1; a.canvasY = 300;
		Protocol.Decoded da = Protocol.decode(Protocol.ack(a));
		assertEquals(Protocol.INPUT_ACK, da.type);
		assertEquals(Protocol.ACK_OFFSCREEN, da.ack.result);
		assertEquals(-1, da.ack.canvasX);
		assertEquals(300, da.ack.canvasY);
	}

	@Test(expected = IllegalArgumentException.class)
	public void truncatedClickRejected()
	{
		byte[] full = Protocol.click(new Protocol.Click());
		Protocol.decode(Arrays.copyOf(full, full.length - 3));
	}

	@Test
	public void stretchedScaling()
	{
		java.awt.Point p = RemoteInput.scale(383, 251, new java.awt.Dimension(765, 503), new java.awt.Dimension(1530, 1006));
		assertEquals(766, p.x);
		assertEquals(502, p.y);
	}
}
