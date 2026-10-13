package org.oldschool.runescape.runescale;

import com.google.inject.Provides;
import java.awt.Color;
import java.awt.Graphics2D;
import java.awt.image.BufferedImage;
import java.net.InetAddress;
import java.security.SecureRandom;
import javax.inject.Inject;
import javax.jmdns.JmDNS;
import javax.jmdns.ServiceInfo;
import lombok.extern.slf4j.Slf4j;
import net.runelite.api.Client;
import net.runelite.api.GameState;
import net.runelite.api.events.ClientTick;
import net.runelite.api.events.GameStateChanged;
import net.runelite.api.events.GameTick;
import net.runelite.client.config.ConfigManager;
import net.runelite.client.eventbus.Subscribe;
import net.runelite.client.events.ConfigChanged;
import net.runelite.client.plugins.Plugin;
import net.runelite.client.plugins.PluginDescriptor;
import net.runelite.client.ui.ClientToolbar;
import net.runelite.client.ui.NavigationButton;

/**
 * Streams nearby scene geometry to a paired headset on the LAN.
 * Read-only: no menu entries, no input, no client state mutation.
 */
@Slf4j
@PluginDescriptor(
	name = "RuneScale Stream",
	description = "Read-only local stream of nearby scene geometry for a Vision Pro viewer",
	tags = {"vr", "ar", "vision", "3d"}
)
public class RuneScaleStreamPlugin extends Plugin
{
	@Inject private Client client;
	@Inject private RuneScaleConfig config;
	@Inject private ConfigManager configManager;
	@Inject private ClientToolbar clientToolbar;

	private SceneCapture capture;
	private StreamServer server;
	private JmDNS jmdns;
	private RuneScalePanel panel;
	private NavigationButton navButton;
	private String token;
	private int tickCounter;
	private int clientTicks;

	@Provides
	RuneScaleConfig provideConfig(ConfigManager manager)
	{
		return manager.getConfig(RuneScaleConfig.class);
	}

	@Override
	protected void startUp()
	{
		token = config.token();
		if (token == null || token.length() != 6)
		{
			token = String.format("%06d", new SecureRandom().nextInt(1_000_000));
			configManager.setConfiguration(RuneScaleConfig.GROUP, "token", token);
		}
		capture = new SceneCapture(client);
		panel = new RuneScalePanel();
		navButton = NavigationButton.builder().tooltip("RuneScale Stream").icon(icon()).priority(9).panel(panel).build();
		clientToolbar.addNavigation(navButton);
		startServer();
	}

	@Override
	protected void shutDown()
	{
		stopServer();
		clientToolbar.removeNavigation(navButton);
		capture = null;
	}

	private void startServer()
	{
		int port = config.port();
		server = new StreamServer(port, token, this::refreshPanel);
		server.start();
		InetAddress lan = StreamServer.lanAddress();
		if (config.bonjour())
		{
			new Thread(() ->
			{
				try
				{
					jmdns = JmDNS.create(lan);
					jmdns.registerService(ServiceInfo.create("_runescale._tcp.local.", "RuneScale " + lan.getHostAddress(), port, "v=1"));
				}
				catch (Exception e)
				{
					log.warn("Bonjour advertise failed; use manual IP", e);
				}
			}, "runescale-mdns").start();
		}
		refreshPanel();
	}

	private void stopServer()
	{
		if (jmdns != null)
		{
			JmDNS j = jmdns;
			jmdns = null;
			new Thread(() ->
			{
				try { j.unregisterAllServices(); j.close(); } catch (Exception ignored) { }
			}, "runescale-mdns-stop").start();
		}
		if (server != null)
		{
			try { server.stop(500); } catch (InterruptedException e) { Thread.currentThread().interrupt(); }
			server = null;
		}
	}

	private void refreshPanel()
	{
		if (panel == null || server == null) return;
		panel.update(StreamServer.lanAddress().getHostAddress() + ":" + config.port(), token,
			server.clientCount() + " headset(s) connected");
	}

	@Subscribe
	public void onConfigChanged(ConfigChanged e)
	{
		if (!RuneScaleConfig.GROUP.equals(e.getGroup()) || "token".equals(e.getKey())) return;
		if ("port".equals(e.getKey()) || "bonjour".equals(e.getKey()))
		{
			stopServer();
			startServer();
		}
		if (capture != null) capture.invalidate();
	}

	@Subscribe
	public void onGameStateChanged(GameStateChanged e)
	{
		if (e.getGameState() == GameState.LOADING && capture != null) capture.invalidate();
	}

	@Subscribe
	public void onGameTick(GameTick e)
	{
		if (server == null || capture == null || server.clientCount() == 0) return;
		boolean resync = server.takeResync();
		if (resync) server.broadcast(Protocol.hello(config.radius()));
		if (resync || ++tickCounter >= config.staticInterval())
		{
			tickCounter = 0;
			capture.captureStatic(config.radius(), resync, server::broadcast);
		}
	}

	@Subscribe
	public void onClientTick(ClientTick e)
	{
		// ~25 Hz actor frames (client ticks run at 50 Hz)
		if (server == null || capture == null || server.clientCount() == 0 || (++clientTicks & 1) != 0) return;
		capture.captureFrame(config.radius(), server::broadcast);
	}

	private static BufferedImage icon()
	{
		BufferedImage img = new BufferedImage(16, 16, BufferedImage.TYPE_INT_ARGB);
		Graphics2D g = img.createGraphics();
		g.setColor(new Color(0x3FA7D6));
		g.fillRoundRect(1, 4, 14, 8, 6, 6);
		g.setColor(Color.BLACK);
		g.fillOval(3, 6, 4, 4);
		g.fillOval(9, 6, 4, 4);
		g.dispose();
		return img;
	}
}
