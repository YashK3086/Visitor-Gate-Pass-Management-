-- ============================================================
-- Corporate Gate Pass System — MySQL Schema
-- ============================================================

CREATE DATABASE IF NOT EXISTS CorporateGatePassSystem;
USE CorporateGatePassSystem;

-- 1. Admin Credentials Table
CREATE TABLE IF NOT EXISTS ADMIN (
    Admin_ID    INT PRIMARY KEY AUTO_INCREMENT,
    Login_Details VARCHAR(50) NOT NULL UNIQUE,
    Password    VARCHAR(100) NOT NULL
);

-- 2. Employee Table
CREATE TABLE IF NOT EXISTS EMPLOYEE (
    Employee_ID INT PRIMARY KEY AUTO_INCREMENT,
    Name        VARCHAR(100) NOT NULL,
    Department  VARCHAR(100),
    Contact     VARCHAR(20)
);

-- 3. Security Guards Table
CREATE TABLE IF NOT EXISTS SECURITY (
    UID         INT PRIMARY KEY AUTO_INCREMENT,
    Name        VARCHAR(100) NOT NULL,
    Shift       VARCHAR(20),
    Contact     VARCHAR(20)
);

-- 4. Visitor Table
CREATE TABLE IF NOT EXISTS VISITOR (
    ID          INT PRIMARY KEY AUTO_INCREMENT,
    Name        VARCHAR(100) NOT NULL,
    Contact     VARCHAR(20) NOT NULL,
    Purpose     TEXT
);

-- 5. Visit Logs Table (links visitors to responsible employees)
CREATE TABLE IF NOT EXISTS VISIT_LOGS (
    Log_ID      INT PRIMARY KEY AUTO_INCREMENT,
    EMP_ID      INT NOT NULL,
    Date        DATE NOT NULL,
    Time        TIME NOT NULL,
    FOREIGN KEY (EMP_ID) REFERENCES EMPLOYEE(Employee_ID)
);

-- 6. Gate Pass Table
CREATE TABLE IF NOT EXISTS GATE_PASS (
    Pass_ID     INT PRIMARY KEY AUTO_INCREMENT,
    UID         INT NOT NULL,
    Name        VARCHAR(100) NOT NULL,
    Contact     VARCHAR(20) NOT NULL,
    Visitor_ID  INT NOT NULL,
    FOREIGN KEY (UID) REFERENCES SECURITY(UID),
    FOREIGN KEY (Visitor_ID) REFERENCES VISITOR(ID)
);

-- 7. Delivery Pass Table
CREATE TABLE IF NOT EXISTS DELIVERY_PASS (
    Pass_ID     INT PRIMARY KEY AUTO_INCREMENT,
    Delivery_Company VARCHAR(100) NOT NULL,
    Driver_Name VARCHAR(100),
    Contact     VARCHAR(20),
    Purpose     TEXT,
    Received_By INT,
    FOREIGN KEY (Received_By) REFERENCES EMPLOYEE(Employee_ID)
);

-- 8. Access Control Table (maps gate passes to building locations)
CREATE TABLE IF NOT EXISTS ACCESS_CONTROL (
    Access_ID     INT PRIMARY KEY AUTO_INCREMENT,
    Security_UID  INT NOT NULL,
    GatePass_UID  INT NOT NULL UNIQUE,
    Location      VARCHAR(100) NOT NULL,
    FOREIGN KEY (Security_UID) REFERENCES SECURITY(UID),
    FOREIGN KEY (GatePass_UID) REFERENCES GATE_PASS(Pass_ID)
);

-- 9. Vehicles Table
CREATE TABLE IF NOT EXISTS VEHICLES (
    Vehicle_ID          INT PRIMARY KEY AUTO_INCREMENT,
    Registration_Number VARCHAR(20) NOT NULL,
    Make                VARCHAR(50),
    Name                VARCHAR(100),
    Contact             VARCHAR(20),
    Date_Time           DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- 10. Notification Table
CREATE TABLE IF NOT EXISTS NOTIFICATION (
    Notification_ID INT PRIMARY KEY AUTO_INCREMENT,
    Message         TEXT NOT NULL,
    Created_At      DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- 11. Visitor Status Table (real-time IN/OUT tracker)
CREATE TABLE IF NOT EXISTS VISITOR_STATUS (
    Status_ID   INT PRIMARY KEY AUTO_INCREMENT,
    Visitor_ID  INT NOT NULL,
    Entry_Time  DATETIME NOT NULL,
    Exit_Time   DATETIME,
    Status      ENUM('IN', 'OUT') DEFAULT 'IN',
    FOREIGN KEY (Visitor_ID) REFERENCES VISITOR(ID)
);

-- ============================================================
-- Seed Data: Default Admin Account
-- ============================================================
INSERT INTO ADMIN (Login_Details, Password) VALUES ('admin', 'admin123');
