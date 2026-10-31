-- ============================================================================
-- Corporate Visitor Gate Pass System (CVGPS) — Production Database Architecture
-- File: database/01_production_schema.sql
-- Engine: MySQL 8.0+ (InnoDB, Strict SQL Mode, UTF8MB4)
-- Normalization: 1NF -> 2NF -> 3NF -> BCNF
-- Version: 2.0 (Visitor Categories, Parking Zones & Sessions, Host Approvals)
-- ============================================================================

SET NAMES utf8mb4;
SET SESSION sql_mode = 'ONLY_FULL_GROUP_BY,STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION';

DROP DATABASE IF EXISTS cvgps_pro;
CREATE DATABASE cvgps_pro
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_0900_ai_ci;

USE cvgps_pro;

-- ============================================================================
-- SECTION 1: NORMALIZED RELATIONAL SCHEMA (1NF -> 2NF -> 3NF -> BCNF)
-- ============================================================================

-- 1.1 Restricted System Secrets (Server-side cryptographic pepper)
CREATE TABLE sys_secrets (
    secret_key   VARCHAR(40)  NOT NULL,
    secret_value VARCHAR(128) NOT NULL,
    rotated_at   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (secret_key)
) ENGINE=InnoDB;

INSERT INTO sys_secrets (secret_key, secret_value)
VALUES ('ID_PROOF_PEPPER', 'cvgps_v2_8f4e2a91c7b305d6e19a4c8f2b70d3e5');

-- 1.2 Departments (Decoupled from employees to eliminate 3NF transitive dependency)
CREATE TABLE departments (
    dept_id       INT          NOT NULL AUTO_INCREMENT,
    dept_code     VARCHAR(12)  NOT NULL,
    dept_name     VARCHAR(80)  NOT NULL,
    building_name VARCHAR(60)  NOT NULL,
    floor_no      INT          NOT NULL,
    created_at    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (dept_id),
    UNIQUE KEY uk_dept_code (dept_code),
    UNIQUE KEY uk_dept_name (dept_name),
    CONSTRAINT chk_dept_code_fmt CHECK (dept_code REGEXP '^[A-Z]{2,8}(-[A-Z0-9]{1,6})?$'),
    CONSTRAINT chk_dept_floor    CHECK (floor_no BETWEEN 0 AND 60)
) ENGINE=InnoDB;

-- 1.3 Government ID Proof Types (Lookup table for BCNF compliance)
CREATE TABLE id_proof_types (
    id_proof_type_id INT         NOT NULL AUTO_INCREMENT,
    type_code        VARCHAR(20) NOT NULL,
    type_label       VARCHAR(60) NOT NULL,
    PRIMARY KEY (id_proof_type_id),
    UNIQUE KEY uk_id_proof_code (type_code)
) ENGINE=InnoDB;

