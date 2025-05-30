package screens;

import db.DatabaseConnection;
import javax.swing.*;
import java.awt.*;
import java.sql.*;

public class IssueGatePassForm extends JFrame {
    private JComboBox<String> securityCombo;
    private final String visitorName;
    private final String visitorContact;
    private final int visitorId; // Added visitorId field

    // Modified constructor to accept visitorId
    public IssueGatePassForm(String visitorName, String visitorContact, int visitorId) {
        this.visitorName = visitorName;
        this.visitorContact = visitorContact;
        this.visitorId = visitorId; // Store visitor ID
        
        setTitle("Issue Gate Pass - " + visitorName);
        setSize(400, 200);
        setLocationRelativeTo(null);
        setDefaultCloseOperation(JFrame.DISPOSE_ON_CLOSE);

        JPanel mainPanel = new JPanel(new BorderLayout(10, 10));
        JPanel infoPanel = new JPanel(new GridLayout(3, 1, 5, 5)); // Changed to 3 rows
        JPanel formPanel = new JPanel(new GridLayout(1, 2, 5, 5));

        // Visitor Info (non-editable)
        infoPanel.add(new JLabel("Visitor: " + visitorName));
        infoPanel.add(new JLabel("Contact: " + visitorContact));
        infoPanel.add(new JLabel("Visitor ID: " + visitorId)); // Display visitor ID

        // Security Selection
        formPanel.add(new JLabel("Security Guard:"));
        securityCombo = new JComboBox<>();
        loadSecurityGuards();
        formPanel.add(securityCombo);

        JButton submitButton = new JButton("Issue Gate Pass");
        submitButton.addActionListener(e -> issueGatePass());

        mainPanel.add(infoPanel, BorderLayout.NORTH);
        mainPanel.add(formPanel, BorderLayout.CENTER);
        mainPanel.add(submitButton, BorderLayout.SOUTH);
        
        add(mainPanel);
        setVisible(true);
    }

    private void loadSecurityGuards() {
        securityCombo.removeAllItems();
        try (Connection conn = DatabaseConnection.getConnection()) {
            String sql = "SELECT UID, Name FROM security ORDER BY Name";
            Statement stmt = conn.createStatement();
            ResultSet rs = stmt.executeQuery(sql);
            
            while (rs.next()) {
                securityCombo.addItem(rs.getInt("UID") + " - " + rs.getString("Name"));
            }
        } catch (SQLException ex) {
            ex.printStackTrace();
            JOptionPane.showMessageDialog(this, "Error loading security guards: " + ex.getMessage());
        }
    }

    private void issueGatePass() {
        String selectedSecurity = (String) securityCombo.getSelectedItem();
        
        if (selectedSecurity == null || selectedSecurity.isEmpty()) {
            JOptionPane.showMessageDialog(this, "Please select a security guard!");
            return;
        }

        try {
            int securityUID = Integer.parseInt(selectedSecurity.split(" - ")[0]);
            
            try (Connection conn = DatabaseConnection.getConnection()) {
                // Modified SQL to include Visitor_ID
                String sql = "INSERT INTO gate_pass (UID, Name, Contact, Visitor_ID) VALUES (?, ?, ?, ?)";
                PreparedStatement pstmt = conn.prepareStatement(sql);
                pstmt.setInt(1, securityUID);
                pstmt.setString(2, visitorName);
                pstmt.setString(3, visitorContact);
                pstmt.setInt(4, visitorId); // Added visitorId parameter
                
                int rowsAffected = pstmt.executeUpdate();
                if (rowsAffected > 0) {
                    JOptionPane.showMessageDialog(this, "Gate pass issued successfully!");
                    dispose();
                }
            } catch (SQLException ex) {
                JOptionPane.showMessageDialog(this, "Database error: " + ex.getMessage());
                ex.printStackTrace();
            }
        } catch (NumberFormatException ex) {
            JOptionPane.showMessageDialog(this, "Invalid security selection!");
        }
    }
}
// This code is a part of the visitor management system, specifically for issuing gate passes to visitors.