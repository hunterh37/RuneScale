package org.oldschool.runescape.runescale;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.IdentityHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.function.Consumer;
import net.runelite.api.Actor;
import net.runelite.api.Client;
import net.runelite.api.DecorativeObject;
import net.runelite.api.GameObject;
import net.runelite.api.GroundObject;
import net.runelite.api.Model;
import net.runelite.api.NPC;
import net.runelite.api.Perspective;
import net.runelite.api.Player;
import net.runelite.api.Renderable;
import net.runelite.api.Scene;
import net.runelite.api.SceneTileModel;
import net.runelite.api.SceneTilePaint;
import net.runelite.api.Tile;
import net.runelite.api.WallObject;
import net.runelite.api.WorldView;
import net.runelite.api.coords.LocalPoint;

/**
 * Reads scene geometry from the client. Read-only: calls getters only, never mutates
 * client state, never touches menus or input. Must run on the client thread.
 */
class SceneCapture
{
	private static final int HIDDEN = 12345678;
	private static final int MAX_TRANSIENT = 4096;

	private final Client client;
	private final TextureColors textures;
	private final Set<Long> sentMeshes = new HashSet<>();
	/** Terrain tiles already streamed since the last reset, keyed by plane, x, y (bridge bit 0x8 in plane). */
	private final Set<Integer> sentTiles = new HashSet<>();
	private final Map<Long, Protocol.Instance> statics = new HashMap<>();
	private final Map<Model, Long> idCache = new IdentityHashMap<>();
	private int baseX = Integer.MIN_VALUE, baseY = Integer.MIN_VALUE, plane = -1;
	private int lastCenterX = -1, lastCenterY = -1;

	SceneCapture(Client client)
	{
		this.client = client;
		this.textures = new TextureColors(client.getTextureProvider());
	}

	void invalidate()
	{
		baseX = Integer.MIN_VALUE;
	}

	/** Static scene diff: terrain, objects. Emits RESET when region or plane changes. */
	void captureStatic(int radius, boolean force, Consumer<byte[]> out)
	{
		Player me = client.getLocalPlayer();
		WorldView wv = client.getTopLevelWorldView();
		if (me == null || wv == null) return;
		Scene scene = wv.getScene();
		LocalPoint lp = me.getLocalLocation();
		int curPlane = wv.getPlane();
		int cx = lp.getSceneX(), cy = lp.getSceneY();

		boolean reset = force || wv.getBaseX() != baseX || wv.getBaseY() != baseY || curPlane != plane;
		if (!reset && Math.abs(cx - lastCenterX) < 2 && Math.abs(cy - lastCenterY) < 2 && !statics.isEmpty())
		{
			// player barely moved; still rescan for door/object changes below
		}
		if (reset)
		{
			baseX = wv.getBaseX();
			baseY = wv.getBaseY();
			plane = curPlane;
			sentMeshes.clear();
			sentTiles.clear();
			statics.clear();
			idCache.clear();
			Protocol.Reset r = new Protocol.Reset();
			r.baseX = baseX;
			r.baseY = baseY;
			r.plane = plane;
			out.accept(Protocol.reset(r));
		}
		lastCenterX = cx;
		lastCenterY = cy;

		Tile[][][] tiles = scene.getTiles();
		int[][][] heights = scene.getTileHeights();
		List<Protocol.Tile> terrain = new ArrayList<>();
		Map<Long, Protocol.Instance> seen = new HashMap<>();
		int size = wv.getSizeX();

		for (int z = 0; z <= curPlane; z++)
		{
			for (int x = Math.max(0, cx - radius); x <= Math.min(size - 1, cx + radius); x++)
			{
				for (int y = Math.max(0, cy - radius); y <= Math.min(tiles[z][x].length - 1, cy + radius); y++)
				{
					Tile t = tiles[z][x][y];
					if (t == null) continue;
					// terrain is sent once per tile; walking streams the tiles that enter the radius
					if (sentTiles.add(z << 16 | x << 8 | y)) addTerrain(t, z, z, x, y, heights, terrain, seen, out);
					addObjects(t, seen, out);
					// bridge-flagged tiles (Grand Exchange floor, bridges) keep the ground level here
					Tile bridge = t.getBridge();
					if (bridge != null)
					{
						int hz = Math.max(0, Math.min(heights.length - 1, bridge.getRenderLevel()));
						if (sentTiles.add((z | 8) << 16 | x << 8 | y)) addTerrain(bridge, hz, z | 8, x, y, heights, terrain, seen, out);
						addObjects(bridge, seen, out);
					}
				}
			}
		}
		{
			// terrain is sent once per tile; keep previous terrain instances alive
			for (Map.Entry<Long, Protocol.Instance> e : statics.entrySet())
			{
				if (e.getKey() < 0) seen.putIfAbsent(e.getKey(), e.getValue());
			}
		}
		if (!terrain.isEmpty()) out.accept(Protocol.terrain(terrain));

		List<Protocol.Instance> added = new ArrayList<>();
		for (Map.Entry<Long, Protocol.Instance> e : seen.entrySet())
		{
			Protocol.Instance old = statics.get(e.getKey());
			Protocol.Instance n = e.getValue();
			if (old == null || old.meshId != n.meshId || old.x != n.x || old.y != n.y || old.z != n.z || old.orientation != n.orientation)
			{
				added.add(n);
			}
		}
		List<Long> removed = new ArrayList<>();
		for (Long id : statics.keySet())
		{
			if (!seen.containsKey(id)) removed.add(id);
		}
		statics.clear();
		statics.putAll(seen);
		if (!removed.isEmpty()) out.accept(Protocol.staticRemove(removed));
		for (int i = 0; i < added.size(); i += 2000)
		{
			out.accept(Protocol.staticAdd(added.subList(i, Math.min(added.size(), i + 2000))));
		}
		if (idCache.size() > 50000) idCache.clear();
	}

