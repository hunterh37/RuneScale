package org.oldschool.runescape.runescale;

import java.net.Inet4Address;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.NetworkInterface;
import java.util.Collections;
import java.util.concurrent.atomic.AtomicBoolean;
import lombok.extern.slf4j.Slf4j;
import org.java_websocket.WebSocket;
import org.java_websocket.handshake.ClientHandshake;
import org.java_websocket.server.WebSocketServer;

/**
 * LAN-only WebSocket server. Outbound only: inbound messages from clients are ignored,
 * so nothing a headset sends can reach the game client.
 */
@Slf4j
class StreamServer extends WebSocketServer
{
	private final String token;
	private final AtomicBoolean resyncRequested = new AtomicBoolean();
	private final Runnable onChange;

	StreamServer(int port, String token, Runnable onChange)
	{
		super(new InetSocketAddress(port));
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
		// read-only stream: ignore
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
				if (!ni.isUp() || ni.isLoopback() || ni.isVirtual()) continue;
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
