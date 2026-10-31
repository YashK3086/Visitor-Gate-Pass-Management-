# Relational Architecture & Normalization Defense (`1NF → 2NF → 3NF → BCNF`)

This document provides the formal functional-dependency analysis and step-by-step relational decomposition that transformed the legacy 11-table `CorporateGatePassSystem` schema into the BCNF-compliant [`01_production_schema.sql`](../database/01_production_schema.sql).

---

## 1. Anomalies Identified in the Legacy Schema (`corporategatepasssystem.sql`)

| Legacy Table | Violated Normal Form | Structural Defect & Resulting Anomaly |
|---|---|---|
| `VISITOR(ID, Name, Contact, Purpose)` | **1NF & 2NF** | `Name` is a composite full-name attribute (`"Aditi Sharma"`), preventing atomic surname sorting/indexing. `Purpose` is an attribute of a *visit*, not a *person*—storing it on `VISITOR` forces either overwriting a visitor's purpose on repeat visits (**Update Anomaly**) or duplicating the visitor row for every visit (**Insertion Anomaly**). |
| `EMPLOYEE(Employee_ID, Name, Department, Contact)` | **1NF & 3NF** | `Name` is composite. `Department` is a repeating free-text string (`"Engineering"`, `"Engg"`): `Employee_ID → Department → Building/Floor`. Deleting the last employee in a department erases the department's existence (**Deletion Anomaly**). |
| `SECURITY(UID, Name, Shift, Contact)` | **1NF & 3NF** | `Shift` is stored as a free-text string (`"Morning"`). Shift start/end hours depend on the shift (`UID → Shift → (Start_Time, End_Time)`), creating a transitive dependency. |
| `GATE_PASS(Pass_ID, UID, Name, Contact, Visitor_ID)` | **2NF / 3NF** | `Name` and `Contact` are redundantly copied from `VISITOR` (`Pass_ID → Visitor_ID → (Name, Contact)`). Updating a visitor's phone number leaves stale data on issued gate passes (**Update Anomaly**). |
| `VEHICLES(Vehicle_ID, Registration_Number, Make, Name, Contact, Date_Time)` | **1NF / 3NF** | No foreign key to `VISITOR`—instead, visitor `Name` and `Contact` are copied into `VEHICLES`, creating orphan vehicle records and update anomalies. |
| `VISIT_LOGS(Log_ID, EMP_ID, Date, Time)` | **1NF & Domain** | Splits a single temporal instant into separate `Date` and `Time` columns (breaking range comparisons across midnight) and omits any foreign key to `VISITOR` or `GATE_PASS`. |
| `VISITOR_STATUS` & `ACCESS_CONTROL` | **3NF Redundancy** | Splits gate pass state (`IN`/`OUT`, `Entry_Time`, `Exit_Time`, `Location`, `Security_UID`) across 3 separate tables (`GATE_PASS`, `VISITOR_STATUS`, `ACCESS_CONTROL`), allowing contradictory states (e.g., a pass with `Status = 'IN'` but no `GATE_PASS` row). |

---

## 2. Step-by-Step Normalization Progression