	/** {@code z} indexes heights; {@code idPlane} is the plane in ids and messages (bit 8 = bridge). */
	private void addTerrain(Tile t, int z, int idPlane, int x, int y, int[][][] h, List<Protocol.Tile> terrain,
		Map<Long, Protocol.Instance> seen, Consumer<byte[]> out)
	{
		SceneTilePaint paint = t.getSceneTilePaint();
		if (paint != null && paint.getNeColor() != HIDDEN && x + 1 < h[z].length && y + 1 < h[z][x + 1].length)
		{
			Protocol.Tile pt = new Protocol.Tile();
			pt.x = x;
			pt.y = y;
			pt.plane = idPlane & 3;
			pt.heights[0] = h[z][x][y];
			pt.heights[1] = h[z][x + 1][y];
			pt.heights[2] = h[z][x + 1][y + 1];
			pt.heights[3] = h[z][x][y + 1];
			int tex = paint.getTexture();
			pt.colors[0] = faceRgb(paint.getSwColor(), tex, textures);
			pt.colors[1] = faceRgb(paint.getSeColor(), tex, textures);
			pt.colors[2] = faceRgb(paint.getNeColor(), tex, textures);
			pt.colors[3] = faceRgb(paint.getNwColor(), tex, textures);
			terrain.add(pt);
		}
		SceneTileModel tm = t.getSceneTileModel();
		if (tm != null)
		{
			Protocol.Mesh m = tileModelMesh(tm);
			if (m != null)
			{
				sendMesh(m, out);
				Protocol.Instance in = new Protocol.Instance();
				in.id = -1L - ((long) idPlane << 16 | (long) x << 8 | y); // negative ids = terrain
				in.meshId = m.id;
				seen.put(in.id, in);
			}
		}
	}

	private void addObjects(Tile t, Map<Long, Protocol.Instance> seen, Consumer<byte[]> out)
	{
		for (GameObject go : t.getGameObjects())
		{
			if (go == null || go.getSceneMinLocation() == null) continue;
			// multi-tile objects appear on several tiles; only take the origin tile
			if (!go.getSceneMinLocation().equals(t.getSceneLocation())) continue;
			LocalPoint p = go.getLocalLocation();
			put(go.getHash(), 0, go.getRenderable(), p.getX(), go.getZ(), p.getY(), go.getModelOrientation(), seen, out);
		}
		WallObject w = t.getWallObject();
		if (w != null)
		{
			LocalPoint p = w.getLocalLocation();
			put(w.getHash(), 1, w.getRenderable1(), p.getX(), w.getZ(), p.getY(), 0, seen, out);
			put(w.getHash(), 2, w.getRenderable2(), p.getX(), w.getZ(), p.getY(), 0, seen, out);
		}
		DecorativeObject d = t.getDecorativeObject();
		if (d != null)
		{
			LocalPoint p = d.getLocalLocation();
			put(d.getHash(), 3, d.getRenderable(), p.getX() + d.getXOffset(), d.getZ(), p.getY() + d.getYOffset(), 0, seen, out);
			put(d.getHash(), 4, d.getRenderable2(), p.getX() + d.getXOffset2(), d.getZ(), p.getY() + d.getYOffset2(), 0, seen, out);
		}
		GroundObject g = t.getGroundObject();
		if (g != null)
		{
			LocalPoint p = g.getLocalLocation();
			put(g.getHash(), 5, g.getRenderable(), p.getX(), g.getZ(), p.getY(), 0, seen, out);
		}
	}