-- 1.4 Employees / Hosts (Includes Ex-Employee Tracking via Hashed ID & Exit State)
CREATE TABLE employees (
    emp_id           INT          NOT NULL AUTO_INCREMENT,
    emp_code         VARCHAR(16)  NOT NULL,
    first_name       VARCHAR(50)  NOT NULL,
    last_name        VARCHAR(50)  NOT NULL,
    email            VARCHAR(120) NOT NULL,
    phone            VARCHAR(20)  NOT NULL,
    dept_id          INT          NOT NULL,
    is_active        TINYINT(1)   NOT NULL DEFAULT 1,
    id_proof_type_id INT          NULL,
    id_proof_hash    BINARY(32)   NULL,
    id_proof_last4   CHAR(4)      NULL,
    exit_type        ENUM('RESIGNED','TERMINATED','CONTRACT_ENDED') NULL,
    exit_date        DATE         NULL,
    created_at       DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (emp_id),
    UNIQUE KEY uk_emp_code  (emp_code),
    UNIQUE KEY uk_emp_email (email),
    UNIQUE KEY uk_emp_phone (phone),
    KEY idx_emp_dept_active (dept_id, is_active),
    KEY idx_emp_id_hash     (id_proof_hash),
    CONSTRAINT chk_emp_names  CHECK (CHAR_LENGTH(TRIM(first_name)) >= 1 AND CHAR_LENGTH(TRIM(last_name)) >= 1),
    CONSTRAINT chk_emp_email  CHECK (email REGEXP '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$'),
    CONSTRAINT chk_emp_phone  CHECK (phone REGEXP '^\\+?[0-9]{10,15}$'),
    CONSTRAINT chk_emp_active CHECK (is_active IN (0, 1)),
    CONSTRAINT fk_emp_dept    FOREIGN KEY (dept_id) REFERENCES departments(dept_id)
                              ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_emp_idtype  FOREIGN KEY (id_proof_type_id) REFERENCES id_proof_types(id_proof_type_id)
                              ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB;

-- 1.5 Shifts
CREATE TABLE shifts (
    shift_id    INT         NOT NULL AUTO_INCREMENT,
    shift_code  VARCHAR(16) NOT NULL,
    shift_name  VARCHAR(40) NOT NULL,
    start_time  TIME        NOT NULL,
    end_time    TIME        NOT NULL,
    PRIMARY KEY (shift_id),
    UNIQUE KEY uk_shift_code (shift_code),
    UNIQUE KEY uk_shift_name (shift_name)
) ENGINE=InnoDB;

-- 1.6 Security Guards
CREATE TABLE security_guards (
    guard_id    INT         NOT NULL AUTO_INCREMENT,
    badge_no    VARCHAR(16) NOT NULL,
    first_name  VARCHAR(50) NOT NULL,
    last_name   VARCHAR(50) NOT NULL,
    phone       VARCHAR(20) NOT NULL,
    shift_id    INT         NOT NULL,
    is_active   TINYINT(1)  NOT NULL DEFAULT 1,
    created_at  DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (guard_id),
    UNIQUE KEY uk_guard_badge (badge_no),
    UNIQUE KEY uk_guard_phone (phone),
    KEY idx_guard_shift (shift_id),
    CONSTRAINT chk_guard_badge  CHECK (badge_no REGEXP '^SG-[0-9]{3,6}$'),
    CONSTRAINT chk_guard_phone  CHECK (phone REGEXP '^\\+?[0-9]{10,15}$'),
    CONSTRAINT chk_guard_active CHECK (is_active IN (0, 1)),
    CONSTRAINT fk_guard_shift   FOREIGN KEY (shift_id) REFERENCES shifts(shift_id)
                                ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB;

-- 1.7 Gate Checkpoints
CREATE TABLE checkpoints (
    checkpoint_id   INT         NOT NULL AUTO_INCREMENT,
    checkpoint_code VARCHAR(20) NOT NULL,
    checkpoint_name VARCHAR(80) NOT NULL,
    building_name   VARCHAR(60) NOT NULL,
    is_active       TINYINT(1)  NOT NULL DEFAULT 1,
    PRIMARY KEY (checkpoint_id),
    UNIQUE KEY uk_checkpoint_code (checkpoint_code),
    CONSTRAINT chk_checkpoint_active CHECK (is_active IN (0, 1))
) ENGINE=InnoDB;

-- 1.8 Visitor Categories & Access Policies (Meeting, Contractor, Courier, New Joinee, Ex-Employee, etc.)
CREATE TABLE visitor_categories (
    category_id            INT         NOT NULL AUTO_INCREMENT,
    category_code          VARCHAR(30) NOT NULL,
    category_name          VARCHAR(60) NOT NULL,
    max_pass_hours         INT         NOT NULL DEFAULT 8,
    parking_allowed        TINYINT(1)  NOT NULL DEFAULT 1,
    max_parking_minutes    INT         NOT NULL DEFAULT 240,
    requires_escort        TINYINT(1)  NOT NULL DEFAULT 0,
    requires_host_approval TINYINT(1)  NOT NULL DEFAULT 0,
    allowed_from_time      TIME        NOT NULL DEFAULT '06:00:00',
    allowed_to_time        TIME        NOT NULL DEFAULT '22:00:00',
    created_at             DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (category_id),
    UNIQUE KEY uk_cat_code (category_code),
    CONSTRAINT chk_cat_hours   CHECK (max_pass_hours BETWEEN 1 AND 24),
    CONSTRAINT chk_cat_parking CHECK (max_parking_minutes >= 0 AND max_parking_minutes <= 1440),
    CONSTRAINT chk_cat_escort  CHECK (requires_escort IN (0, 1)),
    CONSTRAINT chk_cat_hostapp CHECK (requires_host_approval IN (0, 1))
) ENGINE=InnoDB;

-- 1.9 Category Checkpoint Authorizations (Physical perimeter segregation)
CREATE TABLE category_checkpoints (
    category_id   INT NOT NULL,
    checkpoint_id INT NOT NULL,
    PRIMARY KEY (category_id, checkpoint_id),
    CONSTRAINT fk_cc_cat  FOREIGN KEY (category_id) REFERENCES visitor_categories(category_id)
                          ON DELETE CASCADE,
    CONSTRAINT fk_cc_ckpt FOREIGN KEY (checkpoint_id) REFERENCES checkpoints(checkpoint_id)
                          ON DELETE CASCADE
) ENGINE=InnoDB;

-- 1.10 Parking Zones
CREATE TABLE parking_zones (
    zone_id               INT          NOT NULL AUTO_INCREMENT,
    zone_code             VARCHAR(20)  NOT NULL,
    zone_name             VARCHAR(60)  NOT NULL,
    capacity              INT          NOT NULL,
    allowed_vehicle_types VARCHAR(120) NOT NULL DEFAULT 'TWO_WHEELER,SEDAN,SUV',
    is_active             TINYINT(1)   NOT NULL DEFAULT 1,
    created_at            DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (zone_id),
    UNIQUE KEY uk_zone_code (zone_code),
    CONSTRAINT chk_zone_cap CHECK (capacity > 0)
) ENGINE=InnoDB;

-- 1.11 Visitors (1NF atomic names; SHA-256 hashed ID proof + masked last 4 digits)
CREATE TABLE visitors (
    visitor_id       INT          NOT NULL AUTO_INCREMENT,
    first_name       VARCHAR(50)  NOT NULL,
    last_name        VARCHAR(50)  NOT NULL,
    phone            VARCHAR(20)  NOT NULL,
    email            VARCHAR(120) NULL,
    company_name     VARCHAR(100) NULL,
    id_proof_type_id INT          NOT NULL,
    id_proof_hash    BINARY(32)   NOT NULL,
    id_proof_last4   CHAR(4)      NOT NULL,
    created_at       DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (visitor_id),
    UNIQUE KEY uk_visitor_id_proof (id_proof_type_id, id_proof_hash),
    KEY idx_visitor_phone   (phone),
    KEY idx_visitor_name    (last_name, first_name),
    KEY idx_visitor_id_hash (id_proof_hash),
    CONSTRAINT chk_vis_names  CHECK (CHAR_LENGTH(TRIM(first_name)) >= 1 AND CHAR_LENGTH(TRIM(last_name)) >= 1),
    CONSTRAINT chk_vis_phone  CHECK (phone REGEXP '^\\+?[0-9]{10,15}$'),
    CONSTRAINT chk_vis_email  CHECK (email IS NULL OR email REGEXP '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$'),
    CONSTRAINT chk_vis_last4  CHECK (id_proof_last4 REGEXP '^[A-Za-z0-9]{4}$'),
    CONSTRAINT fk_vis_idtype  FOREIGN KEY (id_proof_type_id) REFERENCES id_proof_types(id_proof_type_id)
                              ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB;

-- 1.12 Vehicles (Composite UK (visitor_id, vehicle_id) supports composite FK in gate_passes)
CREATE TABLE vehicles (
    vehicle_id      INT         NOT NULL AUTO_INCREMENT,
    visitor_id      INT         NOT NULL,
    registration_no VARCHAR(20) NOT NULL,
    vehicle_type    ENUM('TWO_WHEELER','SEDAN','SUV','TRUCK','VAN','OTHER') NOT NULL DEFAULT 'SEDAN',
    make_model      VARCHAR(60) NOT NULL,
    created_at      DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (vehicle_id),
    UNIQUE KEY uk_vehicle_reg (registration_no),
    UNIQUE KEY uk_visitor_vehicle (visitor_id, vehicle_id),
    CONSTRAINT chk_vehicle_reg CHECK (registration_no REGEXP '^[A-Z]{2}-[0-9]{2}-[A-Z]{1,2}-[0-9]{4}$'),
    CONSTRAINT fk_veh_visitor  FOREIGN KEY (visitor_id) REFERENCES visitors(visitor_id)
                               ON UPDATE CASCADE ON DELETE CASCADE
) ENGINE=InnoDB;

-- 1.13 Visitor Blacklist (Temporal security watchlist; ON DELETE CASCADE on visitor removal)
CREATE TABLE visitor_blacklist (
    blacklist_id  INT          NOT NULL AUTO_INCREMENT,
    visitor_id    INT          NOT NULL,
    reason        VARCHAR(255) NOT NULL,
    severity      ENUM('LOW','MEDIUM','HIGH','CRITICAL') NOT NULL DEFAULT 'HIGH',
    start_at      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    end_at        DATETIME     NULL,
    lifted_at     DATETIME     NULL,
    lifted_reason VARCHAR(255) NULL,
    created_by    INT          NULL,
    PRIMARY KEY (blacklist_id),
    KEY idx_bl_visitor_active (visitor_id, lifted_at, end_at, start_at),
    CONSTRAINT chk_bl_window CHECK (end_at IS NULL OR end_at > start_at),
    CONSTRAINT fk_bl_visitor FOREIGN KEY (visitor_id) REFERENCES visitors(visitor_id)
                             ON UPDATE CASCADE ON DELETE CASCADE,
    CONSTRAINT fk_bl_guard   FOREIGN KEY (created_by) REFERENCES security_guards(guard_id)
                             ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB;

-- 1.14 Gate Passes (Core lifecycle entity with Category, Host Approval, Escort, and Partial Unique Index)
CREATE TABLE gate_passes (
    pass_id                INT          NOT NULL AUTO_INCREMENT,
    pass_token             BINARY(16)   NOT NULL DEFAULT (UUID_TO_BIN(UUID(), 1)),
    pass_code              CHAR(9)      NOT NULL,
    visitor_id             INT          NOT NULL,
    host_emp_id            INT          NOT NULL,
    category_id            INT          NOT NULL DEFAULT 1,
    vehicle_id             INT          NULL,
    escort_emp_id          INT          NULL,
    visit_purpose          VARCHAR(255) NOT NULL,
    valid_from             DATETIME     NOT NULL,
    valid_until            DATETIME     NOT NULL,
    status                 ENUM('PENDING_APPROVAL','APPROVED','ACTIVE_ON_CAMPUS','COMPLETED','EXPIRED','REVOKED')
                                        NOT NULL DEFAULT 'APPROVED',
    approved_by_emp_id     INT          NULL,
    approved_at            DATETIME     NULL,
    approval_notes         VARCHAR(255) NULL,
    check_in_time          DATETIME     NULL,
    check_in_guard_id      INT          NULL,
    check_in_checkpoint_id INT          NULL,
    check_out_time         DATETIME     NULL,
    check_out_guard_id     INT          NULL,
    check_out_checkpoint_id INT         NULL,
    is_overstay            TINYINT(1)   NOT NULL DEFAULT 0,
    revoke_reason          VARCHAR(255) NULL,
    created_at             DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- Stored generated column emulating a partial unique index:
    -- Guarantees at the storage-engine index level that a visitor has at most ONE non-terminal pass.
    active_visitor_key     INT GENERATED ALWAYS AS (
                               IF(status IN ('PENDING_APPROVAL','APPROVED','ACTIVE_ON_CAMPUS'), visitor_id, NULL)
                           ) STORED,

    -- Virtual generated column: computed on-read, zero 3NF storage redundancy.
    visit_duration_min     INT GENERATED ALWAYS AS (
                               TIMESTAMPDIFF(MINUTE, check_in_time, check_out_time)
                           ) VIRTUAL,

    PRIMARY KEY (pass_id),
    UNIQUE KEY uk_pass_token        (pass_token),
    UNIQUE KEY uk_pass_code         (pass_code),
    UNIQUE KEY uk_gp_active_visitor (active_visitor_key),

    KEY idx_gp_status_checkin    (status, check_in_time),
    KEY idx_gp_host_validfrom    (host_emp_id, valid_from),
    KEY idx_gp_status_validuntil (status, valid_until),
    KEY idx_gp_visitor_created   (visitor_id, created_at),
    KEY idx_gp_category          (category_id),
    KEY idx_gp_checkin_guard     (check_in_guard_id),
    KEY idx_gp_checkout_guard    (check_out_guard_id),
    KEY idx_gp_checkin_ckpt      (check_in_checkpoint_id),
    KEY idx_gp_checkout_ckpt     (check_out_checkpoint_id),

    -- Domain & Cross-Column Integrity CHECK Constraints
    CONSTRAINT chk_gp_code_fmt     CHECK (pass_code REGEXP '^GP-[A-Z0-9]{6}$'),
    CONSTRAINT chk_gp_valid_window CHECK (valid_until > valid_from),
    CONSTRAINT chk_gp_max_duration CHECK (TIMESTAMPDIFF(HOUR, valid_from, valid_until) <= 24),
    CONSTRAINT chk_gp_checkout_ord CHECK (check_out_time IS NULL OR (check_in_time IS NOT NULL AND check_out_time >= check_in_time)),
    CONSTRAINT chk_gp_active_state CHECK (status <> 'ACTIVE_ON_CAMPUS' OR (check_in_time IS NOT NULL AND check_out_time IS NULL)),
    CONSTRAINT chk_gp_done_state   CHECK (status <> 'COMPLETED' OR (check_in_time IS NOT NULL AND check_out_time IS NOT NULL)),
    CONSTRAINT chk_gp_overstay_bit CHECK (is_overstay IN (0, 1)),

    -- Foreign Key Constraints
    CONSTRAINT fk_gp_visitor       FOREIGN KEY (visitor_id) REFERENCES visitors(visitor_id)
                                   ON DELETE RESTRICT,
    CONSTRAINT fk_gp_host          FOREIGN KEY (host_emp_id) REFERENCES employees(emp_id)
                                   ON DELETE RESTRICT,
    CONSTRAINT fk_gp_category      FOREIGN KEY (category_id) REFERENCES visitor_categories(category_id)
                                   ON DELETE RESTRICT,
    CONSTRAINT fk_gp_escort        FOREIGN KEY (escort_emp_id) REFERENCES employees(emp_id)
                                   ON DELETE RESTRICT,
    CONSTRAINT fk_gp_approver      FOREIGN KEY (approved_by_emp_id) REFERENCES employees(emp_id)
                                   ON DELETE RESTRICT,
    CONSTRAINT fk_gp_visitor_veh   FOREIGN KEY (visitor_id, vehicle_id) REFERENCES vehicles(visitor_id, vehicle_id)
                                   ON DELETE RESTRICT,
    CONSTRAINT fk_gp_in_guard      FOREIGN KEY (check_in_guard_id) REFERENCES security_guards(guard_id)
                                   ON DELETE RESTRICT,
    CONSTRAINT fk_gp_out_guard     FOREIGN KEY (check_out_guard_id) REFERENCES security_guards(guard_id)
                                   ON DELETE RESTRICT,
    CONSTRAINT fk_gp_in_ckpt       FOREIGN KEY (check_in_checkpoint_id) REFERENCES checkpoints(checkpoint_id)
                                   ON DELETE RESTRICT,
    CONSTRAINT fk_gp_out_ckpt      FOREIGN KEY (check_out_checkpoint_id) REFERENCES checkpoints(checkpoint_id)
                                   ON DELETE RESTRICT
) ENGINE=InnoDB;

-- 1.15 Parking Sessions (Tracks live vehicle occupancy and per-category parking duration limits)
CREATE TABLE parking_sessions (
    session_id        INT        NOT NULL AUTO_INCREMENT,
    pass_id           INT        NOT NULL,
    vehicle_id        INT        NOT NULL,
    zone_id           INT        NOT NULL,
    allocated_minutes INT        NOT NULL,
    entry_time        DATETIME   NOT NULL DEFAULT CURRENT_TIMESTAMP,
    exit_time         DATETIME   NULL,
    is_overstay       TINYINT(1) NOT NULL DEFAULT 0,

    -- Partial unique index: vehicle can have at most ONE active parking session across the campus
    active_parking_key INT GENERATED ALWAYS AS (
                           IF(exit_time IS NULL, vehicle_id, NULL)
                       ) STORED,

    PRIMARY KEY (session_id),
    UNIQUE KEY uk_active_vehicle_parking (active_parking_key),
    KEY idx_ps_pass (pass_id),
    KEY idx_ps_zone_active (zone_id, exit_time),

    CONSTRAINT chk_ps_exit_ord CHECK (exit_time IS NULL OR exit_time >= entry_time),
    CONSTRAINT chk_ps_overstay CHECK (is_overstay IN (0, 1)),
    CONSTRAINT fk_ps_pass      FOREIGN KEY (pass_id) REFERENCES gate_passes(pass_id)
                               ON DELETE RESTRICT,
    CONSTRAINT fk_ps_vehicle   FOREIGN KEY (vehicle_id) REFERENCES vehicles(vehicle_id)
                               ON DELETE RESTRICT,
    CONSTRAINT fk_ps_zone      FOREIGN KEY (zone_id) REFERENCES parking_zones(zone_id)
                               ON DELETE RESTRICT
) ENGINE=InnoDB;

-- 1.16 Access Audit Logs (Immutable, append-only compliance ledger)
CREATE TABLE access_audit_logs (
    log_id         BIGINT       NOT NULL AUTO_INCREMENT,
    pass_id        INT          NULL,
    attempted_code VARCHAR(20)  NULL,
    event_type     ENUM('ISSUED','HOST_APPROVED','HOST_REJECTED','CHECKED_IN','PARKED','PARKING_EXIT','CHECKED_OUT','EXPIRED','REVOKED','OVERSTAY_FLAGGED','DENIED') NOT NULL,
    from_status    VARCHAR(20)  NULL,
    to_status      VARCHAR(20)  NULL,
    guard_id       INT          NULL,
    checkpoint_id  INT          NULL,
    details        VARCHAR(500) NOT NULL,
    event_at       DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (log_id),
    KEY idx_audit_pass_time (pass_id, event_at),
    KEY idx_audit_type_time (event_type, event_at),
    CONSTRAINT fk_audit_pass  FOREIGN KEY (pass_id) REFERENCES gate_passes(pass_id)
                              ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_audit_guard FOREIGN KEY (guard_id) REFERENCES security_guards(guard_id)
                              ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_audit_ckpt  FOREIGN KEY (checkpoint_id) REFERENCES checkpoints(checkpoint_id)
                              ON UPDATE CASCADE ON DELETE RESTRICT
) ENGINE=InnoDB;


-- ============================================================================
-- SECTION 2: HELPER FUNCTIONS (Deterministic / Binlog-Safe)
-- ============================================================================

DELIMITER $$

-- 2.1 Compute salted/peppered SHA-256 binary digest for visitor ID proofs
CREATE FUNCTION fn_hash_id_proof(p_type_id INT, p_raw_id VARCHAR(64))
RETURNS BINARY(32)
READS SQL DATA
DETERMINISTIC
BEGIN
    DECLARE v_pepper VARCHAR(128);
    SELECT secret_value INTO v_pepper
      FROM sys_secrets
     WHERE secret_key = 'ID_PROOF_PEPPER'
     LIMIT 1;
    RETURN UNHEX(SHA2(CONCAT(COALESCE(v_pepper, 'cvgps'), ':', p_type_id, ':', UPPER(TRIM(p_raw_id))), 256));
END$$

-- 2.2 Generate random human-readable pass code GP-XXXXXX
CREATE FUNCTION fn_generate_pass_code()
RETURNS CHAR(9)
NOT DETERMINISTIC
NO SQL
BEGIN
    RETURN CONCAT('GP-', UPPER(SUBSTRING(HEX(RANDOM_BYTES(4)), 1, 6)));
END$$

DELIMITER ;


-- ============================================================================
-- SECTION 3: AUTOMATED BUSINESS RULES VIA TRIGGERS
-- ============================================================================

DELIMITER $$

-- 3.1 Prevent issuing a gate pass to an actively blacklisted visitor (SQLSTATE 45000 / Errno 50001)
CREATE TRIGGER trg_prevent_blacklisted_visitor
BEFORE INSERT ON gate_passes
FOR EACH ROW
BEGIN
    DECLARE v_reason   VARCHAR(255);
    DECLARE v_severity VARCHAR(16);

    SELECT reason, severity
      INTO v_reason, v_severity
      FROM visitor_blacklist
     WHERE visitor_id = NEW.visitor_id
       AND lifted_at IS NULL
       AND start_at <= NOW()
       AND (end_at IS NULL OR end_at > NOW())
     ORDER BY FIELD(severity, 'CRITICAL', 'HIGH', 'MEDIUM', 'LOW'), start_at DESC
     LIMIT 1;

    IF v_reason IS NOT NULL THEN
        SET @v_err = LEFT(CONCAT('SECURITY BLOCK [', v_severity, ']: Visitor #', NEW.visitor_id,
                                 ' is actively blacklisted (', v_reason, ').'), 128);
        SIGNAL SQLSTATE '45000'
            SET MYSQL_ERRNO = 50001,
                MESSAGE_TEXT = @v_err;
    END IF;
END$$

-- 3.2 Enforce single active or unchecked-out pass per visitor (SQLSTATE 45000 / Errno 50002)
CREATE TRIGGER trg_enforce_single_active_pass
BEFORE INSERT ON gate_passes
FOR EACH ROW
BEGIN
    DECLARE v_existing_code   CHAR(9);
    DECLARE v_existing_status VARCHAR(20);

    IF NEW.status IN ('PENDING_APPROVAL', 'APPROVED', 'ACTIVE_ON_CAMPUS') THEN
        SELECT pass_code, status
          INTO v_existing_code, v_existing_status
          FROM gate_passes
         WHERE visitor_id = NEW.visitor_id
           AND status IN ('PENDING_APPROVAL', 'APPROVED', 'ACTIVE_ON_CAMPUS')
         LIMIT 1;

        IF v_existing_code IS NOT NULL THEN
            SET @v_err = LEFT(CONCAT('DUPLICATE PASS BLOCKED: Visitor #', NEW.visitor_id,
                                     ' already holds active pass ', v_existing_code,
                                     ' [', v_existing_status, '].'), 128);
            SIGNAL SQLSTATE '45000'
                SET MYSQL_ERRNO = 50002,
                    MESSAGE_TEXT = @v_err;
        END IF;
    END IF;
END$$

-- 3.3 Enforce strict state machine transitions on gate_passes (SQLSTATE 45000 / Errno 50006)
CREATE TRIGGER trg_enforce_state_machine
BEFORE UPDATE ON gate_passes
FOR EACH ROW
BEGIN
    IF NOT (OLD.status <=> NEW.status) THEN
        -- Terminal states are permanently frozen
        IF OLD.status IN ('COMPLETED', 'EXPIRED', 'REVOKED') THEN
            SET @v_err = LEFT(CONCAT('ILLEGAL TRANSITION: Pass ', OLD.pass_code,
                                     ' is in terminal state ', OLD.status,
                                     ' and cannot transition to ', NEW.status, '.'), 128);
            SIGNAL SQLSTATE '45000'
                SET MYSQL_ERRNO = 50006,
                    MESSAGE_TEXT = @v_err;
        END IF;

        -- From PENDING_APPROVAL: can only move to APPROVED, REVOKED, or EXPIRED
        IF OLD.status = 'PENDING_APPROVAL' AND NEW.status NOT IN ('APPROVED', 'REVOKED', 'EXPIRED') THEN
            SET @v_err = LEFT(CONCAT('ILLEGAL TRANSITION: Pass ', OLD.pass_code,
                                     ' is PENDING_APPROVAL and must be APPROVED by host before check-in (attempted ',
                                     NEW.status, ').'), 128);
            SIGNAL SQLSTATE '45000'
                SET MYSQL_ERRNO = 50006,
                    MESSAGE_TEXT = @v_err;
        END IF;

        -- From APPROVED: only ACTIVE_ON_CAMPUS, EXPIRED, or REVOKED allowed
        IF OLD.status = 'APPROVED' AND NEW.status NOT IN ('ACTIVE_ON_CAMPUS', 'EXPIRED', 'REVOKED') THEN
            SET @v_err = LEFT(CONCAT('ILLEGAL TRANSITION: Pass ', OLD.pass_code,
                                     ' cannot move directly from APPROVED to ', NEW.status,
                                     ' without checking in first.'), 128);
            SIGNAL SQLSTATE '45000'
                SET MYSQL_ERRNO = 50006,
                    MESSAGE_TEXT = @v_err;
        END IF;

        -- From ACTIVE_ON_CAMPUS: only COMPLETED or REVOKED allowed
        IF OLD.status = 'ACTIVE_ON_CAMPUS' AND NEW.status NOT IN ('COMPLETED', 'REVOKED') THEN
            SET @v_err = LEFT(CONCAT('ILLEGAL TRANSITION: Active pass ', OLD.pass_code,
                                     ' can only transition to COMPLETED or REVOKED (attempted ',
                                     NEW.status, ').'), 128);
            SIGNAL SQLSTATE '45000'
                SET MYSQL_ERRNO = 50006,
                    MESSAGE_TEXT = @v_err;
        END IF;
    END IF;
END$$

-- 3.4 Automatically detect and flag overstays during check-out or active sweep
CREATE TRIGGER trg_auto_expire_overstay
BEFORE UPDATE ON gate_passes
FOR EACH ROW
BEGIN
    IF NEW.status = 'COMPLETED' AND NEW.check_out_time IS NOT NULL AND NEW.check_out_time > NEW.valid_until THEN
        SET NEW.is_overstay = 1;
    ELSEIF NEW.status = 'ACTIVE_ON_CAMPUS' AND NOW() > NEW.valid_until THEN
        SET NEW.is_overstay = 1;
    END IF;
END$$

-- 3.5 Audit initial pass creation
CREATE TRIGGER trg_audit_pass_issue
AFTER INSERT ON gate_passes
FOR EACH ROW
BEGIN
    INSERT INTO access_audit_logs (
        pass_id, attempted_code, event_type, from_status, to_status,
        guard_id, checkpoint_id, details, event_at
    ) VALUES (
        NEW.pass_id,
        NEW.pass_code,
        'ISSUED',
        NULL,
        NEW.status,
        NEW.check_in_guard_id,
        NEW.check_in_checkpoint_id,
        CONCAT('Pass ', NEW.pass_code, ' created for visitor #', NEW.visitor_id,
               ' hosted by emp #', NEW.host_emp_id, ' [Status: ', NEW.status,
               ', Valid: ', DATE_FORMAT(NEW.valid_from, '%Y-%m-%d %H:%i'),
               ' to ', DATE_FORMAT(NEW.valid_until, '%Y-%m-%d %H:%i'), '].'),
        COALESCE(NEW.created_at, CURRENT_TIMESTAMP(3))
    );
END$$

-- 3.6 Audit every lifecycle state transition and overstay violation automatically
CREATE TRIGGER trg_audit_pass_lifecycle
AFTER UPDATE ON gate_passes
FOR EACH ROW
BEGIN
    DECLARE v_event_type VARCHAR(20);
    DECLARE v_guard_id   INT;
    DECLARE v_ckpt_id    INT;
    DECLARE v_details    VARCHAR(500);

    -- Log overstay violation when is_overstay flips from 0 -> 1
    IF OLD.is_overstay = 0 AND NEW.is_overstay = 1 THEN
        INSERT INTO access_audit_logs (
            pass_id, attempted_code, event_type, from_status, to_status,
            guard_id, checkpoint_id, details
        ) VALUES (
            NEW.pass_id,
            NEW.pass_code,
            'OVERSTAY_FLAGGED',
            OLD.status,
            NEW.status,
            COALESCE(NEW.check_out_guard_id, NEW.check_in_guard_id),
            COALESCE(NEW.check_out_checkpoint_id, NEW.check_in_checkpoint_id),
            CONCAT('OVERSTAY VIOLATION: Pass ', NEW.pass_code,
                   ' exceeded valid_until (', DATE_FORMAT(NEW.valid_until, '%Y-%m-%d %H:%i:%s'), ').')
        );
    END IF;

    -- Log status transition
    IF NOT (OLD.status <=> NEW.status) THEN
        IF OLD.status = 'PENDING_APPROVAL' AND NEW.status = 'APPROVED' THEN
            SET v_event_type = 'HOST_APPROVED';
            SET v_guard_id   = NULL;
            SET v_ckpt_id    = NULL;
            SET v_details    = CONCAT('Pass ', NEW.pass_code, ' approved by host emp #',
                                      COALESCE(NEW.approved_by_emp_id, NEW.host_emp_id),
                                      '. Notes: ', COALESCE(NEW.approval_notes, 'Approved'));
        ELSEIF OLD.status = 'PENDING_APPROVAL' AND NEW.status = 'REVOKED' THEN
            SET v_event_type = 'HOST_REJECTED';
            SET v_guard_id   = NULL;
            SET v_ckpt_id    = NULL;
            SET v_details    = CONCAT('Pass ', NEW.pass_code, ' REJECTED by host. Reason: ',
                                      COALESCE(NEW.revoke_reason, 'Rejected by host'));
        ELSE
            CASE NEW.status
                WHEN 'ACTIVE_ON_CAMPUS' THEN
                    SET v_event_type = 'CHECKED_IN';
                    SET v_guard_id   = NEW.check_in_guard_id;
                    SET v_ckpt_id    = NEW.check_in_checkpoint_id;
                    SET v_details    = CONCAT('Visitor checked IN on pass ', NEW.pass_code,
                                              ' at ', DATE_FORMAT(NEW.check_in_time, '%Y-%m-%d %H:%i:%s'), '.');
                WHEN 'COMPLETED' THEN
                    SET v_event_type = 'CHECKED_OUT';
                    SET v_guard_id   = NEW.check_out_guard_id;
                    SET v_ckpt_id    = NEW.check_out_checkpoint_id;
                    SET v_details    = CONCAT('Visitor checked OUT on pass ', NEW.pass_code,
                                              ' after ', COALESCE(NEW.visit_duration_min, 0), ' min',
                                              IF(NEW.is_overstay = 1, ' [OVERSTAY VIOLATION]', ' [ON TIME]'), '.');
                WHEN 'EXPIRED' THEN
                    SET v_event_type = 'EXPIRED';
                    SET v_guard_id   = NULL;
                    SET v_ckpt_id    = NULL;
                    SET v_details    = CONCAT('Pass ', NEW.pass_code,
                                              ' auto-expired past valid_until (',
                                              DATE_FORMAT(NEW.valid_until, '%Y-%m-%d %H:%i:%s'), ').');
                WHEN 'REVOKED' THEN
                    SET v_event_type = 'REVOKED';
                    SET v_guard_id   = COALESCE(NEW.check_out_guard_id, NEW.check_in_guard_id);
                    SET v_ckpt_id    = COALESCE(NEW.check_out_checkpoint_id, NEW.check_in_checkpoint_id);
                    SET v_details    = CONCAT('Pass ', NEW.pass_code, ' REVOKED. Reason: ',
                                              COALESCE(NEW.revoke_reason, 'Administrative revocation'), '.');
                ELSE
                    SET v_event_type = 'ISSUED';
                    SET v_guard_id   = NEW.check_in_guard_id;
                    SET v_ckpt_id    = NEW.check_in_checkpoint_id;
                    SET v_details    = CONCAT('Pass ', NEW.pass_code, ' transitioned to ', NEW.status, '.');
            END CASE;
        END IF;

        INSERT INTO access_audit_logs (
            pass_id, attempted_code, event_type, from_status, to_status,
            guard_id, checkpoint_id, details
        ) VALUES (
            NEW.pass_id,
            NEW.pass_code,
            v_event_type,
            OLD.status,
            NEW.status,
            v_guard_id,
            v_ckpt_id,
            v_details
        );
    END IF;
END$$

-- 3.7 Enforce immutability of access_audit_logs (SQLSTATE 45000 / Errno 50009)
CREATE TRIGGER trg_audit_immutable_upd
BEFORE UPDATE ON access_audit_logs
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
        SET MYSQL_ERRNO = 50009,
            MESSAGE_TEXT = 'COMPLIANCE VIOLATION: access_audit_logs is append-only and cannot be updated.';
END$$

CREATE TRIGGER trg_audit_immutable_del
BEFORE DELETE ON access_audit_logs
FOR EACH ROW
BEGIN
    SIGNAL SQLSTATE '45000'
        SET MYSQL_ERRNO = 50009,
            MESSAGE_TEXT = 'COMPLIANCE VIOLATION: access_audit_logs is append-only and cannot be deleted.';
END$$

DELIMITER ;


-- ============================================================================
-- SECTION 4: ATOMIC TRANSACTIONAL STORED PROCEDURES
-- ============================================================================

DELIMITER $$

-- 4.1 Register a visitor (hashes ID proof inside MySQL; optionally registers a vehicle atomically)
CREATE PROCEDURE sp_register_visitor(
    IN p_first_name       VARCHAR(50),
    IN p_last_name        VARCHAR(50),
    IN p_phone            VARCHAR(20),
    IN p_email            VARCHAR(120),
    IN p_company_name     VARCHAR(100),
    IN p_id_proof_type_id INT,
    IN p_raw_id_number    VARCHAR(64),
    IN p_vehicle_reg_no   VARCHAR(20),
    IN p_vehicle_type     VARCHAR(20),
    IN p_vehicle_model    VARCHAR(60)
)
SQL SECURITY DEFINER
BEGIN
    DECLARE v_hash       BINARY(32);
    DECLARE v_last4      CHAR(4);
    DECLARE v_visitor_id INT;
    DECLARE v_vehicle_id INT DEFAULT NULL;
    DECLARE v_clean_id   VARCHAR(64);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    SET v_clean_id = UPPER(TRIM(COALESCE(p_raw_id_number, '')));
    IF CHAR_LENGTH(v_clean_id) < 4 THEN
        SIGNAL SQLSTATE '45000'
            SET MYSQL_ERRNO = 50011,
                MESSAGE_TEXT = 'INVALID ID PROOF: Raw ID number must be at least 4 alphanumeric characters.';
    END IF;

    SET v_hash  = fn_hash_id_proof(p_id_proof_type_id, v_clean_id);
    SET v_last4 = RIGHT(v_clean_id, 4);

    IF EXISTS (
        SELECT 1 FROM visitors
         WHERE id_proof_type_id = p_id_proof_type_id
           AND id_proof_hash    = v_hash
    ) THEN
        SIGNAL SQLSTATE '45000'
            SET MYSQL_ERRNO = 50011,
                MESSAGE_TEXT = 'DUPLICATE IDENTITY: A visitor with this government ID proof is already registered.';
    END IF;

    START TRANSACTION;

    INSERT INTO visitors (
        first_name, last_name, phone, email, company_name,
        id_proof_type_id, id_proof_hash, id_proof_last4
    ) VALUES (
        TRIM(p_first_name),
        TRIM(p_last_name),
        TRIM(p_phone),
        NULLIF(TRIM(COALESCE(p_email, '')), ''),
        NULLIF(TRIM(COALESCE(p_company_name, '')), ''),
        p_id_proof_type_id,
        v_hash,
        v_last4
    );

    SET v_visitor_id = LAST_INSERT_ID();

    IF NULLIF(TRIM(COALESCE(p_vehicle_reg_no, '')), '') IS NOT NULL THEN
        INSERT INTO vehicles (visitor_id, registration_no, vehicle_type, make_model)
        VALUES (
            v_visitor_id,
            UPPER(TRIM(p_vehicle_reg_no)),
            COALESCE(NULLIF(TRIM(p_vehicle_type), ''), 'SEDAN'),
            COALESCE(NULLIF(TRIM(p_vehicle_model), ''), 'Standard Vehicle')
        );
        SET v_vehicle_id = LAST_INSERT_ID();
    END IF;

    COMMIT;

    SELECT
        'REGISTERED'            AS status_code,
        v_visitor_id            AS visitor_id,
        v_vehicle_id            AS vehicle_id,
        CONCAT('***-', v_last4) AS masked_id_proof,
        HEX(v_hash)             AS id_proof_sha256_hex,
        CONCAT('Visitor ', TRIM(p_first_name), ' ', TRIM(p_last_name), ' registered atomically.') AS message;
END$$

-- 4.2 Issue a Gate Pass with Category Policies, Ex-Employee Check & Host Approval Requirements
CREATE PROCEDURE sp_issue_gate_pass(
    IN p_visitor_id     INT,
    IN p_host_emp_id    INT,
    IN p_vehicle_id     INT,
    IN p_valid_from     DATETIME,
    IN p_duration_hours INT,
    IN p_visit_purpose  VARCHAR(255),
    IN p_category_id    INT,
    IN p_escort_emp_id  INT
)
SQL SECURITY DEFINER
BEGIN
    DECLARE v_vis_exists        INT DEFAULT 0;
    DECLARE v_host_active       INT DEFAULT NULL;
    DECLARE v_valid_from        DATETIME;
    DECLARE v_valid_until       DATETIME;
    DECLARE v_pass_code         CHAR(9);
    DECLARE v_pass_token        BINARY(16);
    DECLARE v_pass_id           INT;
    DECLARE v_attempts          INT DEFAULT 0;
    DECLARE v_cat_id            INT;
    DECLARE v_cat_code          VARCHAR(30);
    DECLARE v_cat_max_hours     INT;
    DECLARE v_cat_park_allowed  TINYINT(1);
    DECLARE v_cat_req_approval  TINYINT(1);
    DECLARE v_is_ex_emp         INT DEFAULT 0;
    DECLARE v_ex_emp_exit_type  VARCHAR(20) DEFAULT NULL;
    DECLARE v_vis_id_hash       BINARY(32);
    DECLARE v_init_status       VARCHAR(20) DEFAULT 'APPROVED';
    DECLARE v_errno             INT DEFAULT 0;
    DECLARE v_errmsg            TEXT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_errno = MYSQL_ERRNO, v_errmsg = MESSAGE_TEXT;
        ROLLBACK;
        START TRANSACTION;
        INSERT INTO access_audit_logs (
            pass_id, attempted_code, event_type, from_status, to_status, details
        ) VALUES (
            NULL,
            NULL,
            'DENIED',
            NULL,
            'REJECTED',
            LEFT(CONCAT('PASS ISSUE DENIED (visitor #', COALESCE(p_visitor_id, 0),
                        ', host #', COALESCE(p_host_emp_id, 0), ') [Err ', v_errno, ']: ', v_errmsg), 500)
        );
        COMMIT;
        RESIGNAL;
    END;

    SET v_valid_from = COALESCE(p_valid_from, NOW());
    SET v_cat_id     = COALESCE(p_category_id, 1);

    IF p_duration_hours IS NULL OR p_duration_hours < 1 OR p_duration_hours > 24 THEN
        SIGNAL SQLSTATE '45000'
            SET MYSQL_ERRNO = 50010,
                MESSAGE_TEXT = 'INVALID WINDOW: Pass validity duration must be between 1 and 24 hours.';
    END IF;

    IF v_valid_from < (NOW() - INTERVAL 10 MINUTE) THEN
        SIGNAL SQLSTATE '45000'
            SET MYSQL_ERRNO = 50010,
                MESSAGE_TEXT = 'INVALID WINDOW: valid_from cannot be backdated into the past.';
    END IF;

    IF NULLIF(TRIM(COALESCE(p_visit_purpose, '')), '') IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MYSQL_ERRNO = 50010,
                MESSAGE_TEXT = 'INVALID PURPOSE: Visit purpose cannot be empty.';
    END IF;

    START TRANSACTION;

    -- Pessimistic row lock on the visitor row serializes concurrent pass issuance
    SELECT COUNT(*), id_proof_hash INTO v_vis_exists, v_vis_id_hash
      FROM visitors
     WHERE visitor_id = p_visitor_id
     GROUP BY id_proof_hash
       FOR UPDATE;

    IF v_vis_exists = 0 OR v_vis_exists IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MYSQL_ERRNO = 50003,
                MESSAGE_TEXT = 'VISITOR NOT FOUND: The specified visitor_id does not exist.';
    END IF;

    -- Verify host employee
    SELECT is_active INTO v_host_active
      FROM employees
     WHERE emp_id = p_host_emp_id
       FOR SHARE;

    IF v_host_active IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MYSQL_ERRNO = 50007,
                MESSAGE_TEXT = 'HOST NOT FOUND: The specified host employee does not exist.';
    END IF;

    IF v_host_active = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MYSQL_ERRNO = 50007,
                MESSAGE_TEXT = 'HOST INACTIVE: Cannot issue gate pass because the host employee is inactive.';
    END IF;

    -- Fetch and evaluate Category Policies
    SELECT category_code, max_pass_hours, parking_allowed, requires_host_approval
      INTO v_cat_code, v_cat_max_hours, v_cat_park_allowed, v_cat_req_approval
      FROM visitor_categories
     WHERE category_id = v_cat_id;

    IF v_cat_code IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MYSQL_ERRNO = 50003,
                MESSAGE_TEXT = 'CATEGORY NOT FOUND: The specified visitor_category does not exist.';
    END IF;

    -- Check if visitor is an ex-employee by matching hashed ID proof against inactive employees
    SELECT COUNT(*), MAX(exit_type)
      INTO v_is_ex_emp, v_ex_emp_exit_type
      FROM employees
     WHERE id_proof_hash = v_vis_id_hash
       AND is_active = 0
       AND exit_type IS NOT NULL;

    IF v_is_ex_emp > 0 THEN
        -- If visitor is an ex-employee, switch to EX_EMPLOYEE category if not already set, and mandate host approval
        SELECT category_id INTO v_cat_id FROM visitor_categories WHERE category_code = 'EX_EMPLOYEE';
        SET v_cat_code = 'EX_EMPLOYEE';
        SET v_cat_req_approval = 1;
    END IF;

    -- Enforce Category Max Duration Cap (SQLSTATE 45000 / Errno 50013)
    IF p_duration_hours > v_cat_max_hours THEN
        SET @v_err = LEFT(CONCAT('EXCEEDS CATEGORY LIMIT: Category ', v_cat_code,
                                 ' allows max ', v_cat_max_hours,
                                 ' hours (requested ', p_duration_hours, ' hours).'), 128);
        SIGNAL SQLSTATE '45000'
            SET MYSQL_ERRNO = 50013,
                MESSAGE_TEXT = @v_err;
    END IF;

    -- Enforce Category Parking Eligibility (SQLSTATE 45000 / Errno 50014)
    IF p_vehicle_id IS NOT NULL AND p_vehicle_id > 0 AND v_cat_park_allowed = 0 THEN
        SET @v_err = LEFT(CONCAT('PARKING NOT ALLOWED: Category ', v_cat_code,
                                 ' does not permit vehicular entry or parking.'), 128);
        SIGNAL SQLSTATE '45000'
            SET MYSQL_ERRNO = 50014,
                MESSAGE_TEXT = @v_err;
    END IF;

    -- Determine Initial Lifecycle Status (Host Approval Workflow)
    IF v_cat_req_approval = 1 THEN
        SET v_init_status = 'PENDING_APPROVAL';
    ELSE
        SET v_init_status = 'APPROVED';
    END IF;

    -- Generate collision-free pass code
    REPEAT
        SET v_pass_code = fn_generate_pass_code();
        SET v_attempts  = v_attempts + 1;
    UNTIL NOT EXISTS (SELECT 1 FROM gate_passes WHERE pass_code = v_pass_code) OR v_attempts > 10
    END REPEAT;

    SET v_pass_token  = UUID_TO_BIN(UUID(), 1);
    SET v_valid_until = v_valid_from + INTERVAL p_duration_hours HOUR;

    -- Triggers trg_prevent_blacklisted_visitor and trg_enforce_single_active_pass fire here
    INSERT INTO gate_passes (
        pass_token, pass_code, visitor_id, host_emp_id, category_id,
        vehicle_id, escort_emp_id, visit_purpose, valid_from, valid_until, status
    ) VALUES (
        v_pass_token,
        v_pass_code,
        p_visitor_id,
        p_host_emp_id,
        v_cat_id,
        NULLIF(p_vehicle_id, 0),
        NULLIF(p_escort_emp_id, 0),
        TRIM(p_visit_purpose),
        v_valid_from,
        v_valid_until,
        v_init_status
    );

    SET v_pass_id = LAST_INSERT_ID();

    COMMIT;

    SELECT
        v_init_status                                  AS status_code,
        v_pass_id                                      AS pass_id,
        v_pass_code                                    AS pass_code,
        BIN_TO_UUID(v_pass_token, 1)                   AS pass_uuid,
        v_cat_code                                     AS category_code,
        IF(v_is_ex_emp > 0, 1, 0)                      AS is_ex_employee,
        v_ex_emp_exit_type                             AS ex_employee_exit_type,
        DATE_FORMAT(v_valid_from,  '%Y-%m-%d %H:%i:%s') AS valid_from,
        DATE_FORMAT(v_valid_until, '%Y-%m-%d %H:%i:%s') AS valid_until,
        CASE
            WHEN v_init_status = 'PENDING_APPROVAL' THEN
                CONCAT('Gate pass ', v_pass_code, ' created with status PENDING_APPROVAL (Awaiting Host Employee #', p_host_emp_id, ' action).')
            ELSE
                CONCAT('Gate pass ', v_pass_code, ' issued and APPROVED.')
        END                                            AS message;
END$$

-- 4.3 Approve or Reject a Gate Pass (Host Approval Workflow)
CREATE PROCEDURE sp_approve_gate_pass(
    IN p_pass_code        VARCHAR(20),
    IN p_approver_emp_id  INT,
    IN p_decision         VARCHAR(10),
    IN p_notes            VARCHAR(255)
)
SQL SECURITY DEFINER
BEGIN
    DECLARE v_clean_code    VARCHAR(20);
    DECLARE v_pass_id       INT DEFAULT NULL;
    DECLARE v_status        VARCHAR(20);
    DECLARE v_visitor_id    INT;
    DECLARE v_host_emp_id   INT;
    DECLARE v_emp_active    INT DEFAULT NULL;
    DECLARE v_clean_dec     VARCHAR(10);
    DECLARE v_errno         INT DEFAULT 0;
    DECLARE v_errmsg        TEXT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_errno = MYSQL_ERRNO, v_errmsg = MESSAGE_TEXT;
        ROLLBACK;
        RESIGNAL;
    END;

    SET v_clean_code = UPPER(TRIM(COALESCE(p_pass_code, '')));
    SET v_clean_dec  = UPPER(TRIM(COALESCE(p_decision, 'APPROVE')));

    SELECT is_active INTO v_emp_active FROM employees WHERE emp_id = p_approver_emp_id;
    IF v_emp_active IS NULL OR v_emp_active = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MYSQL_ERRNO = 50007,
                MESSAGE_TEXT = 'APPROVER INACTIVE OR NOT FOUND: Approver must be an active employee.';
    END IF;

    START TRANSACTION;

    SELECT pass_id, status, visitor_id, host_emp_id
      INTO v_pass_id, v_status, v_visitor_id, v_host_emp_id
      FROM gate_passes
     WHERE pass_code = v_clean_code
       FOR UPDATE;

    IF v_pass_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MYSQL_ERRNO = 50003,
                MESSAGE_TEXT = 'PASS NOT FOUND: No gate pass matches the provided pass code.';
    END IF;

    IF v_status <> 'PENDING_APPROVAL' THEN
        SET @v_err = LEFT(CONCAT('ILLEGAL APPROVAL: Pass ', v_clean_code,
                                 ' is currently ', v_status,
                                 ' (only PENDING_APPROVAL passes can be approved/rejected).'), 128);
        SIGNAL SQLSTATE '45000'
            SET MYSQL_ERRNO = 50006,
                MESSAGE_TEXT = @v_err;
    END IF;

    IF v_clean_dec = 'APPROVE' THEN
        UPDATE gate_passes
           SET status             = 'APPROVED',
               approved_by_emp_id = p_approver_emp_id,
               approved_at        = NOW(),
               approval_notes     = COALESCE(NULLIF(TRIM(p_notes), ''), 'Approved by host')
         WHERE pass_id = v_pass_id;

        COMMIT;

        SELECT
            'APPROVED'   AS status_code,
            v_pass_id    AS pass_id,
            v_clean_code AS pass_code,
            CONCAT('Pass ', v_clean_code, ' successfully APPROVED by Host Emp #', p_approver_emp_id, '.') AS message;
    ELSE
        UPDATE gate_passes
           SET status             = 'REVOKED',
               approved_by_emp_id = p_approver_emp_id,
               approved_at        = NOW(),
               revoke_reason      = CONCAT('HOST REJECTED: ', COALESCE(NULLIF(TRIM(p_notes), ''), 'Access request rejected by host'))
         WHERE pass_id = v_pass_id;

        COMMIT;

        SELECT
            'REVOKED'    AS status_code,
            v_pass_id    AS pass_id,
            v_clean_code AS pass_code,
            CONCAT('Pass ', v_clean_code, ' REJECTED by Host Emp #', p_approver_emp_id, '.') AS message;
    END IF;
END$$

-- 4.4 Process Gate Check-In with Category Perimeter, Window & Escort Checks
CREATE PROCEDURE sp_process_gate_checkin(
    IN p_pass_code     VARCHAR(20),
    IN p_guard_id      INT,
    IN p_checkpoint_id INT
)
SQL SECURITY DEFINER
BEGIN
    DECLARE v_clean_code      VARCHAR(20);
    DECLARE v_pass_id         INT DEFAULT NULL;
    DECLARE v_visitor_id      INT;
    DECLARE v_host_emp_id     INT;
    DECLARE v_category_id     INT;
    DECLARE v_escort_emp_id   INT;
    DECLARE v_status          VARCHAR(20);
    DECLARE v_valid_from      DATETIME;
    DECLARE v_valid_until     DATETIME;
    DECLARE v_guard_active    INT DEFAULT NULL;
    DECLARE v_ckpt_active     INT DEFAULT NULL;
    DECLARE v_bl_reason       VARCHAR(255) DEFAULT NULL;
    DECLARE v_visitor_name    VARCHAR(120);
    DECLARE v_host_name       VARCHAR(120);
    DECLARE v_dept_name       VARCHAR(80);
    DECLARE v_cat_code        VARCHAR(30);
    DECLARE v_cat_req_escort  TINYINT(1);
    DECLARE v_cat_from_time   TIME;
    DECLARE v_cat_to_time     TIME;
    DECLARE v_ckpt_allowed    INT DEFAULT 0;
    DECLARE v_checkin_ts      DATETIME;
    DECLARE v_errno           INT DEFAULT 0;
    DECLARE v_errmsg          TEXT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_errno = MYSQL_ERRNO, v_errmsg = MESSAGE_TEXT;
        ROLLBACK;
        START TRANSACTION;
        INSERT INTO access_audit_logs (
            pass_id, attempted_code, event_type, from_status, to_status,
            guard_id, checkpoint_id, details
        ) VALUES (
            v_pass_id,
            LEFT(UPPER(TRIM(COALESCE(p_pass_code, ''))), 20),
            'DENIED',
            v_status,
            'CHECKIN_DENIED',
            p_guard_id,
            p_checkpoint_id,
            LEFT(CONCAT('CHECK-IN DENIED [Err ', v_errno, ']: ', v_errmsg), 500)
        );
        COMMIT;
        RESIGNAL;
    END;

    SET v_clean_code = UPPER(TRIM(COALESCE(p_pass_code, '')));

    SELECT is_active INTO v_guard_active FROM security_guards WHERE guard_id = p_guard_id;
    SELECT is_active INTO v_ckpt_active  FROM checkpoints     WHERE checkpoint_id = p_checkpoint_id;

    IF v_guard_active IS NULL OR v_guard_active = 0 OR v_ckpt_active IS NULL OR v_ckpt_active = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MYSQL_ERRNO = 50008,
                MESSAGE_TEXT = 'INVALID TERMINAL CONTEXT: Security guard or gate checkpoint is missing or inactive.';
    END IF;

    START TRANSACTION;

    SELECT pass_id, visitor_id, host_emp_id, category_id, escort_emp_id, status, valid_from, valid_until
      INTO v_pass_id, v_visitor_id, v_host_emp_id, v_category_id, v_escort_emp_id, v_status, v_valid_from, v_valid_until
      FROM gate_passes
     WHERE pass_code = v_clean_code
       FOR UPDATE;

    IF v_pass_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MYSQL_ERRNO = 50003,
                MESSAGE_TEXT = 'PASS NOT FOUND: No gate pass matches the scanned pass code.';
    END IF;

    -- Fetch Category Details
    SELECT category_code, requires_escort, allowed_from_time, allowed_to_time
      INTO v_cat_code, v_cat_req_escort, v_cat_from_time, v_cat_to_time
      FROM visitor_categories
     WHERE category_id = v_category_id;

    -- Blacklist verification
    SELECT reason INTO v_bl_reason
      FROM visitor_blacklist
     WHERE visitor_id = v_visitor_id
       AND lifted_at IS NULL
       AND start_at <= NOW()
       AND (end_at IS NULL OR end_at > NOW())
     LIMIT 1;

    IF v_bl_reason IS NOT NULL THEN
        SET @v_err = LEFT(CONCAT('SECURITY ALERT: Visitor #', v_visitor_id,
                                 ' was blacklisted after pass issuance (', v_bl_reason, '). Entry denied.'), 128);
        SIGNAL SQLSTATE '45000'
            SET MYSQL_ERRNO = 50001,
                MESSAGE_TEXT = @v_err;
    END IF;

    -- Check expired status or past valid_until window first
    IF v_status = 'EXPIRED' OR (v_status IN ('APPROVED', 'PENDING_APPROVAL') AND NOW() > v_valid_until) THEN
        SET @v_err = LEFT(CONCAT('PASS EXPIRED: Pass ', v_clean_code,
                                 ' expired at ', DATE_FORMAT(v_valid_until, '%Y-%m-%d %H:%i:%s'), '.'), 128);
        SIGNAL SQLSTATE '45000'
            SET MYSQL_ERRNO = 50005,
                MESSAGE_TEXT = @v_err;
    END IF;

    -- Check if pass is still PENDING_APPROVAL (SQLSTATE 45000 / Errno 50015)
    IF v_status = 'PENDING_APPROVAL' THEN
        SET @v_err = LEFT(CONCAT('PASS PENDING APPROVAL: Gate pass ', v_clean_code,
                                 ' requires host employee approval before campus admission.'), 128);
        SIGNAL SQLSTATE '45000'
            SET MYSQL_ERRNO = 50015,
                MESSAGE_TEXT = @v_err;
    END IF;

    -- Validate state must be APPROVED
    IF v_status <> 'APPROVED' THEN
        SET @v_err = LEFT(CONCAT('ILLEGAL STATE TRANSITION: Pass ', v_clean_code,
                                 ' is currently ', v_status, ' (must be APPROVED to check in).'), 128);
        SIGNAL SQLSTATE '45000'
            SET MYSQL_ERRNO = 50006,
                MESSAGE_TEXT = @v_err;
    END IF;

    -- Validate valid_from window
    IF NOW() < v_valid_from THEN
        SET @v_err = LEFT(CONCAT('PASS NOT YET VALID: Pass ', v_clean_code,
                                 ' opens at ', DATE_FORMAT(v_valid_from, '%Y-%m-%d %H:%i:%s'), '.'), 128);
        SIGNAL SQLSTATE '45000'
            SET MYSQL_ERRNO = 50004,
                MESSAGE_TEXT = @v_err;
    END IF;

    -- Enforce Category Authorized Checkpoint (SQLSTATE 45000 / Errno 50016)
    IF EXISTS (SELECT 1 FROM category_checkpoints WHERE category_id = v_category_id) THEN
        SELECT COUNT(*) INTO v_ckpt_allowed
          FROM category_checkpoints
         WHERE category_id   = v_category_id
           AND checkpoint_id = p_checkpoint_id;

        IF v_ckpt_allowed = 0 THEN
            SET @v_err = LEFT(CONCAT('CHECKPOINT NOT PERMITTED: Category ', v_cat_code,
                                     ' is not authorized to enter through this gate checkpoint.'), 128);
            SIGNAL SQLSTATE '45000'
                SET MYSQL_ERRNO = 50016,
                    MESSAGE_TEXT = @v_err;
        END IF;
    END IF;

    -- Enforce Category Time-of-Day Window (SQLSTATE 45000 / Errno 50017)
    IF CURRENT_TIME() < v_cat_from_time OR CURRENT_TIME() > v_cat_to_time THEN
        SET @v_err = LEFT(CONCAT('TIME WINDOW VIOLATION: Category ', v_cat_code,
                                 ' entry is permitted only between ',
                                 DATE_FORMAT(v_cat_from_time, '%H:%i'), ' and ',
                                 DATE_FORMAT(v_cat_to_time, '%H:%i'), '.'), 128);
        SIGNAL SQLSTATE '45000'
            SET MYSQL_ERRNO = 50017,
                MESSAGE_TEXT = @v_err;
    END IF;

    -- Enforce Escort Requirement (SQLSTATE 45000 / Errno 50018)
    IF v_cat_req_escort = 1 AND v_escort_emp_id IS NULL THEN
        SET @v_err = LEFT(CONCAT('ESCORT REQUIRED: Category ', v_cat_code,
                                 ' requires an assigned host employee escort.'), 128);
        SIGNAL SQLSTATE '45000'
            SET MYSQL_ERRNO = 50018,
                MESSAGE_TEXT = @v_err;
    END IF;

    SET v_checkin_ts = NOW();

    UPDATE gate_passes
       SET status                 = 'ACTIVE_ON_CAMPUS',
           check_in_time          = v_checkin_ts,
           check_in_guard_id      = p_guard_id,
           check_in_checkpoint_id = p_checkpoint_id
     WHERE pass_id = v_pass_id;

    SELECT CONCAT(v.first_name, ' ', v.last_name),
           CONCAT(e.first_name, ' ', e.last_name),
           d.dept_name
      INTO v_visitor_name, v_host_name, v_dept_name
      FROM visitors v
      JOIN employees e   ON e.emp_id  = v_host_emp_id
      JOIN departments d ON d.dept_id = e.dept_id
     WHERE v.visitor_id = v_visitor_id;

    COMMIT;

    SELECT
        'ACTIVE_ON_CAMPUS'                              AS status_code,
        v_pass_id                                       AS pass_id,
        v_clean_code                                    AS pass_code,
        v_visitor_name                                  AS visitor_name,
        v_host_name                                     AS host_name,
        v_dept_name                                     AS dept_name,
        v_cat_code                                      AS category_code,
        DATE_FORMAT(v_checkin_ts, '%Y-%m-%d %H:%i:%s')  AS check_in_time,
        DATE_FORMAT(v_valid_until, '%Y-%m-%d %H:%i:%s') AS valid_until,
        CONCAT('CHECKED IN: ', v_visitor_name, ' admitted on pass ', v_clean_code,
               ' [Category: ', v_cat_code, ', Host: ', v_host_name, '].') AS message;
END$$

-- 4.5 Park Vehicle (Allocates parking session with zone capacity check and category limits)
CREATE PROCEDURE sp_park_vehicle(
    IN p_pass_code VARCHAR(20),
    IN p_zone_id   INT,
    IN p_guard_id  INT
)
SQL SECURITY DEFINER
BEGIN
    DECLARE v_clean_code   VARCHAR(20);
    DECLARE v_pass_id      INT DEFAULT NULL;
    DECLARE v_vehicle_id   INT DEFAULT NULL;
    DECLARE v_category_id  INT;
    DECLARE v_status       VARCHAR(20);
    DECLARE v_zone_cap     INT;
    DECLARE v_zone_occ     INT DEFAULT 0;
    DECLARE v_zone_code    VARCHAR(20);
    DECLARE v_zone_types   VARCHAR(120);
    DECLARE v_veh_type     VARCHAR(20);
    DECLARE v_veh_reg      VARCHAR(20);
    DECLARE v_cat_park_min INT DEFAULT 240;
    DECLARE v_session_id   INT;
    DECLARE v_errno        INT DEFAULT 0;
    DECLARE v_errmsg       TEXT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_errno = MYSQL_ERRNO, v_errmsg = MESSAGE_TEXT;
        ROLLBACK;
        RESIGNAL;
    END;

    SET v_clean_code = UPPER(TRIM(COALESCE(p_pass_code, '')));

    START TRANSACTION;

    SELECT pass_id, vehicle_id, category_id, status
      INTO v_pass_id, v_vehicle_id, v_category_id, v_status
      FROM gate_passes
     WHERE pass_code = v_clean_code
       FOR UPDATE;

    IF v_pass_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MYSQL_ERRNO = 50003,
                MESSAGE_TEXT = 'PASS NOT FOUND: No gate pass matches the provided pass code.';
    END IF;

    IF v_status <> 'ACTIVE_ON_CAMPUS' THEN
        SET @v_err = LEFT(CONCAT('PARKING DENIED: Visitor must be ACTIVE_ON_CAMPUS to park vehicle (Pass status: ',
                                 v_status, ').'), 128);
        SIGNAL SQLSTATE '45000'
            SET MYSQL_ERRNO = 50006,
                MESSAGE_TEXT = @v_err;
    END IF;

    IF v_vehicle_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MYSQL_ERRNO = 50014,
                MESSAGE_TEXT = 'NO VEHICLE: This gate pass has no registered vehicle associated with it.';
    END IF;

    -- Fetch Zone details
    SELECT zone_code, capacity, allowed_vehicle_types
      INTO v_zone_code, v_zone_cap, v_zone_types
      FROM parking_zones
     WHERE zone_id = p_zone_id AND is_active = 1
       FOR SHARE;

    IF v_zone_code IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MYSQL_ERRNO = 50003,
                MESSAGE_TEXT = 'PARKING ZONE NOT FOUND: The selected parking zone does not exist or is inactive.';
    END IF;

    -- Fetch vehicle type
    SELECT vehicle_type, registration_no
      INTO v_veh_type, v_veh_reg
      FROM vehicles
     WHERE vehicle_id = v_vehicle_id;

    -- Verify vehicle type is allowed in zone (SQLSTATE 45000 / Errno 50020)
    IF FIND_IN_SET(v_veh_type, v_zone_types) = 0 THEN
        SET @v_err = LEFT(CONCAT('VEHICLE TYPE NOT PERMITTED: Zone ', v_zone_code,
                                 ' accepts [', v_zone_types, '] but vehicle is ', v_veh_type, '.'), 128);
        SIGNAL SQLSTATE '45000'
            SET MYSQL_ERRNO = 50020,
                MESSAGE_TEXT = @v_err;
    END IF;

    -- Verify vehicle does not already have an active parking session (SQLSTATE 45000 / Errno 50021)
    IF EXISTS (SELECT 1 FROM parking_sessions WHERE vehicle_id = v_vehicle_id AND exit_time IS NULL) THEN
        SET @v_err = LEFT(CONCAT('VEHICLE ALREADY PARKED: Vehicle ', v_veh_reg,
                                 ' already holds an active parking session.'), 128);
        SIGNAL SQLSTATE '45000'
            SET MYSQL_ERRNO = 50021,
                MESSAGE_TEXT = @v_err;
    END IF;

    -- Verify Zone Capacity (SQLSTATE 45000 / Errno 50019)
    SELECT COUNT(*) INTO v_zone_occ
      FROM parking_sessions
     WHERE zone_id = p_zone_id
       AND exit_time IS NULL;

    IF v_zone_occ >= v_zone_cap THEN
        SET @v_err = LEFT(CONCAT('PARKING ZONE FULL: Zone ', v_zone_code,
                                 ' has reached its capacity limit (', v_zone_cap, ' spots).'), 128);
        SIGNAL SQLSTATE '45000'
            SET MYSQL_ERRNO = 50019,
                MESSAGE_TEXT = @v_err;
    END IF;

    -- Fetch category parking limit
    SELECT max_parking_minutes INTO v_cat_park_min
      FROM visitor_categories
     WHERE category_id = v_category_id;

    -- Insert active parking session (uk_active_vehicle_parking ensures single active parking)
    INSERT INTO parking_sessions (pass_id, vehicle_id, zone_id, allocated_minutes, entry_time)
    VALUES (v_pass_id, v_vehicle_id, p_zone_id, v_cat_park_min, NOW());

    SET v_session_id = LAST_INSERT_ID();

    -- Audit log
    INSERT INTO access_audit_logs (
        pass_id, attempted_code, event_type, from_status, to_status, guard_id, details
    ) VALUES (
        v_pass_id,
        v_clean_code,
        'PARKED',
        'ACTIVE_ON_CAMPUS',
        'ACTIVE_ON_CAMPUS',
        p_guard_id,
        CONCAT('Vehicle ', v_veh_reg, ' parked in zone ', v_zone_code,
               ' (Allocated limit: ', v_cat_park_min, ' min).')
    );

    COMMIT;

    SELECT
        'PARKED'       AS status_code,
        v_session_id   AS session_id,
        v_clean_code   AS pass_code,
        v_veh_reg      AS vehicle_reg_no,
        v_zone_code    AS zone_code,
        v_cat_park_min AS allocated_minutes,
        CONCAT('Vehicle ', v_veh_reg, ' parked in ', v_zone_code,
               ' (Limit: ', v_cat_park_min, ' min).') AS message;
END$$

-- 4.6 Exit Parking (Completes parking session and checks for parking overstay)
CREATE PROCEDURE sp_exit_parking(
    IN p_pass_code VARCHAR(20),
    IN p_guard_id  INT
)
SQL SECURITY DEFINER
BEGIN
    DECLARE v_clean_code   VARCHAR(20);
    DECLARE v_pass_id      INT DEFAULT NULL;
    DECLARE v_session_id   INT DEFAULT NULL;
    DECLARE v_entry_time   DATETIME;
    DECLARE v_alloc_min    INT;
    DECLARE v_veh_reg      VARCHAR(20);
    DECLARE v_zone_code    VARCHAR(20);
    DECLARE v_actual_min   INT;
    DECLARE v_is_overstay  TINYINT(1) DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    SET v_clean_code = UPPER(TRIM(COALESCE(p_pass_code, '')));

    START TRANSACTION;

    SELECT gp.pass_id, ps.session_id, ps.entry_time, ps.allocated_minutes, v.registration_no, pz.zone_code
      INTO v_pass_id, v_session_id, v_entry_time, v_alloc_min, v_veh_reg, v_zone_code
      FROM gate_passes gp
      JOIN parking_sessions ps ON ps.pass_id = gp.pass_id AND ps.exit_time IS NULL
      JOIN vehicles v         ON v.vehicle_id = ps.vehicle_id
      JOIN parking_zones pz   ON pz.zone_id   = ps.zone_id
     WHERE gp.pass_code = v_clean_code
       FOR UPDATE;

    IF v_session_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MYSQL_ERRNO = 50003,
                MESSAGE_TEXT = 'NO ACTIVE PARKING: This pass has no active parked vehicle session.';
    END IF;

    SET v_actual_min = TIMESTAMPDIFF(MINUTE, v_entry_time, NOW());
    IF v_actual_min > v_alloc_min THEN
        SET v_is_overstay = 1;
    END IF;

    UPDATE parking_sessions
       SET exit_time   = NOW(),
           is_overstay = v_is_overstay
     WHERE session_id = v_session_id;

    INSERT INTO access_audit_logs (
        pass_id, attempted_code, event_type, from_status, to_status, guard_id, details
    ) VALUES (
        v_pass_id,
        v_clean_code,
        'PARKING_EXIT',
        'ACTIVE_ON_CAMPUS',
        'ACTIVE_ON_CAMPUS',
        p_guard_id,
        CONCAT('Vehicle ', v_veh_reg, ' exited parking zone ', v_zone_code,
               ' after ', v_actual_min, ' min (Limit: ', v_alloc_min, ' min)',
               IF(v_is_overstay = 1, ' [PARKING OVERSTAY VIOLATION]', ' [ON TIME]'), '.')
    );

    COMMIT;

    SELECT
        'PARKING_EXITED' AS status_code,
        v_session_id     AS session_id,
        v_clean_code     AS pass_code,
        v_veh_reg        AS vehicle_reg_no,
        v_actual_min     AS duration_minutes,
        v_alloc_min      AS allocated_minutes,
        v_is_overstay    AS is_overstay,
        CONCAT('Vehicle ', v_veh_reg, ' departed parking zone ', v_zone_code,
               ' after ', v_actual_min, ' min',
               IF(v_is_overstay = 1, ' [OVERSTAY VIOLATION]', ' [ON TIME]'), '.') AS message;
END$$

-- 4.7 Process Gate Check-Out (Closes gate pass and automatically closes any active parking session)
CREATE PROCEDURE sp_process_gate_checkout(
    IN p_pass_code     VARCHAR(20),
    IN p_guard_id      INT,
    IN p_checkpoint_id INT
)
SQL SECURITY DEFINER
BEGIN
    DECLARE v_clean_code    VARCHAR(20);
    DECLARE v_pass_id       INT DEFAULT NULL;
    DECLARE v_visitor_id    INT;
    DECLARE v_status        VARCHAR(20);
    DECLARE v_checkin_time  DATETIME;
    DECLARE v_valid_until   DATETIME;
    DECLARE v_checkout_ts   DATETIME;
    DECLARE v_guard_active  INT DEFAULT NULL;
    DECLARE v_ckpt_active   INT DEFAULT NULL;
    DECLARE v_duration_min  INT;
    DECLARE v_is_overstay   TINYINT(1);
    DECLARE v_overstay_min  INT DEFAULT 0;
    DECLARE v_visitor_name  VARCHAR(120);
    DECLARE v_errno         INT DEFAULT 0;
    DECLARE v_errmsg        TEXT;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_errno = MYSQL_ERRNO, v_errmsg = MESSAGE_TEXT;
        ROLLBACK;
        START TRANSACTION;
        INSERT INTO access_audit_logs (
            pass_id, attempted_code, event_type, from_status, to_status,
            guard_id, checkpoint_id, details
        ) VALUES (
            v_pass_id,
            LEFT(UPPER(TRIM(COALESCE(p_pass_code, ''))), 20),
            'DENIED',
            v_status,
            'CHECKOUT_DENIED',
            p_guard_id,
            p_checkpoint_id,
            LEFT(CONCAT('CHECK-OUT DENIED [Err ', v_errno, ']: ', v_errmsg), 500)
        );
        COMMIT;
        RESIGNAL;
    END;

    SET v_clean_code = UPPER(TRIM(COALESCE(p_pass_code, '')));

    SELECT is_active INTO v_guard_active FROM security_guards WHERE guard_id = p_guard_id;
    SELECT is_active INTO v_ckpt_active  FROM checkpoints     WHERE checkpoint_id = p_checkpoint_id;

    IF v_guard_active IS NULL OR v_guard_active = 0 OR v_ckpt_active IS NULL OR v_ckpt_active = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MYSQL_ERRNO = 50008,
                MESSAGE_TEXT = 'INVALID TERMINAL CONTEXT: Security guard or gate checkpoint is missing or inactive.';
    END IF;

    START TRANSACTION;

    SELECT pass_id, visitor_id, status, check_in_time, valid_until
      INTO v_pass_id, v_visitor_id, v_status, v_checkin_time, v_valid_until
      FROM gate_passes
     WHERE pass_code = v_clean_code
       FOR UPDATE;

    IF v_pass_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MYSQL_ERRNO = 50003,
                MESSAGE_TEXT = 'PASS NOT FOUND: No gate pass matches the scanned pass code.';
    END IF;

    IF v_status <> 'ACTIVE_ON_CAMPUS' THEN
        SET @v_err = LEFT(CONCAT('ILLEGAL STATE TRANSITION: Pass ', v_clean_code,
                                 ' has status ', v_status,
                                 ' (must be ACTIVE_ON_CAMPUS to check out).'), 128);
        SIGNAL SQLSTATE '45000'
            SET MYSQL_ERRNO = 50006,
                MESSAGE_TEXT = @v_err;
    END IF;

    SET v_checkout_ts = GREATEST(NOW(), v_checkin_time);

    -- Auto-exit any active parking session for this pass
    UPDATE parking_sessions
       SET exit_time   = v_checkout_ts,
           is_overstay = IF(TIMESTAMPDIFF(MINUTE, entry_time, v_checkout_ts) > allocated_minutes, 1, 0)
     WHERE pass_id   = v_pass_id
       AND exit_time IS NULL;

    -- Update gate pass status to COMPLETED
    UPDATE gate_passes
       SET status                  = 'COMPLETED',
           check_out_time          = v_checkout_ts,
           check_out_guard_id      = p_guard_id,
           check_out_checkpoint_id = p_checkpoint_id
     WHERE pass_id = v_pass_id;

    SELECT visit_duration_min, is_overstay
      INTO v_duration_min, v_is_overstay
      FROM gate_passes
     WHERE pass_id = v_pass_id;

    IF v_is_overstay = 1 THEN
        SET v_overstay_min = GREATEST(1, TIMESTAMPDIFF(MINUTE, v_valid_until, v_checkout_ts));
    END IF;

    SELECT CONCAT(first_name, ' ', last_name) INTO v_visitor_name
      FROM visitors WHERE visitor_id = v_visitor_id;

    COMMIT;

    SELECT
        'COMPLETED'                                      AS status_code,
        v_pass_id                                        AS pass_id,
        v_clean_code                                     AS pass_code,
        v_visitor_name                                   AS visitor_name,
        DATE_FORMAT(v_checkin_time, '%Y-%m-%d %H:%i:%s') AS check_in_time,
        DATE_FORMAT(v_checkout_ts,  '%Y-%m-%d %H:%i:%s') AS check_out_time,
        v_duration_min                                   AS visit_duration_min,
        v_is_overstay                                    AS is_overstay,
        v_overstay_min                                   AS overstay_minutes,
        CONCAT('CHECKED OUT: ', v_visitor_name, ' exited after ', v_duration_min, ' min',
               IF(v_is_overstay = 1,
                  CONCAT(' [OVERSTAY VIOLATION: +', v_overstay_min, ' min past valid_until]'),
                  ' [WITHIN VALID WINDOW]'), '.')        AS message;
END$$

-- 4.8 Revoke a Gate Pass
CREATE PROCEDURE sp_revoke_gate_pass(
    IN p_pass_code VARCHAR(20),
    IN p_guard_id  INT,
    IN p_reason    VARCHAR(255)
)
SQL SECURITY DEFINER
BEGIN
    DECLARE v_clean_code VARCHAR(20);
    DECLARE v_pass_id    INT DEFAULT NULL;
    DECLARE v_status     VARCHAR(20);

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    SET v_clean_code = UPPER(TRIM(COALESCE(p_pass_code, '')));

    START TRANSACTION;

    SELECT pass_id, status INTO v_pass_id, v_status
      FROM gate_passes
     WHERE pass_code = v_clean_code
       FOR UPDATE;

    IF v_pass_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MYSQL_ERRNO = 50003,
                MESSAGE_TEXT = 'PASS NOT FOUND: Cannot revoke unknown pass code.';
    END IF;

    -- Also close any active parking session
    UPDATE parking_sessions
       SET exit_time = NOW()
     WHERE pass_id = v_pass_id AND exit_time IS NULL;

    UPDATE gate_passes
       SET status             = 'REVOKED',
           revoke_reason      = COALESCE(NULLIF(TRIM(p_reason), ''), 'Administrative security revocation'),
           check_out_guard_id = COALESCE(check_out_guard_id, p_guard_id)
     WHERE pass_id = v_pass_id;

    COMMIT;

    SELECT
        'REVOKED'    AS status_code,
        v_pass_id    AS pass_id,
        v_clean_code AS pass_code,
        CONCAT('Pass ', v_clean_code, ' transitioned from ', v_status, ' to REVOKED.') AS message;
END$$

-- 4.9 Blacklist a Visitor
CREATE PROCEDURE sp_blacklist_visitor(
    IN p_visitor_id     INT,
    IN p_reason         VARCHAR(255),
    IN p_severity       VARCHAR(16),
    IN p_duration_hours INT,
    IN p_guard_id       INT
)
SQL SECURITY DEFINER
BEGIN
    DECLARE v_end_at     DATETIME DEFAULT NULL;
    DECLARE v_bl_id      INT;
    DECLARE v_vis_exists INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    SELECT COUNT(*) INTO v_vis_exists FROM visitors WHERE visitor_id = p_visitor_id;
    IF v_vis_exists = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MYSQL_ERRNO = 50003,
                MESSAGE_TEXT = 'VISITOR NOT FOUND: Cannot blacklist unknown visitor_id.';
    END IF;

    IF p_duration_hours IS NOT NULL AND p_duration_hours > 0 THEN
        SET v_end_at = NOW() + INTERVAL p_duration_hours HOUR;
    END IF;

    START TRANSACTION;

    INSERT INTO visitor_blacklist (visitor_id, reason, severity, start_at, end_at, created_by)
    VALUES (
        p_visitor_id,
        COALESCE(NULLIF(TRIM(p_reason), ''), 'Security policy violation'),
        COALESCE(NULLIF(UPPER(TRIM(p_severity)), ''), 'HIGH'),
        NOW(),
        v_end_at,
        p_guard_id
    );

    SET v_bl_id = LAST_INSERT_ID();

    COMMIT;

    SELECT
        'BLACKLISTED' AS status_code,
        v_bl_id       AS blacklist_id,
        p_visitor_id  AS visitor_id,
        CONCAT('Visitor #', p_visitor_id, ' added to security blacklist (',
               IF(v_end_at IS NULL, 'PERMANENT', CONCAT('until ', DATE_FORMAT(v_end_at, '%Y-%m-%d %H:%i'))), ').') AS message;
END$$

-- 4.10 Lift Blacklist
CREATE PROCEDURE sp_lift_blacklist(
    IN p_blacklist_id  INT,
    IN p_lifted_reason VARCHAR(255)
)
SQL SECURITY DEFINER
BEGIN
    DECLARE v_exists INT DEFAULT 0;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT COUNT(*) INTO v_exists
      FROM visitor_blacklist
     WHERE blacklist_id = p_blacklist_id AND lifted_at IS NULL
       FOR UPDATE;

    IF v_exists = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MYSQL_ERRNO = 50003,
                MESSAGE_TEXT = 'BLACKLIST ENTRY NOT FOUND: Entry does not exist or is already lifted.';
    END IF;

    UPDATE visitor_blacklist
       SET lifted_at     = NOW(),
           lifted_reason = COALESCE(NULLIF(TRIM(p_lifted_reason), ''), 'Cleared by security administration')
     WHERE blacklist_id = p_blacklist_id;

    COMMIT;

    SELECT
        'LIFTED'       AS status_code,
        p_blacklist_id AS blacklist_id,
        CONCAT('Blacklist entry #', p_blacklist_id, ' lifted.') AS message;
END$$

-- 4.11 Expire Stale Passes & Flag Overstays (Passes + Active Parking Sessions)
CREATE PROCEDURE sp_expire_stale_passes()
SQL SECURITY DEFINER
BEGIN
    DECLARE v_expired_count  INT DEFAULT 0;
    DECLARE v_overstay_count INT DEFAULT 0;
    DECLARE v_park_overstays INT DEFAULT 0;

    START TRANSACTION;

    -- 1. Transition unused APPROVED or PENDING_APPROVAL passes past valid_until -> EXPIRED
    UPDATE gate_passes
       SET status = 'EXPIRED'
     WHERE status IN ('APPROVED', 'PENDING_APPROVAL')
       AND valid_until < NOW();
    SET v_expired_count = ROW_COUNT();

    -- 2. Flag currently checked-in passes that have crossed valid_until
    UPDATE gate_passes
       SET is_overstay = 1
     WHERE status = 'ACTIVE_ON_CAMPUS'
       AND is_overstay = 0
       AND valid_until < NOW();
    SET v_overstay_count = ROW_COUNT();

    -- 3. Flag currently active parking sessions that have exceeded their allocated duration
    UPDATE parking_sessions
       SET is_overstay = 1
     WHERE exit_time IS NULL
       AND is_overstay = 0
       AND TIMESTAMPDIFF(MINUTE, entry_time, NOW()) > allocated_minutes;
    SET v_park_overstays = ROW_COUNT();

    COMMIT;

    SELECT
        'SWEEP_COMPLETE'  AS status_code,
        v_expired_count   AS expired_passes,
        v_overstay_count  AS newly_flagged_overstays,
        v_park_overstays  AS newly_flagged_parking_overstays,
        CONCAT('Sweep complete: ', v_expired_count, ' stale pass(es) marked EXPIRED, ',
               v_overstay_count, ' campus overstay(s) flagged, ',
               v_park_overstays, ' parking overstay(s) flagged.') AS message;
END$$

-- 4.12 Load generator for benchmark tests
CREATE PROCEDURE sp_generate_load(IN p_num_rows INT)
SQL SECURITY DEFINER
BEGIN
    DECLARE v_target INT;
    SET v_target = LEAST(GREATEST(COALESCE(p_num_rows, 50000), 100), 100000);

    INSERT INTO gate_passes (
        pass_token, pass_code, visitor_id, host_emp_id, category_id, vehicle_id,
        visit_purpose, valid_from, valid_until, status,
        check_in_time, check_in_guard_id, check_in_checkpoint_id,
        check_out_time, check_out_guard_id, check_out_checkpoint_id,
        is_overstay, created_at
    )
    SELECT
        UUID_TO_BIN(UUID(), 1),
        CONCAT('GP-', LPAD(UPPER(CONV(seq.n, 10, 36)), 6, '0')),
        4 + MOD(seq.n, 22),
        1 + MOD(seq.n, 15),
        1 + MOD(seq.n, 5),
        NULL,
        CONCAT('Synthetic benchmark visit #', seq.n),
        ts.base_ts,
        ts.base_ts + INTERVAL 4 HOUR,
        CASE MOD(seq.n, 10)
            WHEN 0 THEN 'EXPIRED'
            WHEN 1 THEN 'REVOKED'
            ELSE 'COMPLETED'
        END,
        IF(MOD(seq.n, 10) IN (0, 1), NULL, ts.base_ts + INTERVAL 5 MINUTE),
        IF(MOD(seq.n, 10) IN (0, 1), NULL, 1 + MOD(seq.n, 5)),
        IF(MOD(seq.n, 10) IN (0, 1), NULL, 1 + MOD(seq.n, 4)),
        IF(MOD(seq.n, 10) IN (0, 1), NULL,
           ts.base_ts + INTERVAL (45 + MOD(seq.n, 260)) MINUTE),
        IF(MOD(seq.n, 10) IN (0, 1), NULL, 1 + MOD(seq.n + 1, 5)),
        IF(MOD(seq.n, 10) IN (0, 1), NULL, 1 + MOD(seq.n + 1, 4)),
        IF(MOD(seq.n, 10) NOT IN (0, 1) AND (45 + MOD(seq.n, 260)) > 240, 1, 0),
        ts.base_ts - INTERVAL 15 MINUTE
    FROM (
        SELECT (d0.d + d1.d * 10 + d2.d * 100 + d3.d * 1000 + d4.d * 10000) + 1 AS n
        FROM (SELECT 0 d UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
              UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) d0
        CROSS JOIN (SELECT 0 d UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
                    UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) d1
        CROSS JOIN (SELECT 0 d UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
                    UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) d2
        CROSS JOIN (SELECT 0 d UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
                    UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) d3
        CROSS JOIN (SELECT 0 d UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4
                    UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) d4
    ) seq
    CROSS JOIN LATERAL (
        SELECT (NOW() - INTERVAL (10 + MOD(seq.n, 180)) DAY - INTERVAL MOD(seq.n, 86400) SECOND) AS base_ts
    ) ts
    WHERE seq.n <= v_target;

    ANALYZE TABLE gate_passes, access_audit_logs;
END$$

DELIMITER ;


-- ============================================================================
-- SECTION 5: SCHEDULED BACKGROUND EVENT
-- ============================================================================

CREATE EVENT evt_expire_stale_passes
ON SCHEDULE EVERY 1 MINUTE
STARTS CURRENT_TIMESTAMP + INTERVAL 1 MINUTE
ON COMPLETION PRESERVE
ENABLE
COMMENT 'Sweeps unused passes past valid_until to EXPIRED, flags campus & parking overstays'
DO
    CALL sp_expire_stale_passes();


-- ============================================================================
-- SECTION 6: OPTIMIZED VIEWS & WINDOW FUNCTIONS
-- ============================================================================

-- 6.1 Real-Time Campus Occupancy View
CREATE OR REPLACE VIEW vw_live_campus_occupancy AS
SELECT
    gp.pass_id,
    gp.pass_code,
    BIN_TO_UUID(gp.pass_token, 1)                         AS pass_uuid,
    gp.visitor_id,
    CONCAT(v.first_name, ' ', v.last_name)                AS visitor_name,
    v.phone                                               AS visitor_phone,
    COALESCE(v.company_name, 'Independent')               AS visitor_company,
    vc.category_code,
    vc.category_name,
    CONCAT(ipt.type_code, ' ***-', v.id_proof_last4)      AS masked_id_proof,
    COALESCE(veh.registration_no, 'Walk-In')              AS vehicle_reg_no,
    ps.zone_code                                          AS parking_zone_code,
    ps.parking_session_id,
    CONCAT(e.first_name, ' ', e.last_name)                AS host_name,
    e.emp_code                                            AS host_emp_code,
    d.dept_code,
    d.dept_name,
    CONCAT(d.building_name, ' - Floor ', d.floor_no)      AS destination,
    ckpt.checkpoint_code                                  AS entry_checkpoint_code,
    ckpt.checkpoint_name                                  AS entry_checkpoint_name,
    CONCAT(sg.first_name, ' ', sg.last_name, ' (', sg.badge_no, ')') AS admitted_by_guard,
    DATE_FORMAT(gp.check_in_time, '%Y-%m-%d %H:%i:%s')    AS check_in_time,
    DATE_FORMAT(gp.valid_until,   '%Y-%m-%d %H:%i:%s')    AS valid_until,
    TIMESTAMPDIFF(MINUTE, gp.check_in_time, NOW())        AS minutes_on_campus,
    TIMESTAMPDIFF(MINUTE, NOW(), gp.valid_until)          AS minutes_remaining,
    IF(NOW() > gp.valid_until OR gp.is_overstay = 1, 1, 0) AS is_overstaying,
    CASE
        WHEN NOW() > gp.valid_until OR gp.is_overstay = 1 THEN 'OVERSTAYING'
        WHEN TIMESTAMPDIFF(MINUTE, NOW(), gp.valid_until) <= 15 THEN 'EXPIRING_SOON'
        ELSE 'WITHIN_WINDOW'
    END                                                   AS occupancy_alert
FROM gate_passes gp
JOIN visitors v           ON v.visitor_id           = gp.visitor_id
JOIN visitor_categories vc ON vc.category_id         = gp.category_id
JOIN id_proof_types ipt   ON ipt.id_proof_type_id   = v.id_proof_type_id
JOIN employees e          ON e.emp_id               = gp.host_emp_id
JOIN departments d        ON d.dept_id              = e.dept_id
JOIN checkpoints ckpt     ON ckpt.checkpoint_id     = gp.check_in_checkpoint_id
JOIN security_guards sg   ON sg.guard_id            = gp.check_in_guard_id
LEFT JOIN vehicles veh    ON veh.vehicle_id         = gp.vehicle_id
LEFT JOIN (
    SELECT s.pass_id, s.session_id AS parking_session_id, z.zone_code
      FROM parking_sessions s
      JOIN parking_zones z ON z.zone_id = s.zone_id
     WHERE s.exit_time IS NULL
) ps ON ps.pass_id = gp.pass_id
WHERE gp.status = 'ACTIVE_ON_CAMPUS'
ORDER BY is_overstaying DESC, gp.check_in_time ASC;

-- 6.2 Department Visit Analytics View
CREATE OR REPLACE VIEW vw_department_visit_analytics AS
WITH dept_metrics AS (
    SELECT
        d.dept_id,
        d.dept_code,
        d.dept_name,
        d.building_name,
        d.floor_no,
        COUNT(gp.pass_id)                                              AS total_passes,
        SUM(CASE WHEN gp.status = 'ACTIVE_ON_CAMPUS' THEN 1 ELSE 0 END) AS active_now,
        SUM(CASE WHEN gp.status = 'COMPLETED'        THEN 1 ELSE 0 END) AS completed_visits,
        SUM(CASE WHEN gp.is_overstay = 1             THEN 1 ELSE 0 END) AS overstay_incidents,
        ROUND(AVG(gp.visit_duration_min), 1)                           AS avg_duration_min
    FROM departments d
    LEFT JOIN employees e    ON e.dept_id      = d.dept_id
    LEFT JOIN gate_passes gp ON gp.host_emp_id = e.emp_id
    GROUP BY d.dept_id, d.dept_code, d.dept_name, d.building_name, d.floor_no
),
hourly_dept AS (
    SELECT
        e.dept_id,
        HOUR(COALESCE(gp.check_in_time, gp.valid_from)) AS arrival_hour,
        COUNT(*)                                        AS hour_visits,
        ROW_NUMBER() OVER (
            PARTITION BY e.dept_id
            ORDER BY COUNT(*) DESC, HOUR(COALESCE(gp.check_in_time, gp.valid_from)) ASC
        ) AS rn
    FROM gate_passes gp
    JOIN employees e ON e.emp_id = gp.host_emp_id
    WHERE gp.status IN ('ACTIVE_ON_CAMPUS', 'COMPLETED')
    GROUP BY e.dept_id, HOUR(COALESCE(gp.check_in_time, gp.valid_from))
)
SELECT
    dm.dept_id,
    dm.dept_code,
    dm.dept_name,
    dm.building_name,
    dm.floor_no,
    dm.total_passes,
    dm.active_now,
    dm.completed_visits,
    dm.overstay_incidents,
    COALESCE(dm.avg_duration_min, 0.0)                                 AS avg_duration_min,
    RANK()       OVER (ORDER BY dm.total_passes DESC)                  AS visit_rank,
    DENSE_RANK() OVER (ORDER BY dm.total_passes DESC)                  AS visit_dense_rank,
    ROUND(
        100.0 * dm.total_passes / NULLIF(SUM(dm.total_passes) OVER (), 0),
        2
    )                                                                  AS pct_of_campus_traffic,
    SUM(dm.total_passes) OVER (
        ORDER BY dm.total_passes DESC, dm.dept_code ASC
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    )                                                                  AS cumulative_passes,
    CASE
        WHEN hd.arrival_hour IS NULL THEN 'N/A'
        ELSE CONCAT(LPAD(hd.arrival_hour, 2, '0'), ':00 - ', LPAD(hd.arrival_hour, 2, '0'), ':59 (', hd.hour_visits, ' visits)')
    END                                                                AS peak_arrival_window
FROM dept_metrics dm
LEFT JOIN hourly_dept hd ON hd.dept_id = dm.dept_id AND hd.rn = 1
ORDER BY visit_rank ASC, dm.dept_code ASC;

-- 6.3 Daily Visit Trend View
CREATE OR REPLACE VIEW vw_daily_visit_trend AS
WITH daily AS (
    SELECT
        DATE(COALESCE(check_in_time, valid_from)) AS visit_date,
        COUNT(*)                                  AS daily_passes,
        SUM(status = 'COMPLETED')                 AS completed_count,
        SUM(is_overstay = 1)                      AS overstay_count
    FROM gate_passes
    GROUP BY DATE(COALESCE(check_in_time, valid_from))
)
SELECT
    DATE_FORMAT(visit_date, '%Y-%m-%d')                                AS visit_date,
    daily_passes,
    completed_count,
    overstay_count,
    SUM(daily_passes) OVER (
        ORDER BY visit_date ASC
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    )                                                                  AS running_total_passes,
    ROUND(AVG(daily_passes) OVER (
        ORDER BY visit_date ASC
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ), 1)                                                              AS moving_avg_7d
FROM daily
ORDER BY visit_date DESC;

-- 6.4 Pass Audit Trail View
CREATE OR REPLACE VIEW vw_pass_audit_trail AS
SELECT
    al.log_id,
    DATE_FORMAT(al.event_at, '%Y-%m-%d %H:%i:%s.%f') AS event_at,
    al.event_type,
    COALESCE(gp.pass_code, al.attempted_code, '-')   AS pass_code,
    COALESCE(al.from_status, '-')                    AS from_status,
    COALESCE(al.to_status, '-')                      AS to_status,
    COALESCE(CONCAT(v.first_name, ' ', v.last_name), '-') AS visitor_name,
    COALESCE(CONCAT(sg.first_name, ' ', sg.last_name, ' (', sg.badge_no, ')'), 'System / Trigger') AS actor_guard,
    COALESCE(ckpt.checkpoint_code, '-')              AS checkpoint_code,
    al.details
FROM access_audit_logs al
LEFT JOIN gate_passes gp     ON gp.pass_id          = al.pass_id
LEFT JOIN visitors v         ON v.visitor_id        = gp.visitor_id
LEFT JOIN security_guards sg ON sg.guard_id         = al.guard_id
LEFT JOIN checkpoints ckpt   ON ckpt.checkpoint_id  = al.checkpoint_id
ORDER BY al.log_id DESC
LIMIT 250;

-- 6.5 Gate Pass Directory View
CREATE OR REPLACE VIEW vw_pass_directory AS
SELECT
    gp.pass_id,
    gp.pass_code,
    BIN_TO_UUID(gp.pass_token, 1)                    AS pass_uuid,
    gp.status,
    gp.visitor_id,
    CONCAT(v.first_name, ' ', v.last_name)           AS visitor_name,
    COALESCE(v.company_name, 'Independent')          AS visitor_company,
    vc.category_code,
    vc.category_name,
    CONCAT(e.first_name, ' ', e.last_name)           AS host_name,
    d.dept_code,
    d.dept_name,
    COALESCE(veh.registration_no, '-')               AS vehicle_reg_no,
    gp.visit_purpose,
    DATE_FORMAT(gp.valid_from,     '%Y-%m-%d %H:%i') AS valid_from,
    DATE_FORMAT(gp.valid_until,    '%Y-%m-%d %H:%i') AS valid_until,
    DATE_FORMAT(gp.check_in_time,  '%Y-%m-%d %H:%i') AS check_in_time,
    DATE_FORMAT(gp.check_out_time, '%Y-%m-%d %H:%i') AS check_out_time,
    gp.visit_duration_min,
    gp.is_overstay,
    gp.revoke_reason,
    COALESCE(CONCAT(appr.first_name, ' ', appr.last_name), '-') AS approved_by,
    DATE_FORMAT(gp.approved_at,    '%Y-%m-%d %H:%i') AS approved_at
FROM gate_passes gp
JOIN visitors v            ON v.visitor_id            = gp.visitor_id
JOIN visitor_categories vc ON vc.category_id          = gp.category_id
JOIN employees e           ON e.emp_id                = gp.host_emp_id
JOIN departments d         ON d.dept_id               = e.dept_id
LEFT JOIN employees appr   ON appr.emp_id             = gp.approved_by_emp_id
LEFT JOIN vehicles veh     ON veh.vehicle_id          = gp.vehicle_id
ORDER BY gp.pass_id DESC
LIMIT 200;

-- 6.6 Pending Approvals View (Allows host/guard to review requests requiring host consent)
CREATE OR REPLACE VIEW vw_pending_approvals AS
SELECT
    gp.pass_id,
    gp.pass_code,
    gp.visitor_id,
    CONCAT(v.first_name, ' ', v.last_name)           AS visitor_name,
    v.phone                                          AS visitor_phone,
    COALESCE(v.company_name, 'Independent')          AS visitor_company,
    CONCAT(ipt.type_code, ' ***-', v.id_proof_last4) AS masked_id_proof,
    vc.category_id,
    vc.category_code,
    vc.category_name,
    gp.host_emp_id,
    CONCAT(e.first_name, ' ', e.last_name)           AS host_name,
    d.dept_name,
    COALESCE(veh.registration_no, 'Walk-In')         AS vehicle_reg_no,
    gp.visit_purpose,
    DATE_FORMAT(gp.valid_from,  '%Y-%m-%d %H:%i')    AS valid_from,
    DATE_FORMAT(gp.valid_until, '%Y-%m-%d %H:%i')    AS valid_until,
    DATE_FORMAT(gp.created_at,  '%Y-%m-%d %H:%i')    AS requested_at,
    (
        SELECT COUNT(*) > 0 FROM employees ex
         WHERE ex.id_proof_hash = v.id_proof_hash
           AND ex.is_active = 0
           AND ex.exit_type IS NOT NULL
    )                                                AS is_ex_employee,
    (
        SELECT MAX(ex.exit_type) FROM employees ex
         WHERE ex.id_proof_hash = v.id_proof_hash
           AND ex.is_active = 0
    )                                                AS ex_employee_exit_type
FROM gate_passes gp
JOIN visitors v            ON v.visitor_id            = gp.visitor_id
JOIN visitor_categories vc ON vc.category_id          = gp.category_id
JOIN id_proof_types ipt    ON ipt.id_proof_type_id    = v.id_proof_type_id
JOIN employees e           ON e.emp_id                = gp.host_emp_id
JOIN departments d         ON d.dept_id               = e.dept_id
LEFT JOIN vehicles veh     ON veh.vehicle_id          = gp.vehicle_id
WHERE gp.status = 'PENDING_APPROVAL'
ORDER BY gp.created_at ASC;

-- 6.7 Live Parking Occupancy View
CREATE OR REPLACE VIEW vw_live_parking_occupancy AS
SELECT
    ps.session_id,
    gp.pass_code,
    CONCAT(v.first_name, ' ', v.last_name)            AS visitor_name,
    veh.registration_no,
    veh.vehicle_type,
    veh.make_model,
    pz.zone_id,
    pz.zone_code,
    pz.zone_name,
    ps.allocated_minutes,
    DATE_FORMAT(ps.entry_time, '%Y-%m-%d %H:%i:%s')   AS parked_at,
    TIMESTAMPDIFF(MINUTE, ps.entry_time, NOW())       AS minutes_parked,
    GREATEST(0, ps.allocated_minutes - TIMESTAMPDIFF(MINUTE, ps.entry_time, NOW())) AS minutes_remaining,
    IF(TIMESTAMPDIFF(MINUTE, ps.entry_time, NOW()) > ps.allocated_minutes OR ps.is_overstay = 1, 1, 0) AS is_overstay,
    CASE
        WHEN TIMESTAMPDIFF(MINUTE, ps.entry_time, NOW()) > ps.allocated_minutes OR ps.is_overstay = 1 THEN 'PARKING_OVERSTAY'
        WHEN (ps.allocated_minutes - TIMESTAMPDIFF(MINUTE, ps.entry_time, NOW())) <= 15 THEN 'EXPIRING_SOON'
        ELSE 'NORMAL'
    END                                               AS parking_alert
FROM parking_sessions ps
JOIN gate_passes gp    ON gp.pass_id    = ps.pass_id
JOIN visitors v        ON v.visitor_id  = gp.visitor_id
JOIN vehicles veh      ON veh.vehicle_id = ps.vehicle_id
JOIN parking_zones pz  ON pz.zone_id    = ps.zone_id
WHERE ps.exit_time IS NULL
ORDER BY is_overstay DESC, ps.entry_time ASC;

-- 6.8 UI Lookup Views
CREATE OR REPLACE VIEW vw_lookup_categories AS
SELECT
    category_id,
    category_code,
    category_name,
    max_pass_hours,
    parking_allowed,
    max_parking_minutes,
    requires_escort,
    requires_host_approval,
    DATE_FORMAT(allowed_from_time, '%H:%i') AS allowed_from,
    DATE_FORMAT(allowed_to_time,   '%H:%i') AS allowed_to
FROM visitor_categories
ORDER BY category_id ASC;

CREATE OR REPLACE VIEW vw_lookup_parking_zones AS
SELECT
    pz.zone_id,
    pz.zone_code,
    pz.zone_name,
    pz.capacity,
    pz.allowed_vehicle_types,
    COUNT(ps.session_id)                                AS occupied_slots,
    GREATEST(0, pz.capacity - COUNT(ps.session_id))     AS available_slots,
    ROUND(100.0 * COUNT(ps.session_id) / pz.capacity, 1) AS occupancy_pct
FROM parking_zones pz
LEFT JOIN parking_sessions ps ON ps.zone_id = pz.zone_id AND ps.exit_time IS NULL
WHERE pz.is_active = 1
GROUP BY pz.zone_id, pz.zone_code, pz.zone_name, pz.capacity, pz.allowed_vehicle_types
ORDER BY pz.zone_id ASC;

CREATE OR REPLACE VIEW vw_lookup_visitors AS
SELECT
    v.visitor_id,
    CONCAT(v.first_name, ' ', v.last_name)           AS full_name,
    v.phone,
    COALESCE(v.email, '-')                           AS email,
    COALESCE(v.company_name, 'Independent')          AS company_name,
    ipt.type_code                                    AS id_proof_type,
    CONCAT('***-', v.id_proof_last4)                 AS masked_id_proof,
    EXISTS (
        SELECT 1 FROM visitor_blacklist bl
         WHERE bl.visitor_id = v.visitor_id
           AND bl.lifted_at IS NULL
           AND bl.start_at <= NOW()
           AND (end_at IS NULL OR end_at > NOW())
    )                                                AS is_currently_blacklisted,
    EXISTS (
        SELECT 1 FROM employees ex
         WHERE ex.id_proof_hash = v.id_proof_hash
           AND ex.is_active = 0
           AND ex.exit_type IS NOT NULL
    )                                                AS is_ex_employee,
    (
        SELECT MAX(ex.exit_type) FROM employees ex
         WHERE ex.id_proof_hash = v.id_proof_hash
           AND ex.is_active = 0
    )                                                AS ex_employee_exit_type,
    (
        SELECT gp.pass_code FROM gate_passes gp
         WHERE gp.visitor_id = v.visitor_id
           AND gp.status IN ('PENDING_APPROVAL', 'APPROVED', 'ACTIVE_ON_CAMPUS')
         LIMIT 1
    )                                                AS current_active_pass
FROM visitors v
JOIN id_proof_types ipt ON ipt.id_proof_type_id = v.id_proof_type_id
ORDER BY v.visitor_id ASC;

CREATE OR REPLACE VIEW vw_lookup_employees AS
SELECT
    e.emp_id,
    e.emp_code,
    CONCAT(e.first_name, ' ', e.last_name) AS full_name,
    e.email,
    e.phone,
    d.dept_code,
    d.dept_name,
    e.is_active,
    e.exit_type
FROM employees e
JOIN departments d ON d.dept_id = e.dept_id
ORDER BY e.is_active DESC, e.emp_id ASC;

CREATE OR REPLACE VIEW vw_lookup_vehicles AS
SELECT
    veh.vehicle_id,
    veh.visitor_id,
    CONCAT(v.first_name, ' ', v.last_name) AS owner_name,
    veh.registration_no,
    veh.vehicle_type,
    veh.make_model
FROM vehicles veh
JOIN visitors v ON v.visitor_id = veh.visitor_id
ORDER BY veh.vehicle_id ASC;

CREATE OR REPLACE VIEW vw_lookup_guards AS
SELECT
    sg.guard_id,
    sg.badge_no,
    CONCAT(sg.first_name, ' ', sg.last_name) AS full_name,
    s.shift_code,
    s.shift_name,
    DATE_FORMAT(s.start_time, '%H:%i')       AS shift_start,
    DATE_FORMAT(s.end_time,   '%H:%i')       AS shift_end,
    sg.is_active
FROM security_guards sg
JOIN shifts s ON s.shift_id = sg.shift_id
ORDER BY sg.is_active DESC, sg.guard_id ASC;

CREATE OR REPLACE VIEW vw_lookup_checkpoints AS
SELECT
    checkpoint_id,
    checkpoint_code,
    checkpoint_name,
    building_name,
    is_active
FROM checkpoints
ORDER BY is_active DESC, checkpoint_id ASC;

CREATE OR REPLACE VIEW vw_lookup_id_proof_types AS
SELECT id_proof_type_id, type_code, type_label
FROM id_proof_types
ORDER BY id_proof_type_id ASC;

CREATE OR REPLACE VIEW vw_blacklist_status AS
SELECT
    bl.blacklist_id,
    bl.visitor_id,
    CONCAT(v.first_name, ' ', v.last_name)        AS visitor_name,
    v.phone                                       AS visitor_phone,
    bl.severity,
    bl.reason,
    DATE_FORMAT(bl.start_at,  '%Y-%m-%d %H:%i')   AS start_at,
    DATE_FORMAT(bl.end_at,    '%Y-%m-%d %H:%i')   AS end_at,
    DATE_FORMAT(bl.lifted_at, '%Y-%m-%d %H:%i')   AS lifted_at,
    bl.lifted_reason,
    CASE
        WHEN bl.lifted_at IS NOT NULL THEN 'LIFTED'
        WHEN bl.end_at IS NOT NULL AND bl.end_at <= NOW() THEN 'EXPIRED_WINDOW'
        WHEN bl.start_at > NOW() THEN 'SCHEDULED'
        ELSE 'ACTIVE_BLOCK'
    END                                           AS effective_state
FROM visitor_blacklist bl
JOIN visitors v ON v.visitor_id = bl.visitor_id
ORDER BY bl.blacklist_id DESC;


-- ============================================================================
-- SECTION 7: LEAST-PRIVILEGE APPLICATION USER (gp_app)
-- ============================================================================

DROP USER IF EXISTS 'gp_app'@'localhost';
DROP USER IF EXISTS 'gp_app'@'127.0.0.1';

CREATE USER 'gp_app'@'localhost' IDENTIFIED BY 'CvgpsApp_2026_Secure';
CREATE USER 'gp_app'@'127.0.0.1' IDENTIFIED BY 'CvgpsApp_2026_Secure';

-- Grant SELECT strictly on Views
GRANT SELECT ON cvgps_pro.vw_live_campus_occupancy      TO 'gp_app'@'localhost', 'gp_app'@'127.0.0.1';
GRANT SELECT ON cvgps_pro.vw_department_visit_analytics TO 'gp_app'@'localhost', 'gp_app'@'127.0.0.1';
GRANT SELECT ON cvgps_pro.vw_daily_visit_trend          TO 'gp_app'@'localhost', 'gp_app'@'127.0.0.1';
GRANT SELECT ON cvgps_pro.vw_pass_audit_trail           TO 'gp_app'@'localhost', 'gp_app'@'127.0.0.1';
GRANT SELECT ON cvgps_pro.vw_pass_directory             TO 'gp_app'@'localhost', 'gp_app'@'127.0.0.1';
GRANT SELECT ON cvgps_pro.vw_pending_approvals          TO 'gp_app'@'localhost', 'gp_app'@'127.0.0.1';
GRANT SELECT ON cvgps_pro.vw_live_parking_occupancy     TO 'gp_app'@'localhost', 'gp_app'@'127.0.0.1';
GRANT SELECT ON cvgps_pro.vw_lookup_categories          TO 'gp_app'@'localhost', 'gp_app'@'127.0.0.1';
GRANT SELECT ON cvgps_pro.vw_lookup_parking_zones       TO 'gp_app'@'localhost', 'gp_app'@'127.0.0.1';
GRANT SELECT ON cvgps_pro.vw_lookup_visitors            TO 'gp_app'@'localhost', 'gp_app'@'127.0.0.1';
GRANT SELECT ON cvgps_pro.vw_lookup_employees           TO 'gp_app'@'localhost', 'gp_app'@'127.0.0.1';
GRANT SELECT ON cvgps_pro.vw_lookup_vehicles            TO 'gp_app'@'localhost', 'gp_app'@'127.0.0.1';
GRANT SELECT ON cvgps_pro.vw_lookup_guards              TO 'gp_app'@'localhost', 'gp_app'@'127.0.0.1';
GRANT SELECT ON cvgps_pro.vw_lookup_checkpoints         TO 'gp_app'@'localhost', 'gp_app'@'127.0.0.1';
GRANT SELECT ON cvgps_pro.vw_lookup_id_proof_types      TO 'gp_app'@'localhost', 'gp_app'@'127.0.0.1';
GRANT SELECT ON cvgps_pro.vw_blacklist_status           TO 'gp_app'@'localhost', 'gp_app'@'127.0.0.1';

-- Grant EXECUTE strictly on application Stored Procedures
GRANT EXECUTE ON PROCEDURE cvgps_pro.sp_register_visitor      TO 'gp_app'@'localhost', 'gp_app'@'127.0.0.1';
GRANT EXECUTE ON PROCEDURE cvgps_pro.sp_issue_gate_pass       TO 'gp_app'@'localhost', 'gp_app'@'127.0.0.1';
GRANT EXECUTE ON PROCEDURE cvgps_pro.sp_approve_gate_pass     TO 'gp_app'@'localhost', 'gp_app'@'127.0.0.1';
GRANT EXECUTE ON PROCEDURE cvgps_pro.sp_process_gate_checkin  TO 'gp_app'@'localhost', 'gp_app'@'127.0.0.1';
GRANT EXECUTE ON PROCEDURE cvgps_pro.sp_process_gate_checkout TO 'gp_app'@'localhost', 'gp_app'@'127.0.0.1';
GRANT EXECUTE ON PROCEDURE cvgps_pro.sp_park_vehicle          TO 'gp_app'@'localhost', 'gp_app'@'127.0.0.1';
GRANT EXECUTE ON PROCEDURE cvgps_pro.sp_exit_parking          TO 'gp_app'@'localhost', 'gp_app'@'127.0.0.1';
GRANT EXECUTE ON PROCEDURE cvgps_pro.sp_revoke_gate_pass      TO 'gp_app'@'localhost', 'gp_app'@'127.0.0.1';
GRANT EXECUTE ON PROCEDURE cvgps_pro.sp_blacklist_visitor     TO 'gp_app'@'localhost', 'gp_app'@'127.0.0.1';
GRANT EXECUTE ON PROCEDURE cvgps_pro.sp_lift_blacklist        TO 'gp_app'@'localhost', 'gp_app'@'127.0.0.1';
GRANT EXECUTE ON PROCEDURE cvgps_pro.sp_expire_stale_passes   TO 'gp_app'@'localhost', 'gp_app'@'127.0.0.1';

FLUSH PRIVILEGES;
