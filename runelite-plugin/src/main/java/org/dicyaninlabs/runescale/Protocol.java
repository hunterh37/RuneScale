package org.oldschool.runescape.runescale;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.ArrayList;
import java.util.List;

/** Binary wire format. See notes/PROTOCOL.md. All values little-endian. */
public final class Protocol
{
	public static final int MAGIC = 0x5253; // "RS"
	public static final int VERSION = 1;

	public static final int HELLO = 1;
	public static final int RESET = 2;
	public static final int MESH = 3;
	public static final int TERRAIN = 4;
	public static final int STATIC_ADD = 5;
	public static final int STATIC_REMOVE = 6;
	public static final int FRAME = 7;
	public static final int INPUT_ACK = 8;
	public static final int UI_FRAME = 9;
	public static final int CONTAINER = 10;
	public static final int ITEM_ICON = 11;
	public static final int EQUIP_MODEL = 12;
	public static final int WIDGET_CLICK = 66;
	public static final int MENU = 13;
	public static final int HITSPLAT = 14;
	public static final int HEALTH = 15;
	public static final int SOUND = 16;
	public static final int MUSIC = 17;
	public static final int MENU_SELECT = 67;
	public static final int ACK_NO_MENU = 6;
	public static final int CONTAINER_INVENTORY = 0, CONTAINER_EQUIPMENT = 1;
	public static final int ACK_WIDGET_HIDDEN = 5;
	/** Headset to plugin. Only accepted when remote input is enabled. */
	public static final int CLICK = 64;
	public static final int UI_CLICK = 65;

	public static final int BUTTON_LEFT = 0, BUTTON_RIGHT = 1;
	public static final int ACK_OK = 0, ACK_DISABLED = 1, ACK_OFFSCREEN = 2, ACK_RATE_LIMITED = 3, ACK_NOT_LOGGED_IN = 4;

	public static final int MESH_FLAG_TRANSIENT = 1;
	public static final int KIND_LOCAL = 0, KIND_PLAYER = 1, KIND_NPC = 2, KIND_OWN_PET = 3, KIND_PET = 4;

	private Protocol() { }

	public static final class Mesh
	{
		public long id;
		public int flags;
		public short[] vertices; // x,y,z triples, OSRS model units, y down
		public int[] indices;    // a,b,c triples
		public int[] colors;     // rgb per face corner (3 per face)
		public byte[] alpha;     // per face, 255 = opaque

		public int faceCount() { return indices.length / 3; }
	}

	public static final class Tile
	{
		public int x, y, plane;
		public int[] heights = new int[4]; // sw, se, ne, nw
		public int[] colors = new int[4];  // rgb sw, se, ne, nw
	}

	public static final class Instance
	{
		public long id, meshId;
		public int x, y, z, orientation;
	}

	public static final class Actor
	{
		public int key, kind, x, y, z, orientation;
		public long meshId;
	}

	public static final class Frame
	{
		public int tick, playerX, playerY, playerZ, playerOrientation, cameraYaw, plane;
		public List<Actor> actors = new ArrayList<>();
	}

	/** One hitsplat on an actor (same key as FRAME), with the actor's health bar at that moment. */
	public static final class Hitsplat
	{
		public int key, type, amount, ratio = -1, scale;
	}

	/** Health bar for one actor; ratio/scale as in Actor.getHealthRatio/getHealthScale. */
	public static final class Health
	{
		public int key, ratio, scale;
	}

	public static final class Reset
	{
		public int baseX, baseY, plane;
	}

	/** Click at a scene-local 3D point (same units as FRAME). The plugin projects it to the canvas. */
	public static final class Click
	{
		public int seq, button, x, y, z;
	}

	public static final class UiClick
	{
		public int seq, button, x, y; // game canvas pixels
	}

	public static final class UiFrame
	{
		public int seq, canvasWidth, canvasHeight;
		public byte[] jpeg;
	}

	/** Item container snapshot: slot i holds ids[i] x qty[i]; id -1 is empty. */
	public static final class Container
	{
		public int kind;
		public int[] ids = new int[0], qty = new int[0];
	}

	/** Worn item 3D model: slot (EquipmentInventorySlot idx), item id, inventory-model mesh id (0 = empty). */
	public static final class EquipModel
	{
		public int slot, itemId;
		public long meshId;
	}

