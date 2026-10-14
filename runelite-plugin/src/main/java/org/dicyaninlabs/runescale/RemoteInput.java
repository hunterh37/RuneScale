package org.oldschool.runescape.runescale;

import java.awt.Canvas;
import java.awt.Dimension;
import java.awt.event.InputEvent;
import java.awt.event.MouseEvent;
import java.util.function.Consumer;
import lombok.extern.slf4j.Slf4j;
import javax.swing.SwingUtilities;
import net.runelite.api.Client;
import net.runelite.api.GameState;
import net.runelite.api.Perspective;
import net.runelite.api.Point;
import net.runelite.client.callback.ClientThread;

/**
 * Turns a headset tap into one real mouse click on the game canvas. One tap produces exactly one
 * click at the projected screen position of the tapped 3D point; nothing is queued or repeated.
 * Disabled unless the "Headset input" config option is on.
 */
@Slf4j
class RemoteInput
{
	static final long MIN_INTERVAL_MS = 100;

	private final Client client;
	private final ClientThread clientThread;
	private long lastClick;

	RemoteInput(Client client, ClientThread clientThread)
	{
		this.client = client;
		this.clientThread = clientThread;
	}

	/** Called from the socket thread. {@code reply} receives the ACK bytes. */
	void handle(Protocol.Click c, boolean enabled, Consumer<byte[]> reply)
	{
		log.info("headset click #{} button={} at {},{},{} enabled={}", c.seq, c.button, c.x, c.y, c.z, enabled);
		if (!enabled)
		{
			reply.accept(ack(c, Protocol.ACK_DISABLED, -1, -1));
			return;
		}
		if (!takeSlot())
		{
			reply.accept(ack(c, Protocol.ACK_RATE_LIMITED, -1, -1));
			return;
		}
		clientThread.invoke(() ->
		{
			if (client.getGameState() != GameState.LOGGED_IN)
			{
				reply.accept(ack(c, Protocol.ACK_NOT_LOGGED_IN, -1, -1));
				return;
			}
			Point p = Perspective.localToCanvas(client, c.x, c.z, c.y);
			if (p == null || !inViewport(p))
			{
				reply.accept(ack(c, Protocol.ACK_OFFSCREEN, -1, -1));
				return;
			}
			java.awt.Point real = toRealCanvas(p.getX(), p.getY());
			log.info("headset click #{} -> canvas {},{}", c.seq, real.x, real.y);
			SwingUtilities.invokeLater(() -> dispatch(client.getCanvas(), real.x, real.y, c.button));
			reply.accept(ack(c, Protocol.ACK_OK, p.getX(), p.getY()));
		});
	}

	/** Click at a game-canvas pixel from the mirrored interface panel. Works on any game state. */
	void handleUi(Protocol.UiClick c, boolean enabled, Consumer<byte[]> reply)
	{
		log.info("headset ui click #{} button={} at {},{} enabled={}", c.seq, c.button, c.x, c.y, enabled);
		if (!enabled)
		{
			reply.accept(ack(c.seq, Protocol.ACK_DISABLED, -1, -1));
			return;
		}
		if (!takeSlot())
		{
			reply.accept(ack(c.seq, Protocol.ACK_RATE_LIMITED, -1, -1));
			return;
		}
		clientThread.invoke(() ->
		{
			if (c.x < 0 || c.y < 0 || c.x >= client.getCanvasWidth() || c.y >= client.getCanvasHeight())
			{
				reply.accept(ack(c.seq, Protocol.ACK_OFFSCREEN, -1, -1));
				return;
			}
			java.awt.Point real = toRealCanvas(c.x, c.y);
			SwingUtilities.invokeLater(() -> dispatch(client.getCanvas(), real.x, real.y, c.button));
			reply.accept(ack(c.seq, Protocol.ACK_OK, c.x, c.y));
		});
	}

	/**
	 * Click one inventory or equipment slot by its widget bounds. The tab must be open; a hidden
	 * widget returns ACK_WIDGET_HIDDEN instead of switching tabs (one gesture, one click).
	 */
	void handleWidget(Protocol.WidgetClick c, boolean enabled, Consumer<byte[]> reply)
	{
		log.info("headset widget click #{} container={} slot={} enabled={}", c.seq, c.container, c.slot, enabled);
		if (!enabled)
		{
			reply.accept(ack(c.seq, Protocol.ACK_DISABLED, -1, -1));
			return;
		}
		if (!takeSlot())
		{
			reply.accept(ack(c.seq, Protocol.ACK_RATE_LIMITED, -1, -1));
			return;
		}
		clientThread.invoke(() ->
		{
			if (client.getGameState() != GameState.LOGGED_IN)
			{
				reply.accept(ack(c.seq, Protocol.ACK_NOT_LOGGED_IN, -1, -1));
				return;
			}
			java.awt.Rectangle r = WidgetSlots.bounds(client, c.container, c.slot);
			if (r == null)
			{
				reply.accept(ack(c.seq, Protocol.ACK_WIDGET_HIDDEN, -1, -1));
				return;
			}
			int x = (int) r.getCenterX(), y = (int) r.getCenterY();
			java.awt.Point real = toRealCanvas(x, y);
			SwingUtilities.invokeLater(() -> dispatch(client.getCanvas(), real.x, real.y, c.button));
			reply.accept(ack(c.seq, Protocol.ACK_OK, x, y));
		});
	}

