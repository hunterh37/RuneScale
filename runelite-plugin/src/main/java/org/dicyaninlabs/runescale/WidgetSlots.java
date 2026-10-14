package org.oldschool.runescape.runescale;

import java.awt.Rectangle;
import net.runelite.api.Client;
import net.runelite.api.gameval.InterfaceID;
import net.runelite.api.widgets.Widget;

/** Canvas bounds of inventory and equipment slot widgets. Null when the widget is not visible. */
final class WidgetSlots
{
	private WidgetSlots() { }

	/** Equipment slot index (EquipmentInventorySlot.getSlotIdx) to Wornitems component. 6, 8, 11 have none. */
	static int equipmentComponent(int slot)
	{
		switch (slot)
		{
			case 0: return InterfaceID.Wornitems.SLOT0;
			case 1: return InterfaceID.Wornitems.SLOT1;
			case 2: return InterfaceID.Wornitems.SLOT2;
			case 3: return InterfaceID.Wornitems.SLOT3;
			case 4: return InterfaceID.Wornitems.SLOT4;
			case 5: return InterfaceID.Wornitems.SLOT5;
			case 7: return InterfaceID.Wornitems.SLOT7;
			case 9: return InterfaceID.Wornitems.SLOT9;
			case 10: return InterfaceID.Wornitems.SLOT10;
			case 12: return InterfaceID.Wornitems.SLOT12;
			case 13: return InterfaceID.Wornitems.SLOT13;
			default: return -1;
		}
	}

	static Rectangle bounds(Client client, int container, int slot)
	{
		Widget w;
		if (container == Protocol.CONTAINER_INVENTORY)
		{
			if (slot < 0 || slot >= 28) return null;
			Widget parent = client.getWidget(InterfaceID.Inventory.ITEMS);
			if (parent == null || parent.isHidden()) return null;
			w = parent.getChild(slot);
		}
		else if (container == Protocol.CONTAINER_EQUIPMENT)
		{
			int id = equipmentComponent(slot);
			if (id < 0) return null;
			w = client.getWidget(id);
		}
		else
		{
			return null;
		}
		if (w == null || w.isHidden()) return null;
		Rectangle r = w.getBounds();
		return r == null || r.width <= 0 || r.height <= 0 ? null : r;
	}
}
