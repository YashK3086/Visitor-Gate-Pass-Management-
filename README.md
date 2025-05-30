# 🏢 Corporate Visitor Gate Pass System

## 📋 Description

The **Corporate Visitor Gate Pass System** is a desktop-based Java application designed to manage visitor entries, gate pass issuance, employee verification, and visitor tracking in a corporate setting. It streamlines the manual visitor registration process and ensures high security and monitoring using a MySQL database backend.

## 💡 Features

- 🔐 **Admin Login Authentication**
- 👥 **Visitor Entry Form**
- 🎫 **Automatic Gate Pass Generation**
- 📊 **Admin Dashboard** with access to all major tables:
  - Visitors
  - Employees
  - Vehicles
  - Gate Passes
  - Notifications
  - Visitor Status
- 🔔 **Pop-up Notifications** on new gate pass creation
- 📈 **Visitor Status Monitor** (In/Out)
- 🗃️ **Database Integration** using JDBC
- 💻 **User-friendly Java Swing UI**

---

## 🗃️ Database Schema (MySQL)

The project uses a database named `CorporateGatePassSystem` with tables:

- `VISITOR`
- `EMPLOYEE`
- `VISIT_LOGS`
- `SECURITY`
- `ACCESS_CONTROL`
- `GATE_PASS`
- `DELIVERY_PASS`
- `VEHICLES`
- `NOTIFICATION`
- `VISITOR_STATUS` ✅ *(custom added table)*
- `ADMIN` ✅ *(includes password column)*

A full SQL script is included in the `sql/` folder.

---

## 🛠️ Tech Stack

- **Frontend:** Java Swing (AWT/Swing)
- **Backend:** MySQL (via JDBC)
- **Language:** Java
- **Database Connector:** JDBC (MySQL Connector/J)

---

## 🚀 How to Run Locally

### 1. Requirements

- Java JDK 8 or above
- MySQL Server
- MySQL JDBC Driver (add `mysql-connector-java.jar` to classpath)
- IDE (e.g., IntelliJ IDEA, Eclipse, NetBeans)

### 2. Steps

1. Clone or unzip the project folder.
2. Import the SQL script into MySQL:
   ```bash
   mysql -u root -p < sql/CorporateGatePassSystem.sql