	public static final class ItemIcon
	{
		public int itemId;
		public byte[] png;
	}

	/** Headset to plugin: click one slot of an item container widget. */
	public static final class WidgetClick
	{
		public int seq, button, container, slot;
	}

	/** Open game right-click menu, rows top to bottom; empty = closed. */
	public static final class Menu
	{
		public int seq;
		public String[] options = new String[0], targets = new String[0];
	}

	/** Headset to plugin: left click row {@code index} (top = 0) of the open menu {@code menuSeq}. */
	public static final class MenuSelect
	{
		public int seq, menuSeq, index;
	}

	public static final class Ack
	{
		public int seq, result, canvasX, canvasY;
	}

	private static ByteBuffer header(int type, int body)
	{
		ByteBuffer b = ByteBuffer.allocate(4 + body).order(ByteOrder.LITTLE_ENDIAN);
		b.putShort((short) MAGIC).put((byte) VERSION).put((byte) type);
		return b;
	}

	private static void rgb(ByteBuffer b, int c)
	{
		b.put((byte) (c >> 16)).put((byte) (c >> 8)).put((byte) c);
	}

	private static int rgb(ByteBuffer b)
	{
		return ((b.get() & 0xFF) << 16) | ((b.get() & 0xFF) << 8) | (b.get() & 0xFF);
	}

	public static byte[] hello(int radius)
	{
		return header(HELLO, 4).putInt(radius).array();
	}

	public static byte[] reset(Reset r)
	{
		return header(RESET, 9).putInt(r.baseX).putInt(r.baseY).put((byte) r.plane).array();
	}

	public static byte[] mesh(Mesh m)
	{
		int v = m.vertices.length / 3, f = m.faceCount();
		ByteBuffer b = header(MESH, 8 + 1 + 4 + 4 + v * 6 + f * 6 + f * 9 + f);
		b.putLong(m.id).put((byte) m.flags).putInt(v).putInt(f);
		for (short s : m.vertices) b.putShort(s);
		for (int i : m.indices) b.putShort((short) i);
		for (int c : m.colors) rgb(b, c);
		b.put(m.alpha);
		return b.array();
	}

	public static byte[] terrain(List<Tile> tiles)
	{
		ByteBuffer b = header(TERRAIN, 4 + tiles.size() * (3 + 16 + 12));
		b.putInt(tiles.size());
		for (Tile t : tiles)
		{
			b.put((byte) t.x).put((byte) t.y).put((byte) t.plane);
			for (int h : t.heights) b.putInt(h);
			for (int c : t.colors) rgb(b, c);
		}
		return b.array();
	}

	public static byte[] staticAdd(List<Instance> list)
	{
		ByteBuffer b = header(STATIC_ADD, 4 + list.size() * 30);
		b.putInt(list.size());
		for (Instance i : list)
		{
			b.putLong(i.id).putLong(i.meshId).putInt(i.x).putInt(i.y).putInt(i.z).putShort((short) i.orientation);
		}
		return b.array();
	}

	public static byte[] staticRemove(List<Long> ids)
	{
		ByteBuffer b = header(STATIC_REMOVE, 4 + ids.size() * 8);
		b.putInt(ids.size());
		for (long id : ids) b.putLong(id);
		return b.array();
	}

	public static byte[] frame(Frame f)
	{
		ByteBuffer b = header(FRAME, 4 + 12 + 2 + 2 + 1 + 4 + f.actors.size() * 27);
		b.putInt(f.tick).putInt(f.playerX).putInt(f.playerY).putInt(f.playerZ)
			.putShort((short) f.playerOrientation).putShort((short) f.cameraYaw).put((byte) f.plane);
		b.putInt(f.actors.size());
		for (Actor a : f.actors)
		{
			b.putInt(a.key).put((byte) a.kind).putInt(a.x).putInt(a.y).putInt(a.z)
				.putShort((short) a.orientation).putLong(a.meshId);
		}
		return b.array();
	}

	public static byte[] click(Click c)
	{
		return header(CLICK, 4 + 1 + 12).putInt(c.seq).put((byte) c.button).putInt(c.x).putInt(c.y).putInt(c.z).array();
	}

