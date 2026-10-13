package org.oldschool.runescape.runescale;

import java.awt.BorderLayout;
import java.awt.Font;
import java.awt.GridLayout;
import javax.swing.JLabel;
import javax.swing.JPanel;
import javax.swing.SwingUtilities;
import javax.swing.border.EmptyBorder;
import net.runelite.client.ui.PluginPanel;

class RuneScalePanel extends PluginPanel
{
	private final JLabel host = new JLabel();
	private final JLabel token = new JLabel();
	private final JLabel status = new JLabel();

	RuneScalePanel()
	{
		setLayout(new BorderLayout());
		setBorder(new EmptyBorder(10, 10, 10, 10));
		JPanel grid = new JPanel(new GridLayout(0, 1, 0, 6));
		grid.add(new JLabel("RuneScale Stream (read-only)"));
		grid.add(new JLabel("Host"));
		grid.add(host);
		grid.add(new JLabel("Pairing token"));
		token.setFont(token.getFont().deriveFont(Font.BOLD, 22f));
		grid.add(token);
		grid.add(status);
		add(grid, BorderLayout.NORTH);
	}

	void update(String hostText, String tokenText, String statusText)
	{
		SwingUtilities.invokeLater(() ->
		{
			host.setText(hostText);
			token.setText(tokenText);
			status.setText(statusText);
		});
	}
}
