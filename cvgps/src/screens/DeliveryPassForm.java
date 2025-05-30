// 2. New DeliveryPassForm.java
package screens;

import db.DatabaseConnection;
import javax.swing.*;
import java.awt.*;
import java.sql.*;

public class DeliveryPassForm extends JFrame {
    private JTextField nameField, contactField, parcelIdField;
    private JComboBox<String> securityCombo;

    public DeliveryPassForm() {
        setTitle("Delivery Pass Entry");
        setSize(400, 300);
        setLocationRelativeTo(null);
        setDefaultCloseOperation(JFrame.DISPOSE_ON_CLOSE);

        JPanel panel = new JPanel(new GridLayout(0, 2, 5, 5));
        
        nameField = new JTextField();
        contactField = new JTextField();
        parcelIdField = new JTextField();
        
        panel.add(new JLabel("Delivery Person Name:"));
        panel.add(nameField);
        panel.add(new JLabel("Contact Number:"));
        panel.add(contactField);
        panel.add(new JLabel("Parcel ID:"));
        panel.add(parcelIdField);
        
        panel.add(new JLabel("Security Guard:"));
        securityCombo = new JComboBox<>();
        loadSecurity();
        panel.add(securityCombo);

        JButton submit = new JButton("Create Delivery Pass");
        submit.addActionListener(e -> createDeliveryPass());
        
        add(panel, BorderLayout.CENTER);
        add(submit, BorderLayout.SOUTH);
    }

    private void loadSecurity() {
        try (Connection conn = DatabaseConnection.getConnection()) {
            Statement stmt = conn.createStatement();
            ResultSet rs = stmt.executeQuery("SELECT UID, Name FROM security");
            while (rs.next()) {
                securityCombo.addItem(rs.getInt("UID") + " - " + rs.getString("Name"));
            }
        } catch (SQLException ex) {
            ex.printStackTrace();
        }
    }

    private void createDeliveryPass() {
        String name = nameField.getText().trim();
        String contact = contactField.getText().trim();
        String parcelId = parcelIdField.getText().trim();
        int securityId = Integer.parseInt(securityCombo.getSelectedItem().toString().split(" - ")[0]);

        try (Connection conn = DatabaseConnection.getConnection()) {
            PreparedStatement stmt = conn.prepareStatement(
                "INSERT INTO delivery_pass (Parcel_ID, Name, Date_Time, Security_UID) VALUES (?, ?, NOW(), ?)"
            );
            stmt.setString(1, parcelId);
            stmt.setString(2, name);
            stmt.setInt(3, securityId);
            
            stmt.executeUpdate();
            JOptionPane.showMessageDialog(this, "Delivery pass created successfully!");
            dispose();
        } catch (SQLException ex) {
            ex.printStackTrace();
            JOptionPane.showMessageDialog(this, "Database Error: " + ex.getMessage());
        }
    }
}