	private void put(long hash, int slot, Renderable r, int x, int height, int y, int orientation,
		Map<Long, Protocol.Instance> seen, Consumer<byte[]> out)
	{
		if (r == null) return;
		Model model = r instanceof Model ? (Model) r : r.getModel();
		if (model == null) return;
		Long cached = idCache.get(model);
		long meshId;
		if (cached != null && sentMeshes.contains(cached))
		{
			meshId = cached;
		}
		else
		{
			Protocol.Mesh m = modelMesh(model, 0, textures);
			if (m == null) return;
			sendMesh(m, out);
			meshId = m.id;
			if (r instanceof Model) idCache.put(model, meshId); // only cache stable model instances
		}
		Protocol.Instance in = new Protocol.Instance();
		in.id = (hash * 8 + slot) & Long.MAX_VALUE; // non-negative ids = objects
		in.meshId = meshId;
		in.x = x;
		in.y = height;
		in.z = y;
		in.orientation = orientation & 2047;
		seen.put(in.id, in);
	}

	/** Actors streamed per frame, nearest first. Beyond this crowds are dropped. */
	static final int MAX_ACTORS = 128;
	/** Nearest actors that get a new animation pose every frame; the rest every 4th frame. */
	static final int FULL_RATE_ACTORS = 24;

	private static final class Pose
	{
		long sig;
		long meshId;
	}

	private static final class Candidate
	{
		final Actor a;
		final int kind, key, dist;
		final LocalPoint p;

		Candidate(Actor a, int kind, int key, int dist, LocalPoint p)
		{
			this.a = a; this.kind = kind; this.key = key; this.dist = dist; this.p = p;
		}
	}

	private final Map<Integer, Pose> poses = new HashMap<>();
	private final List<Candidate> candidates = new ArrayList<>();
	private int frameCount;

	/** Per-frame actor transforms; sends transient meshes for new animation poses. */
	void captureFrame(int radius, Consumer<byte[]> out)
	{
		Player me = client.getLocalPlayer();
		WorldView wv = client.getTopLevelWorldView();
		if (me == null || wv == null || baseX == Integer.MIN_VALUE) return;
		LocalPoint lp = me.getLocalLocation();
		Protocol.Frame f = new Protocol.Frame();
		f.tick = client.getTickCount();
		f.playerX = lp.getX();
		f.playerZ = lp.getY();
		f.playerY = Perspective.getTileHeight(client, lp, wv.getPlane());
		f.playerOrientation = me.getCurrentOrientation() & 2047;
		f.cameraYaw = client.getCameraYaw() & 2047;
		f.plane = wv.getPlane();
		int maxDist = radius * Perspective.LOCAL_TILE_SIZE;
		candidates.clear();
		for (Player p : wv.players())
		{
			if (p == null) continue;
			addCandidate(p, p == me ? Protocol.KIND_LOCAL : Protocol.KIND_PLAYER, p.getId(), lp, maxDist, p == me);
		}
		for (NPC n : wv.npcs())
		{
			if (n == null) continue;
			addCandidate(n, Protocol.KIND_NPC, 0x10000 | n.getIndex(), lp, maxDist, false);
		}
		candidates.sort((x, y) -> Integer.compare(x.dist, y.dist));
		int n = Math.min(candidates.size(), MAX_ACTORS);
		frameCount++;
		Set<Integer> live = new HashSet<>(n * 2);
		for (int i = 0; i < n; i++)
		{
			Candidate c = candidates.get(i);
			boolean refresh = i < FULL_RATE_ACTORS || ((frameCount + c.key) & 3) == 0;
			Protocol.Actor pa = actorFrame(c, refresh, wv, out);
			if (pa == null) continue;
			live.add(c.key);
			f.actors.add(pa);
		}
		poses.keySet().retainAll(live);
		candidates.clear();
		out.accept(Protocol.frame(f));
	}

	private void addCandidate(Actor a, int kind, int key, LocalPoint center, int maxDist, boolean self)
	{
		LocalPoint p = a.getLocalLocation();
		if (p == null) return;
		int d = p.distanceTo(center);
		if (d > maxDist) return;
		candidates.add(new Candidate(a, kind, key, self ? -1 : d, p));
	}

