package screens;

import db.DatabaseConnection;
import javax.swing.*;
import java.awt.*;
import java.sql.*;

public class AccessControlForm extends JFrame {
    private JComboBox<String> securityCombo;
    private JComboBox<String> gatePassCombo;
    private JTextField locationField;

    public AccessControlForm() {
        setTitle("Access Control Management");
        setSize(500, 200);
        setLocationRelativeTo(null);
        setDefaultCloseOperation(JFrame.DISPOSE_ON_CLOSE);

        JPanel mainPanel = new JPanel(new GridLayout(4, 2, 10, 10));
        
        // Security Selection
        mainPanel.add(new JLabel("Security Guard:"));
        securityCombo = new JComboBox<>();
        loadSecurityGuards();
        mainPanel.add(securityCombo);

        // Gate Pass Selection
        mainPanel.add(new JLabel("Gate Pass:"));
        gatePassCombo = new JComboBox<>();
        loadActiveGatePasses();
        mainPanel.add(gatePassCombo);

        // Location Input
        mainPanel.add(new JLabel("Assigned Location:"));
        locationField = new JTextField();
        mainPanel.add(locationField);

        JButton submitButton = new JButton("Assign Location");
        submitButton.addActionListener(e -> assignLocation());
        
        add(mainPanel, BorderLayout.CENTER);
        add(submitButton, BorderLayout.SOUTH);
    }

    private void loadSecurityGuards() {
        try (Connection conn = DatabaseConnection.getConnection()) {
            String sql = "SELECT UID, Name FROM security";
            ResultSet rs = conn.createStatement().executeQuery(sql);
            while(rs.next()) {
                securityCombo.addItem(rs.getInt("UID") + " - " + rs.getString("Name"));
            }
        } catch (SQLException ex) {
            ex.printStackTrace();
        }
    }

    private void loadActiveGatePasses() {
        try (Connection conn = DatabaseConnection.getConnection()) {
            // Clear existing items first
            gatePassCombo.removeAllItems();
            
            // Modified SQL query with proper joins and conditions
            String sql = "SELECT gp.pass_id, v.Name, gp.Visitor_ID "
                       + "FROM gate_pass gp "
                       + "LEFT JOIN access_control ac ON gp.pass_id = ac.GatePass_UID "
                       + "JOIN visitor v ON gp.Visitor_ID = v.ID "
                       + "WHERE ac.GatePass_UID IS NULL";
            
            Statement stmt = conn.createStatement();
            ResultSet rs = stmt.executeQuery(sql);
            
            // Add debugging output
            System.out.println("Loading active gate passes...");
            boolean hasResults = false;
            
            while(rs.next()) {
                hasResults = true;
                String displayText = rs.getInt("pass_id") + " - " 
                                   + rs.getString("Name") + " (Visitor ID: " 
                                   + rs.getInt("Visitor_ID") + ")";
                gatePassCombo.addItem(displayText);
                System.out.println("Added gate pass: " + displayText);
            }
            
            if (!hasResults) {
                System.out.println("No unassigned gate passes found");
                JOptionPane.showMessageDialog(this, "No unassigned gate passes available!");
                dispose();
            }
            
        } catch (SQLException ex) {
            ex.printStackTrace();
            JOptionPane.showMessageDialog(this, "Error loading gate passes: " + ex.getMessage());
        }
    }
    

    private void assignLocation() {
        try {
            int securityUID = Integer.parseInt(securityCombo.getSelectedItem().toString().split(" - ")[0]);
            int gatePassUID = Integer.parseInt(gatePassCombo.getSelectedItem().toString().split(" - ")[0]);
            String location = locationField.getText().trim();

            if(location.isEmpty()) {
                JOptionPane.showMessageDialog(this, "Please enter a location!");
                return;
            }

            try (Connection conn = DatabaseConnection.getConnection()) {
                String sql = "INSERT INTO access_control (Security_UID, GatePass_UID, Location) VALUES (?, ?, ?)";
                PreparedStatement pstmt = conn.prepareStatement(sql);
                pstmt.setInt(1, securityUID);
                pstmt.setInt(2, gatePassUID);
                pstmt.setString(3, location);
                
                pstmt.executeUpdate();
                JOptionPane.showMessageDialog(this, "Access control record created!");
                dispose();
            }
        } catch (Exception ex) {
            ex.printStackTrace();
            JOptionPane.showMessageDialog(this, "Error: " + ex.getMessage());
        }
    }
}
