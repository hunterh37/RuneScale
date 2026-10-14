package org.oldschool.runescape.runescale;

import java.io.BufferedOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.OutputStream;
import lombok.extern.slf4j.Slf4j;

/**
 * Writes outgoing stream messages to a .rsrec file for offline replay in the headset app
 * (simulator launch argument {@code -replay <path>}). Format: per message {@code u32 length (LE)}
 * then the message bytes. UI_FRAME is skipped to keep files small.
 */
@Slf4j
class StreamRecorder
{
	private final OutputStream out;
	final File file;
	private long bytes;

	StreamRecorder(File file) throws IOException
	{
		File dir = file.getParentFile();
		if (dir != null && !dir.isDirectory() && !dir.mkdirs()) throw new IOException("mkdir " + dir);
		this.file = file;
		out = new BufferedOutputStream(new FileOutputStream(file), 1 << 16);
	}

	synchronized void write(byte[] msg)
	{
		if (msg.length >= 4 && (msg[3] & 0xFF) == Protocol.UI_FRAME) return;
		try
		{
			int n = msg.length;
			out.write(new byte[]{(byte) n, (byte) (n >> 8), (byte) (n >> 16), (byte) (n >> 24)});
			out.write(msg);
			bytes += 4 + n;
		}
		catch (IOException e)
		{
			log.warn("RuneScale recording write failed", e);
		}
	}

	synchronized void close()
	{
		try
		{
			out.close();
			log.info("RuneScale recording saved: {} ({} bytes)", file, bytes);
		}
		catch (IOException e)
		{
			log.warn("RuneScale recording close failed", e);
		}
	}
}