	private Protocol.Actor actorFrame(Candidate c, boolean refresh, WorldView wv, Consumer<byte[]> out)
	{
		Pose pose = poses.get(c.key);
		long meshId;
		if (!refresh && pose != null)
		{
			meshId = pose.meshId; // far actor: keep last pose, skip model read
		}
		else
		{
			Model model = c.a.getModel();
			if (model == null) return null;
			long sig = poseSignature(c.a, model);
			if (pose != null && pose.sig == sig)
			{
				meshId = pose.meshId; // same pose as last frame: skip mesh build + hash
			}
			else
			{
				Protocol.Mesh m = modelMesh(model, Protocol.MESH_FLAG_TRANSIENT, textures);
				if (m == null) return null;
				sendMesh(m, out);
				if (pose == null) { pose = new Pose(); poses.put(c.key, pose); }
				pose.sig = sig;
				pose.meshId = m.id;
				meshId = m.id;
			}
		}
		Protocol.Actor pa = new Protocol.Actor();
		pa.key = c.key;
		pa.kind = c.kind;
		pa.x = c.p.getX();
		pa.z = c.p.getY();
		pa.y = Perspective.getTileHeight(client, c.p, wv.getPlane());
		pa.orientation = c.a.getCurrentOrientation() & 2047;
		pa.meshId = meshId;
		return pa;
	}

	/** Cheap pose key: animation state, model size and a sparse vertex/color sample. */
	static long poseSignature(Actor a, Model m)
	{
		long h = 0xcbf29ce484222325L;
		h = (h ^ a.getAnimation()) * 0x100000001b3L;
		h = (h ^ a.getAnimationFrame()) * 0x100000001b3L;
		h = (h ^ a.getPoseAnimation()) * 0x100000001b3L;
		h = (h ^ a.getPoseAnimationFrame()) * 0x100000001b3L;
		return sampleHash(h, m);
	}

	static long sampleHash(long h, Model m)
	{
		int vc = m.getVerticesCount(), fc = m.getFaceCount();
		h = (h ^ vc) * 0x100000001b3L;
		h = (h ^ fc) * 0x100000001b3L;
		float[] vx = m.getVerticesX(), vy = m.getVerticesY(), vz = m.getVerticesZ();
		int vStep = Math.max(1, vc / 16);
		for (int v = 0; v < vc; v += vStep)
		{
			h = (h ^ Float.floatToRawIntBits(vx[v])) * 0x100000001b3L;
			h = (h ^ Float.floatToRawIntBits(vy[v])) * 0x100000001b3L;
			h = (h ^ Float.floatToRawIntBits(vz[v])) * 0x100000001b3L;
		}
		int[] c1 = m.getFaceColors1();
		int fStep = Math.max(1, fc / 16);
		for (int i = 0; i < fc; i += fStep) h = (h ^ c1[i]) * 0x100000001b3L;
		return h;
	}

	private void sendMesh(Protocol.Mesh m, Consumer<byte[]> out)
	{
		if (sentMeshes.add(m.id))
		{
			out.accept(Protocol.mesh(m));
			if ((m.flags & Protocol.MESH_FLAG_TRANSIENT) != 0 && sentMeshes.size() > 200000) sentMeshes.clear();
		}
	}

	static Protocol.Mesh modelMesh(Model model, int flags)
	{
		return modelMesh(model, flags, null);
	}

	static Protocol.Mesh modelMesh(Model model, int flags, TextureColors tex)
	{
		int vc = model.getVerticesCount(), fc = model.getFaceCount();
		if (vc <= 0 || fc <= 0 || vc > 65535) return null;
		float[] vx = model.getVerticesX(), vy = model.getVerticesY(), vz = model.getVerticesZ();
		int[] i1 = model.getFaceIndices1(), i2 = model.getFaceIndices2(), i3 = model.getFaceIndices3();
		int[] c1 = model.getFaceColors1(), c2 = model.getFaceColors2(), c3 = model.getFaceColors3();
		byte[] trans = model.getFaceTransparencies();
		short[] ft = tex == null ? null : model.getFaceTextures();
		return build(vc, fc, vx, vy, vz, i1, i2, i3, c1, c2, c3, trans, flags, ft, tex);
	}

	static Protocol.Mesh build(int vc, int fc, float[] vx, float[] vy, float[] vz, int[] i1, int[] i2, int[] i3,
		int[] c1, int[] c2, int[] c3, byte[] trans, int flags)
	{
		return build(vc, fc, vx, vy, vz, i1, i2, i3, c1, c2, c3, trans, flags, null, null);
	}

