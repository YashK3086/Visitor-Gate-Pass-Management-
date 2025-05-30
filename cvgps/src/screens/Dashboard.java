package screens;
import java.awt.*;
import javax.swing.*;

public class Dashboard extends JFrame {

    public Dashboard() {
        setTitle("Dashboard");
        setSize(500, 350);
        setDefaultCloseOperation(JFrame.EXIT_ON_CLOSE);
        setLocationRelativeTo(null);

        JMenuBar menuBar = new JMenuBar();

        // --- Tables Menu ---
        JMenu tablesMenu = new JMenu("Tables");
        JMenuItem viewTables = new JMenuItem("View Entity Tables");
        viewTables.addActionListener(e -> new TableMenu());
        tablesMenu.add(viewTables);
        menuBar.add(tablesMenu);

        // --- Visitor Menu ---
        JMenu visitorMenu = new JMenu("Visitor Functions");
        JMenuItem addVisitor = new JMenuItem("Add Visitor Entry");
        addVisitor.addActionListener(e -> new AddVisitorForm().setVisible(true));
        JMenuItem visitorStatus = new JMenuItem("Visitor Status Table");
        visitorStatus.addActionListener(e -> new VisitorStatusTable().setVisible(true));
        visitorMenu.add(addVisitor);
        visitorMenu.add(visitorStatus);
        menuBar.add(visitorMenu);

        // --- Delivery Menu ---
        JMenu deliveryMenu = new JMenu("Delivery Functions");

        JMenuItem addDelivery = new JMenuItem("Add Delivery Entry");
        addDelivery.addActionListener(e -> new DeliveryPassForm().setVisible(true));
        deliveryMenu.add(addDelivery);

        // NEW: View All Delivery Passes Menu Item
        JMenuItem viewDeliveryPasses = new JMenuItem("View All Delivery Passes");
        viewDeliveryPasses.addActionListener(e -> new TableViewer("delivery_pass")); 
        deliveryMenu.add(viewDeliveryPasses);

        menuBar.add(deliveryMenu);


        // --- Notification Menu ---
        JMenu notificationMenu = new JMenu("Notifications");
        JMenuItem viewNotifications = new JMenuItem("View Notifications");
        viewNotifications.addActionListener(e -> new TableViewer("notification"));

        notificationMenu.add(viewNotifications);
        menuBar.add(notificationMenu);
        

        // --- Security Menu ---
        JMenu securityMenu = new JMenu("Security");
        JMenuItem accessControlItem = new JMenuItem("Access Control");
        accessControlItem.addActionListener(e -> new AccessControlForm().setVisible(true));
        securityMenu.add(accessControlItem);
        menuBar.add(securityMenu);

        // --- Vehicle Menu ---
        JMenu vehicleMenu = new JMenu("Vehicles");
        JMenuItem viewVehicles = new JMenuItem("View All Vehicles");
        viewVehicles.addActionListener(e -> new TableViewer("vehicles"));
        vehicleMenu.add(viewVehicles);
        menuBar.add(vehicleMenu);

        setJMenuBar(menuBar);

        BackgroundPanel bgPanel = new BackgroundPanel("lib\\background.jpg"); 
        bgPanel.setLayout(new BorderLayout());

        JLabel label = new JLabel("Welcome to the Corporate Visitor GatePass Dashboard!", SwingConstants.CENTER);
        label.setFont(new Font("Arial", Font.BOLD, 18));
        label.setForeground(Color.WHITE);
        bgPanel.add(label, BorderLayout.CENTER);

        setContentPane(bgPanel);


        setVisible(true);
    }
}
