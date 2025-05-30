package screens;

import db.DatabaseConnection;
import javax.swing.*;
import javax.swing.table.DefaultTableModel;
import java.awt.*;
import java.sql.*;

public class NotificationTable extends JFrame {
    private DefaultTableModel model = new DefaultTableModel(
        new String[]{"ID", "Entry", "Exit_Time", "Contact"}, 0);

    public NotificationTable() {
        setTitle("Notifications");
        setSize(700, 400);
        setLocationRelativeTo(null);
        setDefaultCloseOperation(JFrame.DISPOSE_ON_CLOSE);

        JTable table = new JTable(model);
        loadNotifications();

        add(new JScrollPane(table), BorderLayout.CENTER);
        setVisible(true);
    }

    private void loadNotifications() {
        model.setRowCount(0);
        try (Connection conn = DatabaseConnection.getConnection()) {
            String sql = "SELECT ID, Entry, Exit_Time, Contact FROM notification ORDER BY Entry DESC";
            ResultSet rs = conn.createStatement().executeQuery(sql);
            while (rs.next()) {
                model.addRow(new Object[]{
                    rs.getInt("ID"),
                    rs.getTimestamp("Entry"),
                    rs.getTimestamp("Exit_Time"),
                    rs.getString("Contact")
                });
            }
        } catch (SQLException ex) {
            ex.printStackTrace();
        }
    }
}
