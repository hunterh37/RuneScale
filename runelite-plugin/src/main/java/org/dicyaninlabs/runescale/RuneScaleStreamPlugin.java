package org.oldschool.runescape.runescale;

import com.google.inject.Provides;
import java.awt.Color;
import java.awt.Graphics2D;
import java.awt.image.BufferedImage;
import java.io.File;
import java.text.SimpleDateFormat;
import java.util.Date;
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
import net.runelite.api.events.ItemContainerChanged;
import net.runelite.client.game.ItemManager;
import net.runelite.client.callback.ClientThread;
import net.runelite.client.config.ConfigManager;
import net.runelite.client.eventbus.Subscribe;
import net.runelite.client.events.ConfigChanged;
import net.runelite.client.plugins.Plugin;
import net.runelite.client.plugins.PluginDescriptor;
import net.runelite.client.ui.ClientToolbar;
import net.runelite.client.ui.DrawManager;
import net.runelite.client.ui.NavigationButton;
import net.runelite.client.RuneLite;

/**
 * Streams nearby scene geometry to a paired headset on the LAN.
 * No menu entries or client state mutation. Headset taps become canvas clicks only when
 * the "Headset input" option is on (off by default).
 */
@Slf4j
@PluginDescriptor(
	name = "RuneScale Stream",
	description = "Local stream of nearby scene geometry to a Vision Pro viewer, optional headset clicks",
	tags = {"vr", "ar", "vision", "3d"}
)
public class RuneScaleStreamPlugin extends Plugin
{
	@Inject private Client client;
	@Inject private RuneScaleConfig config;
	@Inject private ConfigManager configManager;
	@Inject private ClientToolbar clientToolbar;
	@Inject private ClientThread clientThread;
	@Inject private DrawManager drawManager;
	@Inject private ItemManager itemManager;

	private SceneCapture capture;
	private RemoteInput input;
	private InterfaceCapture ui;
	private ItemSync items;
	private StreamServer server;
	private JmDNS jmdns;
	private RuneScalePanel panel;
	private NavigationButton navButton;
	private String token;
	private int tickCounter;
	private int clientTicks;
	private volatile StreamRecorder recorder;
	private boolean recordResync;

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
		input = new RemoteInput(client, clientThread);
		ui = new InterfaceCapture(client, drawManager);
		items = new ItemSync(client, itemManager);
		panel = new RuneScalePanel();
		navButton = NavigationButton.builder().tooltip("RuneScale Stream").icon(icon()).priority(9).panel(panel).build();
		clientToolbar.addNavigation(navButton);
		startServer();
		updateRecorder();
	}

	@Override
	protected void shutDown()
	{
		stopRecorder();
		stopServer();
		clientToolbar.removeNavigation(navButton);
		if (ui != null) ui.shutdown();
		ui = null;
		capture = null;
	}

	private void startServer()
	{
		int port = config.port();
		server = new StreamServer(port, token, this::refreshPanel,
			(click, reply) -> input.handle(click, config.remoteInput(), reply),
			(click, reply) -> input.handleUi(click, config.remoteInput(), reply),
			(click, reply) -> input.handleWidget(click, config.remoteInput(), reply));
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
		if ("recordStream".equals(e.getKey())) updateRecorder();
		if (capture != null) capture.invalidate();
	}

	/** Sends to headsets and, when recording, appends to the .rsrec file. */
	private void emit(byte[] msg)
	{
		StreamServer s = server;
		if (s != null) s.broadcast(msg);
		StreamRecorder r = recorder;
		if (r != null) r.write(msg);
	}

	private boolean active()
	{
		return server != null && (server.clientCount() > 0 || recorder != null);
	}

	private void updateRecorder()
	{
		if (config.recordStream() == (recorder != null)) return;
		if (!config.recordStream())
		{
			stopRecorder();
			return;
		}
		String name = "capture-" + new SimpleDateFormat("yyyyMMdd-HHmmss").format(new Date()) + ".rsrec";
		try
		{
			recorder = new StreamRecorder(new File(new File(RuneLite.RUNELITE_DIR, "runescale"), name));
			recordResync = true;
			log.info("RuneScale recording to {}", recorder.file);
		}
		catch (Exception ex)
		{
			log.warn("RuneScale recording failed to start", ex);
		}
	}

	private void stopRecorder()
	{
		StreamRecorder r = recorder;
		recorder = null;
		if (r != null) r.close();
	}

	@Subscribe
	public void onGameStateChanged(GameStateChanged e)
	{
		if (e.getGameState() == GameState.LOADING && capture != null) capture.invalidate();
	}

	@Subscribe
	public void onItemContainerChanged(ItemContainerChanged e)
	{
		if (items == null || !active()) return;
		items.send(e.getContainerId(), this::emit);
	}

	@Subscribe
	public void onGameTick(GameTick e)
	{
		if (capture == null || !active()) return;
		boolean resync = server.takeResync() | recordResync;
		recordResync = false;
		if (resync)
		{
			emit(Protocol.hello(config.radius()));
			items.reset();
			items.sendAll(this::emit);
		}
		if (resync || ++tickCounter >= config.staticInterval())
		{
			tickCounter = 0;
			capture.captureStatic(config.radius(), resync, this::emit);
		}
	}

	@Subscribe
	public void onClientTick(ClientTick e)
	{
		if (capture == null || !active()) return;
		if (ui != null && config.streamInterface() && server.clientCount() > 0) ui.tick(config.interfaceFps(), config.interfaceWidth(), this::emit);
		// ~25 Hz actor frames (client ticks run at 50 Hz)
		if ((++clientTicks & 1) != 0) return;
		capture.captureFrame(config.radius(), this::emit);
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
