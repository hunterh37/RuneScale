package org.oldschool.runescape.runescale;

import java.awt.Graphics2D;
import java.awt.Image;
import java.awt.RenderingHints;
import java.awt.image.BufferedImage;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.function.Consumer;
import javax.imageio.IIOImage;
import javax.imageio.ImageIO;
import javax.imageio.ImageWriteParam;
import javax.imageio.ImageWriter;
import javax.imageio.stream.MemoryCacheImageOutputStream;
import lombok.extern.slf4j.Slf4j;
import net.runelite.api.Client;
import net.runelite.client.ui.DrawManager;

/**
 * Streams the rendered client canvas (every interface tab, chatbox, minimap, dialogs) as JPEG
 * UI_FRAME messages. One frame in flight at a time; encode runs off the client thread.
 */
@Slf4j
class InterfaceCapture
{
	static final float QUALITY = 0.72f;
	private static final long STUCK_MS = 2000;

	private final Client client;
	private final DrawManager drawManager;
	private final ExecutorService encoder = Executors.newSingleThreadExecutor(r ->
	{
		Thread t = new Thread(r, "runescale-ui-encode");
		t.setDaemon(true);
		return t;
	});
	private volatile boolean pending;
	private long requestedAt;
	private int seq;

	InterfaceCapture(Client client, DrawManager drawManager)
	{
		this.client = client;
		this.drawManager = drawManager;
	}

	/** Client thread. Requests the next drawn frame when the fps budget allows. */
	void tick(int fps, int maxWidth, Consumer<byte[]> sink)
	{
		long now = System.currentTimeMillis();
		if (pending && now - requestedAt < STUCK_MS) return;
		if (now - requestedAt < 1000L / Math.max(1, fps)) return;
		int cw = client.getCanvasWidth(), ch = client.getCanvasHeight();
		if (cw <= 0 || ch <= 0) return;
		pending = true;
		requestedAt = now;
		drawManager.requestNextFrameListener(img ->
		{
			BufferedImage scaled = scale(img, maxWidth);
			if (scaled == null)
			{
				pending = false;
				return;
			}
			encoder.execute(() ->
			{
				try
				{
					Protocol.UiFrame f = new Protocol.UiFrame();
					f.seq = ++seq;
					f.canvasWidth = cw;
					f.canvasHeight = ch;
					f.jpeg = jpeg(scaled, QUALITY);
					sink.accept(Protocol.uiFrame(f));
				}
				catch (Exception e)
				{
					log.debug("interface frame failed", e);
				}
				finally
				{
					pending = false;
				}
			});
		});
	}

	void shutdown()
	{
		encoder.shutdownNow();
	}

	static BufferedImage scale(Image img, int maxWidth)
	{
		int w = img.getWidth(null), h = img.getHeight(null);
		if (w <= 0 || h <= 0) return null;
		int tw = Math.min(w, maxWidth), th = Math.max(1, h * tw / w);
		BufferedImage out = new BufferedImage(tw, th, BufferedImage.TYPE_INT_RGB);
		Graphics2D g = out.createGraphics();
		g.setRenderingHint(RenderingHints.KEY_INTERPOLATION, RenderingHints.VALUE_INTERPOLATION_BILINEAR);
		g.drawImage(img, 0, 0, tw, th, null);
		g.dispose();
		return out;
	}

	static byte[] jpeg(BufferedImage img, float quality) throws IOException
	{
		ImageWriter w = ImageIO.getImageWritersByFormatName("jpeg").next();
		ByteArrayOutputStream bytes = new ByteArrayOutputStream(64 << 10);
		try (MemoryCacheImageOutputStream out = new MemoryCacheImageOutputStream(bytes))
		{
			w.setOutput(out);
			ImageWriteParam p = w.getDefaultWriteParam();
			p.setCompressionMode(ImageWriteParam.MODE_EXPLICIT);
			p.setCompressionQuality(quality);
			w.write(null, new IIOImage(img, null, null), p);
		}
		finally
		{
			w.dispose();
		}
		return bytes.toByteArray();
	}
}
