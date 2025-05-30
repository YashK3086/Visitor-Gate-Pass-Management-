package screens;
import db.DatabaseConnection;
import javax.swing.*;
import javax.swing.table.DefaultTableModel;
import java.awt.*;
import java.sql.*;

public class VisitorStatusTable extends JFrame {
    private DefaultTableModel model = new DefaultTableModel(
        new String[]{"ID", "Visitor Name", "Status", "Entry Time", "Exit Time"}, 0);

    public VisitorStatusTable() {
        setTitle("Visitor Status Table");
        setSize(700, 400);
        setLocationRelativeTo(null);
        setDefaultCloseOperation(JFrame.DISPOSE_ON_CLOSE);

        JTable table = new JTable(model);
        loadStatusData();

        JButton toggle = new JButton("Toggle IN/OUT Status");
        toggle.addActionListener(e -> toggleStatus(table));

        JPanel panel = new JPanel(new BorderLayout());
        panel.add(new JScrollPane(table), BorderLayout.CENTER);
        panel.add(toggle, BorderLayout.SOUTH);

        add(panel);
        setVisible(true);
    }

    private void loadStatusData() {
        model.setRowCount(0);
        try (Connection conn = DatabaseConnection.getConnection()) {
            String sql = "SELECT vs.ID, v.Name, vs.Status, vs.Entry_Time, vs.Exit_Time " +
                         "FROM visitor_status vs JOIN visitor v ON vs.Visitor_ID = v.ID";
            ResultSet rs = conn.createStatement().executeQuery(sql);
            while(rs.next()) {
                model.addRow(new Object[] {
                    rs.getInt("ID"), rs.getString("Name"),
                    rs.getString("Status"),
                    rs.getTimestamp("Entry_Time"), rs.getTimestamp("Exit_Time")
                });
            }
        } catch (SQLException ex) {
            ex.printStackTrace();
        }
    }

    private void toggleStatus(JTable table) {
        int row = table.getSelectedRow();
        if(row == -1) {
            JOptionPane.showMessageDialog(this, "Select a row first!");
            return;
        }
        int id = (int)model.getValueAt(row, 0);
        String currentStatus = (String)model.getValueAt(row, 2);
        String newStatus = currentStatus.equalsIgnoreCase("IN") ? "OUT" : "IN";
        try (Connection conn = DatabaseConnection.getConnection()) {
            String sql = newStatus.equals("OUT") ?
                "UPDATE visitor_status SET Status=?, Exit_Time=NOW() WHERE ID=?" :
                "UPDATE visitor_status SET Status=?, Entry_Time=NOW(), Exit_Time=NULL WHERE ID=?";
            PreparedStatement ps = conn.prepareStatement(sql);
            ps.setString(1, newStatus);
            ps.setInt(2, id);
            ps.executeUpdate();
            JOptionPane.showMessageDialog(this, "Status updated to " + newStatus + "!");
            loadStatusData();
        } catch (SQLException ex) {
            ex.printStackTrace();
            JOptionPane.showMessageDialog(this, "DB Error: " + ex.getMessage());
        }
    }
}
