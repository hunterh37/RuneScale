package org.oldschool.runescape.runescale;

import java.net.Inet4Address;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.NetworkInterface;
import java.nio.ByteBuffer;
import java.util.function.BiConsumer;
import java.util.function.Consumer;
import java.util.Collections;
import java.util.concurrent.atomic.AtomicBoolean;
import lombok.extern.slf4j.Slf4j;
import org.java_websocket.WebSocket;
import org.java_websocket.handshake.ClientHandshake;
import org.java_websocket.server.WebSocketServer;

/**
 * LAN-only WebSocket server. Inbound CLICK / UI_CLICK messages are passed to {@code onClick} / {@code onUiClick};
 * the plugin drops them unless headset input is enabled. Everything else inbound is ignored.
 */
@Slf4j
class StreamServer extends WebSocketServer
{
	private final String token;
	private final AtomicBoolean resyncRequested = new AtomicBoolean();
	private final Runnable onChange;
	private final BiConsumer<Protocol.Click, Consumer<byte[]>> onClick;
	private final BiConsumer<Protocol.UiClick, Consumer<byte[]>> onUiClick;

	StreamServer(int port, String token, Runnable onChange, BiConsumer<Protocol.Click, Consumer<byte[]>> onClick,
		BiConsumer<Protocol.UiClick, Consumer<byte[]>> onUiClick)
	{
		super(new InetSocketAddress(port));
		this.onClick = onClick;
		this.onUiClick = onUiClick;
		this.token = token;
		this.onChange = onChange;
		setReuseAddr(true);
		setConnectionLostTimeout(15);
	}

	@Override
	public void onOpen(WebSocket conn, ClientHandshake handshake)
	{
		InetAddress remote = conn.getRemoteSocketAddress().getAddress();
		if (!isLocal(remote))
		{
			conn.close(4003, "LAN only");
			return;
		}
		String desc = handshake.getResourceDescriptor();
		String header = handshake.getFieldValue("X-RuneScale-Token");
		boolean ok = token.equals(header) || (desc != null && desc.contains("token=" + token));
		if (!ok)
		{
			conn.close(4001, "bad token");
			return;
		}
		log.info("RuneScale client connected: {}", remote);
		resyncRequested.set(true);
		onChange.run();
	}

	static boolean isLocal(InetAddress a)
	{
		return a.isLoopbackAddress() || a.isSiteLocalAddress() || a.isLinkLocalAddress()
			|| (a.getAddress().length == 16 && (a.getAddress()[0] & 0xFE) == 0xFC); // IPv6 ULA
	}

	boolean takeResync()
	{
		return resyncRequested.getAndSet(false);
	}

	int clientCount()
	{
		return getConnections().size();
	}

	@Override
	public void onClose(WebSocket conn, int code, String reason, boolean remote)
	{
		onChange.run();
	}

	@Override
	public void onMessage(WebSocket conn, String message)
	{
		// text frames are not part of the protocol
	}

	@Override
	public void onMessage(WebSocket conn, ByteBuffer message)
	{
		byte[] data = new byte[message.remaining()];
		message.get(data);
		Protocol.Decoded d;
		try
		{
			d = Protocol.decode(data);
		}
		catch (RuntimeException e)
		{
			return;
		}
		Consumer<byte[]> reply = bytes ->
		{
			if (conn.isOpen()) conn.send(bytes);
		};
		if (d.type == Protocol.CLICK) onClick.accept(d.click, reply);
		else if (d.type == Protocol.UI_CLICK) onUiClick.accept(d.uiClick, reply);
	}

	@Override
	public void onError(WebSocket conn, Exception ex)
	{
		log.debug("RuneScale socket error", ex);
	}

	@Override
	public void onStart()
	{
		log.info("RuneScale stream listening on {}", getPort());
	}

	static InetAddress lanAddress()
	{
		try
		{
			for (NetworkInterface ni : Collections.list(NetworkInterface.getNetworkInterfaces()))
			{
				if (!ni.isUp() || ni.isLoopback() || ni.isVirtual() || ni.isPointToPoint() || ni.getName().startsWith("utun")) continue;
				for (InetAddress a : Collections.list(ni.getInetAddresses()))
				{
					if (a instanceof Inet4Address && a.isSiteLocalAddress()) return a;
				}
			}
			return InetAddress.getLocalHost();
		}
		catch (Exception e)
		{
			return InetAddress.getLoopbackAddress();
		}
	}
}