	/**
	 * Left click one row of the open right-click menu. Rows are top to bottom, matching MENU.
	 * A stale menu (closed or reopened since the headset saw it) returns ACK_NO_MENU.
	 */
	void handleMenu(Protocol.MenuSelect m, int currentMenuSeq, boolean enabled, Consumer<byte[]> reply)
	{
		log.info("headset menu select #{} menu={} row={} enabled={}", m.seq, m.menuSeq, m.index, enabled);
		if (!enabled)
		{
			reply.accept(ack(m.seq, Protocol.ACK_DISABLED, -1, -1));
			return;
		}
		if (!takeSlot())
		{
			reply.accept(ack(m.seq, Protocol.ACK_RATE_LIMITED, -1, -1));
			return;
		}
		clientThread.invoke(() ->
		{
			int n = client.getMenuEntries().length;
			if (!client.isMenuOpen() || m.menuSeq != currentMenuSeq || m.index >= n)
			{
				reply.accept(ack(m.seq, Protocol.ACK_NO_MENU, -1, -1));
				return;
			}
			java.awt.Point p = menuRow(client.getMenuX(), client.getMenuY(), client.getMenuWidth(), m.index);
			java.awt.Point real = toRealCanvas(p.x, p.y);
			SwingUtilities.invokeLater(() -> dispatch(client.getCanvas(), real.x, real.y, Protocol.BUTTON_LEFT));
			reply.accept(ack(m.seq, Protocol.ACK_OK, p.x, p.y));
		});
	}

	/** Center of menu row {@code index}: 19 px header, 15 px rows. */
	static java.awt.Point menuRow(int menuX, int menuY, int menuWidth, int index)
	{
		return new java.awt.Point(menuX + menuWidth / 2, menuY + 19 + index * 15 + 7);
	}

	private synchronized boolean takeSlot()
	{
		long now = System.currentTimeMillis();
		if (now - lastClick < MIN_INTERVAL_MS) return false;
		lastClick = now;
		return true;
	}

	private boolean inViewport(Point p)
	{
		int x0 = client.getViewportXOffset(), y0 = client.getViewportYOffset();
		return p.getX() >= x0 && p.getY() >= y0
			&& p.getX() < x0 + client.getViewportWidth() && p.getY() < y0 + client.getViewportHeight();
	}

	/** Game canvas coordinates to AWT canvas coordinates (stretched mode scales the canvas). */
	private java.awt.Point toRealCanvas(int x, int y)
	{
		if (!client.isStretchedEnabled()) return new java.awt.Point(x, y);
		Dimension real = client.getRealDimensions(), stretched = client.getStretchedDimensions();
		return scale(x, y, real, stretched);
	}

	static java.awt.Point scale(int x, int y, Dimension real, Dimension stretched)
	{
		if (real.width == 0 || real.height == 0) return new java.awt.Point(x, y);
		return new java.awt.Point(x * stretched.width / real.width, y * stretched.height / real.height);
	}

	static void dispatch(Canvas canvas, int x, int y, int button)
	{
		if (canvas == null) return;
		int awtButton = button == Protocol.BUTTON_RIGHT ? MouseEvent.BUTTON3 : MouseEvent.BUTTON1;
		int mask = button == Protocol.BUTTON_RIGHT ? InputEvent.BUTTON3_DOWN_MASK : InputEvent.BUTTON1_DOWN_MASK;
		long t = System.currentTimeMillis();
		canvas.dispatchEvent(new MouseEvent(canvas, MouseEvent.MOUSE_MOVED, t, 0, x, y, 0, false, MouseEvent.NOBUTTON));
		canvas.dispatchEvent(new MouseEvent(canvas, MouseEvent.MOUSE_PRESSED, t, mask, x, y, 1, button == Protocol.BUTTON_RIGHT, awtButton));
		canvas.dispatchEvent(new MouseEvent(canvas, MouseEvent.MOUSE_RELEASED, t + 1, 0, x, y, 1, false, awtButton));
		canvas.dispatchEvent(new MouseEvent(canvas, MouseEvent.MOUSE_CLICKED, t + 1, 0, x, y, 1, false, awtButton));
	}

	private static byte[] ack(Protocol.Click c, int result, int x, int y)
	{
		return ack(c.seq, result, x, y);
	}

	private static byte[] ack(int seq, int result, int x, int y)
	{
		Protocol.Ack a = new Protocol.Ack();
		a.seq = seq;
		a.result = result;
		a.canvasX = x;
		a.canvasY = y;
		return Protocol.ack(a);
	}
}