	public static byte[] ack(Ack a)
	{
		return header(INPUT_ACK, 4 + 1 + 8).putInt(a.seq).put((byte) a.result).putInt(a.canvasX).putInt(a.canvasY).array();
	}

	public static byte[] uiClick(UiClick c)
	{
		return header(UI_CLICK, 4 + 1 + 8).putInt(c.seq).put((byte) c.button).putInt(c.x).putInt(c.y).array();
	}

	public static byte[] uiFrame(UiFrame f)
	{
		return header(UI_FRAME, 4 + 2 + 2 + 4 + f.jpeg.length).putInt(f.seq).putShort((short) f.canvasWidth)
			.putShort((short) f.canvasHeight).putInt(f.jpeg.length).put(f.jpeg).array();
	}

	public static byte[] container(Container c)
	{
		ByteBuffer b = header(CONTAINER, 1 + 4 + c.ids.length * 8).put((byte) c.kind).putInt(c.ids.length);
		for (int i = 0; i < c.ids.length; i++) b.putInt(c.ids[i]).putInt(c.qty[i]);
		return b.array();
	}

	public static byte[] itemIcon(ItemIcon i)
	{
		return header(ITEM_ICON, 8 + i.png.length).putInt(i.itemId).putInt(i.png.length).put(i.png).array();
	}

	public static byte[] equipModel(EquipModel e)
	{
		return header(EQUIP_MODEL, 1 + 4 + 8).put((byte) e.slot).putInt(e.itemId).putLong(e.meshId).array();
	}

	public static byte[] widgetClick(WidgetClick c)
	{
		return header(WIDGET_CLICK, 4 + 3).putInt(c.seq).put((byte) c.button).put((byte) c.container).put((byte) c.slot).array();
	}

	private static void str(ByteBuffer b, byte[] u)
	{
		b.putShort((short) u.length).put(u);
	}

	private static String str(ByteBuffer b)
	{
		byte[] u = new byte[b.getShort() & 0xFFFF];
		b.get(u);
		return new String(u, java.nio.charset.StandardCharsets.UTF_8);
	}

	public static byte[] menu(Menu m)
	{
		int n = Math.min(m.options.length, 255);
		byte[][] o = new byte[n][], t = new byte[n][];
		int body = 4 + 1;
		for (int i = 0; i < n; i++)
		{
			o[i] = m.options[i].getBytes(java.nio.charset.StandardCharsets.UTF_8);
			t[i] = m.targets[i].getBytes(java.nio.charset.StandardCharsets.UTF_8);
			body += 4 + o[i].length + t[i].length;
		}
		ByteBuffer b = header(MENU, body).putInt(m.seq).put((byte) n);
		for (int i = 0; i < n; i++)
		{
			str(b, o[i]);
			str(b, t[i]);
		}
		return b.array();
	}

	public static byte[] hitsplat(Hitsplat h)
	{
		return header(HITSPLAT, 4 + 2 + 4 + 1 + 1).putInt(h.key).putShort((short) h.type).putInt(h.amount)
			.put((byte) (h.ratio < 0 ? 255 : Math.min(h.ratio, 254))).put((byte) Math.min(h.scale, 255)).array();
	}

	/** Actors whose health bar is showing this tick; actors left out have no bar. */
	public static byte[] health(List<Health> list)
	{
		ByteBuffer b = header(HEALTH, 4 + list.size() * 6);
		b.putInt(list.size());
		for (Health h : list) b.putInt(h.key).put((byte) Math.min(h.ratio, 254)).put((byte) Math.min(h.scale, 255));
		return b.array();
	}

	/** Sound effect: area = positioned at scene-local x,z units (tile * 128 + 64); sourceKey -1 none. */
	public static byte[] sound(boolean area, int soundId, int delay, int range, int x, int z, int sourceKey)
	{
		return header(SOUND, 1 + 2 + 2 + 1 + 4 + 4 + 4).put((byte) (area ? 1 : 0)).putShort((short) soundId)
			.putShort((short) Math.min(Math.max(delay, 0), 0xFFFF)).put((byte) Math.min(Math.max(range, 0), 255))
			.putInt(x).putInt(z).putInt(sourceKey).array();
	}

