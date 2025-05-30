package screens;

import db.DatabaseConnection;
import javax.swing.*;
import java.awt.*;
import java.sql.*;

public class TableViewer extends JFrame {
    public TableViewer(String tableName) {
        setTitle("Viewing " + tableName);
        setSize(600, 400);
        setDefaultCloseOperation(JFrame.DISPOSE_ON_CLOSE);
        setLocationRelativeTo(null);

        try (Connection conn = DatabaseConnection.getConnection()) {
            Statement stmt = conn.createStatement(ResultSet.TYPE_SCROLL_INSENSITIVE, ResultSet.CONCUR_READ_ONLY);
            ResultSet rs = stmt.executeQuery("SELECT * FROM " + tableName);
            
            ResultSetMetaData rsmd = rs.getMetaData();
            int cols = rsmd.getColumnCount();
            String[] column = new String[cols];
            
            for (int i = 0; i < cols; i++) {
                column[i] = rsmd.getColumnName(i + 1);
            }

            // Get row count properly
            rs.last();
            int rows = rs.getRow();
            rs.beforeFirst();
            
            Object[][] data = new Object[rows][cols];
            int count = 0;
            while (rs.next()) {
                for (int i = 0; i < cols; i++) {
                    data[count][i] = rs.getObject(i + 1);
                }
                count++;
            }

            JTable table = new JTable(data, column);
            JScrollPane sp = new JScrollPane(table);
            add(sp);
            
        } catch (SQLException e) {
            e.printStackTrace();
            JOptionPane.showMessageDialog(this, "Error loading table: " + e.getMessage());
        }

        setVisible(true);
    }
}
