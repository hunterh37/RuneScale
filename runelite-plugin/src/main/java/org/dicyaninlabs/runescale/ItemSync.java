package org.oldschool.runescape.runescale;

import java.awt.image.BufferedImage;
import java.io.ByteArrayOutputStream;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;
import java.util.function.Consumer;
import javax.imageio.ImageIO;
import lombok.extern.slf4j.Slf4j;
import net.runelite.api.Client;
import net.runelite.api.Item;
import net.runelite.api.ItemComposition;
import net.runelite.api.ItemContainer;
import net.runelite.api.Model;
import net.runelite.api.gameval.InventoryID;
import net.runelite.client.game.ItemManager;

/** Streams inventory and equipment contents plus one PNG icon per item id. Read-only. */
@Slf4j
class ItemSync
{
	private final Client client;
	private final ItemManager items;
	private final Set<Integer> iconsSent = new HashSet<>();
	private final Map<Integer, Protocol.Mesh> modelCache = new HashMap<>();
	private final Set<Long> meshesSent = new HashSet<>();

	ItemSync(Client client, ItemManager items)
	{
		this.client = client;
		this.items = items;
	}

	/** New connection: icons must be resent. */
	synchronized void reset()
	{
		iconsSent.clear();
		meshesSent.clear();
	}

	/** Client thread. Sends both containers. */
	void sendAll(Consumer<byte[]> out)
	{
		send(InventoryID.INV, out);
		send(InventoryID.WORN, out);
	}

	/** Client thread. */
	void send(int containerId, Consumer<byte[]> out)
	{
		int kind;
		int size;
		if (containerId == InventoryID.INV) { kind = Protocol.CONTAINER_INVENTORY; size = 28; }
		else if (containerId == InventoryID.WORN) { kind = Protocol.CONTAINER_EQUIPMENT; size = 14; }
		else return;
		ItemContainer c = client.getItemContainer(containerId);
		Protocol.Container msg = snapshot(kind, size, c == null ? null : c.getItems());
		for (int id : msg.ids) icon(id, out);
		out.accept(Protocol.container(msg));
		if (kind == Protocol.CONTAINER_EQUIPMENT) sendModels(msg, out);
	}

	/** Client thread. One EQUIP_MODEL per worn slot; MESH first for unseen models. */
	private void sendModels(Protocol.Container worn, Consumer<byte[]> out)
	{
		for (int slot = 0; slot < worn.ids.length; slot++)
		{
			Protocol.EquipModel e = new Protocol.EquipModel();
			e.slot = slot;
			e.itemId = worn.ids[slot];
			Protocol.Mesh m = e.itemId >= 0 ? model(e.itemId, iconPosed(slot)) : null;
			if (m != null)
			{
				boolean fresh;
				synchronized (this) { fresh = meshesSent.add(m.id); }
				if (fresh) out.accept(Protocol.mesh(m));
				e.meshId = m.id;
			}
			out.accept(Protocol.equipModel(e));
		}
	}

	/** Body-worn slots (head, cape, amulet, body, legs, boots) use the icon pose: upright, front toward -z. */
	static boolean iconPosed(int slot)
	{
		return slot == 0 || slot == 1 || slot == 2 || slot == 4 || slot == 7 || slot == 10;
	}

	private Protocol.Mesh model(int itemId, boolean posed)
	{
		if (modelCache.containsKey(itemId)) return modelCache.get(itemId);
		Protocol.Mesh mesh = null;
		try
		{
			ItemComposition def = client.getItemDefinition(itemId);
			Model model = client.loadModel(def.getInventoryModel(), def.getColorToReplace(), def.getColorToReplaceWith());
			if (model != null && posed)
			{
				int vc = model.getVerticesCount();
				float[] vx = model.getVerticesX().clone(), vy = model.getVerticesY().clone(), vz = model.getVerticesZ().clone();
				iconPose(vx, vy, vz, vc, def.getXan2d(), def.getYan2d(), def.getZan2d());
				mesh = SceneCapture.build(vc, model.getFaceCount(), vx, vy, vz, model.getFaceIndices1(), model.getFaceIndices2(),
					model.getFaceIndices3(), model.getFaceColors1(), model.getFaceColors2(), model.getFaceColors3(),
					model.getFaceTransparencies(), 0);
			}
			else if (model != null) mesh = SceneCapture.modelMesh(model, 0);
		}
		catch (Exception ex)
		{
			log.debug("item model load failed for {}", itemId, ex);
		}
		modelCache.put(itemId, mesh);
		return mesh;
	}

	/**
	 * Rotates inventory-model vertices the way the client renders the item icon: yaw (yan2d about Y),
	 * roll (zan2d about Z), pitch (xan2d about X), angles in 2048ths of a turn. The icon camera looks
	 * along +z with y down, so the result is upright with the item front facing -z.
	 */
	static void iconPose(float[] vx, float[] vy, float[] vz, int vc, int xan, int yan, int zan)
	{
		double k = 2 * Math.PI / 2048;
		float sy = (float) Math.sin(yan * k), cy = (float) Math.cos(yan * k);
		float sz = (float) Math.sin(zan * k), cz = (float) Math.cos(zan * k);
		float sx = (float) Math.sin(xan * k), cx = (float) Math.cos(xan * k);
		for (int v = 0; v < vc; v++)
		{
			float x = vx[v], y = vy[v], z = vz[v], t;
			if (yan != 0) { t = z * sy + x * cy; z = z * cy - x * sy; x = t; }
			if (zan != 0) { t = y * sz + x * cz; y = y * cz - x * sz; x = t; }
			if (xan != 0) { t = y * cx - z * sx; z = y * sx + z * cx; y = t; }
			vx[v] = x; vy[v] = y; vz[v] = z;
		}
	}

	static Protocol.Container snapshot(int kind, int size, Item[] src)
	{
		Protocol.Container msg = new Protocol.Container();
		msg.kind = kind;
		msg.ids = new int[size];
		msg.qty = new int[size];
		for (int i = 0; i < size; i++)
		{
			Item it = src != null && i < src.length ? src[i] : null;
			boolean empty = it == null || it.getId() < 0 || it.getQuantity() <= 0;
			msg.ids[i] = empty ? -1 : it.getId();
			msg.qty[i] = empty ? 0 : it.getQuantity();
		}
		return msg;
	}

	private void icon(int id, Consumer<byte[]> out)
	{
		if (id < 0) return;
		synchronized (this)
		{
			if (!iconsSent.add(id)) return;
		}
		BufferedImage img = items.getImage(id);
		// AsyncBufferedImage fills in later; encode once loaded
		if (img instanceof net.runelite.client.util.AsyncBufferedImage)
		{
			((net.runelite.client.util.AsyncBufferedImage) img).onLoaded(() -> encode(id, img, out));
		}
		else
		{
			encode(id, img, out);
		}
	}

	private static void encode(int id, BufferedImage img, Consumer<byte[]> out)
	{
		try
		{
			ByteArrayOutputStream bos = new ByteArrayOutputStream();
			ImageIO.write(img, "png", bos);
			Protocol.ItemIcon i = new Protocol.ItemIcon();
			i.itemId = id;
			i.png = bos.toByteArray();
			out.accept(Protocol.itemIcon(i));
		}
		catch (Exception e)
		{
			log.debug("icon encode failed for {}", id, e);
		}
	}
}