	/** Music tab now-playing title; empty = none. */
	public static byte[] music(String title)
	{
		byte[] u = title.getBytes(java.nio.charset.StandardCharsets.UTF_8);
		int n = Math.min(u.length, 0xFFFF);
		return header(MUSIC, 2 + n).putShort((short) n).put(u, 0, n).array();
	}

	public static byte[] menuSelect(MenuSelect s)
	{
		return header(MENU_SELECT, 9).putInt(s.seq).putInt(s.menuSeq).put((byte) s.index).array();
	}

	/** Decoded message: type plus one populated payload. Used by tests and tooling. */
	public static final class Decoded
	{
		public int type;
		public int radius;
		public Reset reset;
		public Mesh mesh;
		public List<Tile> tiles;
		public List<Instance> instances;
		public List<Long> removed;
		public Frame frame;
		public Click click;
		public UiClick uiClick;
		public UiFrame uiFrame;
		public Ack ack;
		public Container container;
		public ItemIcon icon;
		public WidgetClick widgetClick;
		public EquipModel equip;
		public Menu menu;
		public MenuSelect menuSelect;
		public Hitsplat hitsplat;
		public List<Health> health;
	}

	public static Decoded decode(byte[] data)
	{
		ByteBuffer b = ByteBuffer.wrap(data).order(ByteOrder.LITTLE_ENDIAN);
		if ((b.getShort() & 0xFFFF) != MAGIC) throw new IllegalArgumentException("bad magic");
		if ((b.get() & 0xFF) != VERSION) throw new IllegalArgumentException("bad version");
		Decoded d = new Decoded();
		d.type = b.get() & 0xFF;
		switch (d.type)
		{
			case HELLO:
				d.radius = b.getInt();
				break;
			case RESET:
				d.reset = new Reset();
				d.reset.baseX = b.getInt();
				d.reset.baseY = b.getInt();
				d.reset.plane = b.get() & 0xFF;
				break;
			case MESH:
			{
				Mesh m = new Mesh();
				m.id = b.getLong();
				m.flags = b.get() & 0xFF;
				int v = b.getInt(), f = b.getInt();
				m.vertices = new short[v * 3];
				for (int i = 0; i < m.vertices.length; i++) m.vertices[i] = b.getShort();
				m.indices = new int[f * 3];
				for (int i = 0; i < m.indices.length; i++) m.indices[i] = b.getShort() & 0xFFFF;
				m.colors = new int[f * 3];
				for (int i = 0; i < m.colors.length; i++) m.colors[i] = rgb(b);
				m.alpha = new byte[f];
				b.get(m.alpha);
				d.mesh = m;
				break;
			}
			case TERRAIN:
			{
				int n = b.getInt();
				d.tiles = new ArrayList<>(n);
				for (int i = 0; i < n; i++)
				{
					Tile t = new Tile();
					t.x = b.get() & 0xFF;
					t.y = b.get() & 0xFF;
					t.plane = b.get() & 0xFF;
					for (int k = 0; k < 4; k++) t.heights[k] = b.getInt();
					for (int k = 0; k < 4; k++) t.colors[k] = rgb(b);
					d.tiles.add(t);
				}
				break;
			}
			case STATIC_ADD:
			{
				int n = b.getInt();
				d.instances = new ArrayList<>(n);
				for (int i = 0; i < n; i++)
				{
					Instance in = new Instance();
					in.id = b.getLong();
					in.meshId = b.getLong();
					in.x = b.getInt();
					in.y = b.getInt();
					in.z = b.getInt();
					in.orientation = b.getShort() & 0xFFFF;
					d.instances.add(in);
				}
				break;
			}
			case STATIC_REMOVE:
			{
				int n = b.getInt();
				d.removed = new ArrayList<>(n);
				for (int i = 0; i < n; i++) d.removed.add(b.getLong());
				break;
			}
			case FRAME:
			{
				Frame f = new Frame();
				f.tick = b.getInt();
				f.playerX = b.getInt();
				f.playerY = b.getInt();
				f.playerZ = b.getInt();
				f.playerOrientation = b.getShort() & 0xFFFF;
				f.cameraYaw = b.getShort() & 0xFFFF;
				f.plane = b.get() & 0xFF;
				int n = b.getInt();
				for (int i = 0; i < n; i++)
				{
					Actor a = new Actor();
					a.key = b.getInt();
					a.kind = b.get() & 0xFF;
					a.x = b.getInt();
					a.y = b.getInt();
					a.z = b.getInt();
					a.orientation = b.getShort() & 0xFFFF;
					a.meshId = b.getLong();
					f.actors.add(a);
				}
				d.frame = f;
				break;
			}
			case CLICK:
			{
				if (b.remaining() < 17) throw new IllegalArgumentException("truncated click");
				Click c = new Click();
				c.seq = b.getInt();
				c.button = b.get() & 0xFF;
				c.x = b.getInt();
				c.y = b.getInt();
				c.z = b.getInt();
				d.click = c;
				break;
			}
			case UI_CLICK:
			{
				if (b.remaining() < 13) throw new IllegalArgumentException("truncated ui click");
				UiClick c = new UiClick();
				c.seq = b.getInt();
				c.button = b.get() & 0xFF;
				c.x = b.getInt();
				c.y = b.getInt();
				d.uiClick = c;
				break;
			}
			case UI_FRAME:
			{
				UiFrame f = new UiFrame();
				f.seq = b.getInt();
				f.canvasWidth = b.getShort() & 0xFFFF;
				f.canvasHeight = b.getShort() & 0xFFFF;
				f.jpeg = new byte[b.getInt()];
				b.get(f.jpeg);
				d.uiFrame = f;
				break;
			}
			case INPUT_ACK:
			{
				Ack a = new Ack();
				a.seq = b.getInt();
				a.result = b.get() & 0xFF;
				a.canvasX = b.getInt();
				a.canvasY = b.getInt();
				d.ack = a;
				break;
			}
			case CONTAINER:
			{
				Container c = new Container();
				c.kind = b.get() & 0xFF;
				int n = b.getInt();
				c.ids = new int[n];
				c.qty = new int[n];
				for (int i = 0; i < n; i++)
				{
					c.ids[i] = b.getInt();
					c.qty[i] = b.getInt();
				}
				d.container = c;
				break;
			}
			case ITEM_ICON:
			{
				ItemIcon i = new ItemIcon();
				i.itemId = b.getInt();
				i.png = new byte[b.getInt()];
				b.get(i.png);
				d.icon = i;
				break;
			}
			case EQUIP_MODEL:
			{
				EquipModel e = new EquipModel();
				e.slot = b.get() & 0xFF;
				e.itemId = b.getInt();
				e.meshId = b.getLong();
				d.equip = e;
				break;
			}
			case WIDGET_CLICK:
			{
				if (b.remaining() < 7) throw new IllegalArgumentException("truncated widget click");
				WidgetClick c = new WidgetClick();
				c.seq = b.getInt();
				c.button = b.get() & 0xFF;
				c.container = b.get() & 0xFF;
				c.slot = b.get() & 0xFF;
				d.widgetClick = c;
				break;
			}
			case MENU:
			{
				Menu m = new Menu();
				m.seq = b.getInt();
				int n = b.get() & 0xFF;
				m.options = new String[n];
				m.targets = new String[n];
				for (int i = 0; i < n; i++)
				{
					m.options[i] = str(b);
					m.targets[i] = str(b);
				}
				d.menu = m;
				break;
			}
			case HITSPLAT:
			{
				Hitsplat h = new Hitsplat();
				h.key = b.getInt();
				h.type = b.getShort() & 0xFFFF;
				h.amount = b.getInt();
				int r = b.get() & 0xFF;
				h.ratio = r == 255 ? -1 : r;
				h.scale = b.get() & 0xFF;
				d.hitsplat = h;
				break;
			}
			case HEALTH:
			{
				int n = b.getInt();
				d.health = new ArrayList<>(n);
				for (int i = 0; i < n; i++)
				{
					Health h = new Health();
					h.key = b.getInt();
					h.ratio = b.get() & 0xFF;
					h.scale = b.get() & 0xFF;
					d.health.add(h);
				}
				break;
			}
			case MENU_SELECT:
			{
				if (b.remaining() < 9) throw new IllegalArgumentException("truncated menu select");
				MenuSelect m = new MenuSelect();
				m.seq = b.getInt();
				m.menuSeq = b.getInt();
				m.index = b.get() & 0xFF;
				d.menuSelect = m;
				break;
			}
			default:
				throw new IllegalArgumentException("unknown type " + d.type);
		}
		return d;
	}
}
