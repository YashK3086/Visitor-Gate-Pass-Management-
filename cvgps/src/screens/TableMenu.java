package screens;

import javax.swing.*;

public class TableMenu extends JFrame {

    public TableMenu() {
        setTitle("Tables");
        setSize(300, 400);
        setDefaultCloseOperation(JFrame.DISPOSE_ON_CLOSE);
        setLocationRelativeTo(null);

        JPanel panel = new JPanel();
        panel.setLayout(new BoxLayout(panel, BoxLayout.Y_AXIS));
        
        String[] tables = {"visitor", "employee", "security", "vehicles", "gate_pass", "notification"};
        
        for (String table : tables) {
            JButton button = new JButton(table.toUpperCase());
            button.addActionListener(e -> new TableViewer(table));
            panel.add(button);
        }
        
        add(panel);
        setVisible(true);
    }
}