### Step 2.1 — First Normal Form (1NF: Atomicity & Repeating Group Elimination)
1. **Atomic Person Names:** Split composite `Name` into `first_name VARCHAR(50) NOT NULL` and `last_name VARCHAR(50) NOT NULL` across [`employees`](../database/01_production_schema.sql#L48-L67), [`security_guards`](../database/01_production_schema.sql#L81-L97), and [`visitors`](../database/01_production_schema.sql#L121-L143).
2. **Atomic Temporal Attributes:** Consolidated split `Date` + `Time` columns into unified `DATETIME` / `DATETIME(3)` attributes (`valid_from`, `valid_until`, `check_in_time`, `check_out_time`, `event_at`).
3. **Multi-Valued Attribute Extraction:** A single visitor can own zero, one, or multiple vehicles (e.g., Visitor `#1` owns both `KA-01-MJ-4821` and `KA-05-NB-9012`). Vehicles are extracted into [`vehicles`](../database/01_production_schema.sql#L147-L160) with `FOREIGN KEY (visitor_id) REFERENCES visitors(visitor_id) ON DELETE CASCADE`.
4. **Visit Purpose Relocation:** Moved `visit_purpose` from `visitors` to [`gate_passes`](../database/01_production_schema.sql#L180-L255), because a visitor's identity is permanent while each gate pass represents one specific visit.

### Step 2.2 — Second Normal Form (2NF: Full Functional Dependency on Candidate Keys)
- Every table uses a single-attribute surrogate primary key (`dept_id`, `emp_id`, `guard_id`, `visitor_id`, `vehicle_id`, `pass_id`, `log_id`) alongside enforced natural candidate keys (`UNIQUE`).
- In [`gate_passes`](../database/01_production_schema.sql#L180-L255), all redundant visitor copies (`Name`, `Contact`) were eliminated. Every non-prime attribute of `gate_passes` (`visitor_id`, `host_emp_id`, `vehicle_id`, `visit_purpose`, `valid_from`, `valid_until`, `status`, `check_in_*`, `check_out_*`) depends irreducibly on the whole candidate key `pass_id` (and equivalently `pass_code` / `pass_token`).

### Step 2.3 — Third Normal Form (3NF: Elimination of Transitive Dependencies)
1. **Department Decoupling:**
   - Removed `department_name`, `building_name`, and `floor_no` from `employees`.
   - Created [`departments`](../database/01_production_schema.sql#L33-L45):
     $$\text{emp\_id} \to \text{dept\_id}, \quad \text{dept\_id} \to (\text{dept\_code}, \text{dept\_name}, \text{building\_name}, \text{floor\_no})$$
2. **Shift Decoupling:**
   - Removed shift timing from `security_guards` into [`shifts`](../database/01_production_schema.sql#L70-L79):
     $$\text{guard\_id} \to \text{shift\_id}, \quad \text{shift\_id} \to (\text{shift\_code}, \text{shift\_name}, \text{start\_time}, \text{end\_time})$$
3. **Checkpoint Decoupling:**
   - Replaced free-text `Location` in `ACCESS_CONTROL` with [`checkpoints`](../database/01_production_schema.sql#L100-L110) (`checkpoint_id → checkpoint_code, checkpoint_name, building_name`).
4. **Zero-Redundancy Duration Calculation:**
   - `visit_duration_min` is functionally determined by `(check_in_time, check_out_time)`. Instead of storing a physical column that could drift out of sync, [`gate_passes`](../database/01_production_schema.sql#L207-L209) defines it as a **`VIRTUAL` generated column**:
     ```sql
     visit_duration_min INT GENERATED ALWAYS AS (TIMESTAMPDIFF(MINUTE, check_in_time, check_out_time)) VIRTUAL
     ```

### Step 2.4 — Boyce-Codd Normal Form (BCNF: Every Determinant is a Superkey)
For every relation $R$ in `cvgps_pro` and every non-trivial functional dependency $X \to Y$, $X$ is enforced as a `PRIMARY KEY` or `UNIQUE KEY` (superkey):

| Relation $R$ | Enforced Candidate Keys (Superkeys) | Non-Trivial Functional Dependencies $X \to Y$ | BCNF Verdict |
|---|---|---|---|
| `departments` | `{dept_id}`, `{dept_code}`, `{dept_name}` | `dept_id → all`, `dept_code → all`, `dept_name → all` | **BCNF** (all 3 determinants are `UNIQUE`/`PK`) |
| `employees` | `{emp_id}`, `{emp_code}`, `{email}`, `{phone}` | Each candidate key uniquely determines the employee tuple; `dept_id` only determines `dept_id` within `employees` | **BCNF** |
| `shifts` | `{shift_id}`, `{shift_code}`, `{shift_name}` | `shift_id → all`, `shift_code → all`, `shift_name → all` | **BCNF** |
| `security_guards` | `{guard_id}`, `{badge_no}`, `{phone}` | All determinants are superkeys | **BCNF** |
| `checkpoints` | `{checkpoint_id}`, `{checkpoint_code}` | All determinants are superkeys | **BCNF** |
| `id_proof_types` | `{id_proof_type_id}`, `{type_code}` | All determinants are superkeys | **BCNF** |
| `visitors` | `{visitor_id}`, `{id_proof_type_id, id_proof_hash}` | Composite candidate key `(id_proof_type_id, id_proof_hash)` uniquely identifies a visitor without storing plaintext government IDs | **BCNF** |
| `vehicles` | `{vehicle_id}`, `{registration_no}`, `{visitor_id, vehicle_id}` | `registration_no → all`, `vehicle_id → all` | **BCNF** |
| `visitor_blacklist` | `{blacklist_id}` | Allows multiple temporal blacklist intervals per visitor over time (`blacklist_id → all`) | **BCNF** |
| `gate_passes` | `{pass_id}`, `{pass_token}`, `{pass_code}`, `{active_visitor_key}` | All determinants are superkeys | **BCNF** |
| `access_audit_logs` | `{log_id}` | Immutable event ledger (`log_id → all`) | **BCNF** |

---

## 3. Foreign Key Referential Actions (`RESTRICT` vs `CASCADE`)

| Child Table → Parent Table | Constraint | Referential Policy | Engineering Justification |
|---|---|---|---|
| `employees.dept_id → departments` | `fk_emp_dept` | `ON DELETE RESTRICT` | Prevents accidentally deleting a department that still has assigned staff (`ERROR 1451`). |
| `vehicles.visitor_id → visitors` | `fk_veh_visitor` | `ON DELETE CASCADE` | A visitor's registered vehicle entry is a weak/dependent entity owned by that visitor. If an unreferenced visitor is purged, their vehicle registration is automatically cleaned up. |
| `visitor_blacklist.visitor_id → visitors` | `fk_bl_visitor` | `ON DELETE CASCADE` | Blacklist entries belong strictly to the visitor identity. |
| `gate_passes.visitor_id → visitors` | `fk_gp_visitor` | `ON DELETE RESTRICT` | A visitor who has historical or active gate passes **cannot** be deleted (`ERROR 1451`), preserving the security audit chain. |
| `gate_passes(visitor_id, vehicle_id) → vehicles(visitor_id, vehicle_id)` | `fk_gp_visitor_veh` | `ON DELETE RESTRICT` | **Composite Foreign Key** guarantees a gate pass can never attach a vehicle owned by a *different* visitor (`ERROR 1452`), while allowing `vehicle_id IS NULL` for walk-in visitors. |
| `access_audit_logs.pass_id → gate_passes` | `fk_audit_pass` | `ON DELETE RESTRICT` | Prevents deleting any gate pass that has audit trail records. |

