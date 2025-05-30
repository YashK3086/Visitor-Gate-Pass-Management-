// 1. Updated AddVisitorForm.java
package screens;

import db.DatabaseConnection;
import javax.swing.*;
import java.awt.*;
import java.awt.event.*;
import java.sql.*;

public class AddVisitorForm extends JFrame {
    private JTextField nameField, contactField;
    private JTextArea purposeArea;
    private JCheckBox vehicleCheck;
    private JTextField regNumberField, makeField;
    private JComboBox<String> employeeCombo;

    public AddVisitorForm() {
        setTitle("Add Visitor Entry");
        setSize(500, 400);
        setLocationRelativeTo(null);
        setDefaultCloseOperation(JFrame.DISPOSE_ON_CLOSE);

        JPanel mainPanel = new JPanel(new BorderLayout(10, 10));
        JPanel formPanel = new JPanel(new GridLayout(0, 2, 5, 5));

        // Visitor Details
        nameField = new JTextField();
        contactField = new JTextField();
        purposeArea = new JTextArea(3, 15);
        
        formPanel.add(new JLabel("Name:"));
        formPanel.add(nameField);
        formPanel.add(new JLabel("Contact:"));
        formPanel.add(contactField);
        formPanel.add(new JLabel("Purpose:"));
        formPanel.add(new JScrollPane(purposeArea));

        // Employee Selection
        formPanel.add(new JLabel("Responsible Employee:"));
        employeeCombo = new JComboBox<>();
        loadEmployees();
        formPanel.add(employeeCombo);

        // Vehicle Details
        vehicleCheck = new JCheckBox("Has Vehicle?");
        regNumberField = new JTextField();
        makeField = new JTextField();
        
        JPanel vehiclePanel = new JPanel(new GridLayout(2, 2, 5, 5));
        vehiclePanel.add(new JLabel("Registration Number:"));
        vehiclePanel.add(regNumberField);
        vehiclePanel.add(new JLabel("Vehicle Make:"));
        vehiclePanel.add(makeField);
        vehiclePanel.setVisible(false);

        vehicleCheck.addItemListener(e -> {
            vehiclePanel.setVisible(e.getStateChange() == ItemEvent.SELECTED);
            revalidate();
            repaint();
        });

        mainPanel.add(formPanel, BorderLayout.NORTH);
        mainPanel.add(vehicleCheck, BorderLayout.CENTER);
        mainPanel.add(vehiclePanel, BorderLayout.SOUTH);

        JButton submit = new JButton("Submit Entry");
        submit.addActionListener(e -> handleAddVisitor());
        
        add(mainPanel);
        add(submit, BorderLayout.SOUTH);
    }

    private void loadEmployees() {
        try (Connection conn = DatabaseConnection.getConnection()) {
            Statement stmt = conn.createStatement();
            ResultSet rs = stmt.executeQuery("SELECT Employee_ID, Name FROM employee");
            while (rs.next()) {
                employeeCombo.addItem(rs.getInt("Employee_ID") + " - " + rs.getString("Name"));
            }
        } catch (SQLException ex) {
            ex.printStackTrace();
        }
    }

    private void handleAddVisitor() {
        String name = nameField.getText().trim();
        String contact = contactField.getText().trim();
        String purpose = purposeArea.getText().trim();
        int empId = Integer.parseInt(employeeCombo.getSelectedItem().toString().split(" - ")[0]);
    
        if (name.isEmpty() || contact.isEmpty() || purpose.isEmpty()) {
            JOptionPane.showMessageDialog(this, "Please fill all required fields!");
            return;
        }
    
        try (Connection conn = DatabaseConnection.getConnection()) {
            conn.setAutoCommit(false);
    
            // Insert into visitor table
            PreparedStatement visitorStmt = conn.prepareStatement(
                "INSERT INTO visitor (Name, Contact, Purpose) VALUES (?, ?, ?)",
                Statement.RETURN_GENERATED_KEYS
            );
            visitorStmt.setString(1, name);
            visitorStmt.setString(2, contact);
            visitorStmt.setString(3, purpose);
            visitorStmt.executeUpdate();
    
            ResultSet rs = visitorStmt.getGeneratedKeys();
            int visitorId = rs.next() ? rs.getInt(1) : -1;
    
            // --- Insert into visitor_status ---
            PreparedStatement statusStmt = conn.prepareStatement(
                "INSERT INTO visitor_status (Visitor_ID, Entry_Time, Status) VALUES (?, NOW(), 'IN')"
            );
            statusStmt.setInt(1, visitorId);
            statusStmt.executeUpdate();
    
            // Insert visit log
            PreparedStatement logStmt = conn.prepareStatement(
                "INSERT INTO visit_logs (EMP_ID, Date, Time) VALUES (?, CURDATE(), CURTIME())"
            );
            logStmt.setInt(1, empId);
            logStmt.executeUpdate();
    
            // Insert vehicle if needed
            if (vehicleCheck.isSelected()) {
                PreparedStatement vehicleStmt = conn.prepareStatement(
                    "INSERT INTO vehicles (Registration_Number, Make, Name, Contact, Date_Time) VALUES (?, ?, ?, ?, NOW())"
                );
                vehicleStmt.setString(1, regNumberField.getText().trim());
                vehicleStmt.setString(2, makeField.getText().trim());
                vehicleStmt.setString(3, name);
                vehicleStmt.setString(4, contact);
                vehicleStmt.executeUpdate();
            }
    
            conn.commit();
            JOptionPane.showMessageDialog(this, "Visitor entry created successfully!");
            new IssueGatePassForm(name, contact, visitorId);
  
            dispose();

            dispose();
        } catch (SQLException ex) {
            ex.printStackTrace();
            JOptionPane.showMessageDialog(this, "Database Error: " + ex.getMessage());
        }
    }
    
    }
