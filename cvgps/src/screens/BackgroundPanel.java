package screens;
import javax.swing.*;
import java.awt.*;

public class BackgroundPanel extends JPanel {
    private Image background;

    public BackgroundPanel(String imagePath) {
        // Try both file path and resource loading
        try {
            background = new ImageIcon(getClass().getResource(imagePath)).getImage();
        } catch (Exception e) {
            background = Toolkit.getDefaultToolkit().createImage(imagePath);
        }
    }

    @Override
    protected void paintComponent(Graphics g) {
        super.paintComponent(g);
        if(background != null) {
            g.drawImage(background, 0, 0, getWidth(), getHeight(), this);
        }
    }
}