	/**
	 * Face color as RGB. Untextured: packed HSL. Textured (texture id >= 0): the color holds
	 * lightness only, so the texture's average color is shaded by it; a null {@code tex}
	 * resolver uses {@link TextureColors#FALLBACK}.
	 */
	static int faceRgb(int color, int texture, TextureColors tex)
	{
		if (texture < 0) return JagexColor.toRgb(color);
		int base = tex == null ? TextureColors.FALLBACK : tex.average(texture);
		return TextureColors.shade(base, color);
	}

	/** {@code faceTex} is per-face texture ids (-1 none) or null; textured faces resolve through {@code tex}. */
	static Protocol.Mesh build(int vc, int fc, float[] vx, float[] vy, float[] vz, int[] i1, int[] i2, int[] i3,
		int[] c1, int[] c2, int[] c3, byte[] trans, int flags, short[] faceTex, TextureColors tex)
	{
		int visible = 0;
		for (int f = 0; f < fc; f++) if (c3[f] != -2) visible++;
		if (visible == 0) return null;
		Protocol.Mesh m = new Protocol.Mesh();
		m.flags = flags;
		m.vertices = new short[vc * 3];
		for (int v = 0; v < vc; v++)
		{
			m.vertices[v * 3] = clamp(vx[v]);
			m.vertices[v * 3 + 1] = clamp(vy[v]);
			m.vertices[v * 3 + 2] = clamp(vz[v]);
		}
		m.indices = new int[visible * 3];
		m.colors = new int[visible * 3];
		m.alpha = new byte[visible];
		int o = 0;
		for (int f = 0; f < fc; f++)
		{
			if (c3[f] == -2) continue; // hidden face
			m.indices[o * 3] = i1[f];
			m.indices[o * 3 + 1] = i2[f];
			m.indices[o * 3 + 2] = i3[f];
			int t = faceTex != null && f < faceTex.length ? faceTex[f] : -1;
			int a = faceRgb(c1[f], t, tex);
			boolean flat = c3[f] == -1;
			m.colors[o * 3] = a;
			m.colors[o * 3 + 1] = flat ? a : faceRgb(c2[f], t, tex);
			m.colors[o * 3 + 2] = flat ? a : faceRgb(c3[f], t, tex);
			m.alpha[o] = (byte) (trans == null ? 255 : 255 - (trans[f] & 0xFF));
			o++;
		}
		m.id = hash(m);
		return m;
	}

	private Protocol.Mesh tileModelMesh(SceneTileModel tm)
	{
		int[] vx = tm.getVertexX(), vy = tm.getVertexY(), vz = tm.getVertexZ();
		int[] fx = tm.getFaceX(), fy = tm.getFaceY(), fz = tm.getFaceZ();
		if (vx == null || fx == null) return null;
		int[] ca = tm.getTriangleColorA(), cb = tm.getTriangleColorB(), cc = tm.getTriangleColorC();
		int fc = fx.length, vc = vx.length;
		float[] x = new float[vc], y = new float[vc], z = new float[vc];
		for (int i = 0; i < vc; i++)
		{
			// tile model vertices are in scene-local units: X east, Y height, Z north
			x[i] = vx[i];
			y[i] = vy[i];
			z[i] = vz[i];
		}
		int[] c3 = new int[fc];
		for (int i = 0; i < fc; i++) c3[i] = ca[i] == HIDDEN ? -2 : cc[i];
		int[] tt = tm.getTriangleTextureId();
		short[] ft = null;
		if (tt != null)
		{
			ft = new short[fc];
			for (int i = 0; i < fc; i++) ft[i] = (short) (i < tt.length ? tt[i] : -1);
		}
		return build(vc, fc, x, y, z, fx, fy, fz, ca, cb, c3, null, 0, ft, textures);
	}

	private static short clamp(float f)
	{
		int v = Math.round(f);
		return (short) Math.max(Short.MIN_VALUE, Math.min(Short.MAX_VALUE, v));
	}

	/** 64-bit FNV-1a over geometry and colors. Stable content id for dedup. */
	static long hash(Protocol.Mesh m)
	{
		long h = 0xcbf29ce484222325L;
		for (short s : m.vertices) h = (h ^ (s & 0xFFFF)) * 0x100000001b3L;
		for (int i : m.indices) h = (h ^ i) * 0x100000001b3L;
		for (int c : m.colors) h = (h ^ c) * 0x100000001b3L;
		for (byte b : m.alpha) h = (h ^ (b & 0xFF)) * 0x100000001b3L;
		h = (h ^ m.flags) * 0x100000001b3L;
		return h;
	}
}
