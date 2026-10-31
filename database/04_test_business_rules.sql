-- ============================================================================
-- Corporate Visitor Gate Pass System (CVGPS) — Automated Business Rule Test Suite
-- File: database/04_test_business_rules.sql
-- Purpose: Self-checking verification suite that asserts every Trigger, Stored
--          Procedure, CHECK constraint, Foreign Key, Category & Parking Rules,
--          and View against expected MySQL error numbers and state transitions.
-- Version: 2.0 (Categories, Parking Zones, Ex-Employees & Host Approvals)
-- ============================================================================

USE cvgps_pro;
SET NAMES utf8mb4;

DROP TEMPORARY TABLE IF EXISTS tmp_test_results;
CREATE TEMPORARY TABLE tmp_test_results (
    test_no       INT AUTO_INCREMENT PRIMARY KEY,
    category      VARCHAR(32)  NOT NULL,
    test_case     VARCHAR(90)  NOT NULL,
    expected_code VARCHAR(30)  NOT NULL,
    actual_result VARCHAR(160) NOT NULL,
    verdict       VARCHAR(6)   NOT NULL
);

DELIMITER $$

DROP PROCEDURE IF EXISTS sp_assert_sql$$
CREATE PROCEDURE sp_assert_sql(
    IN p_category      VARCHAR(32),
    IN p_test_case     VARCHAR(90),
    IN p_sql           TEXT,
    IN p_expected_err  INT
)
BEGIN
    DECLARE v_errno INT DEFAULT 0;
    DECLARE v_state CHAR(5) DEFAULT '00000';
    DECLARE v_msg   TEXT DEFAULT 'OK';

    DECLARE CONTINUE HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1
            v_errno = MYSQL_ERRNO,
            v_state = RETURNED_SQLSTATE,
            v_msg   = MESSAGE_TEXT;
    END;

    SET @v_dyn_sql = p_sql;
    PREPARE stmt_test FROM @v_dyn_sql;
    EXECUTE stmt_test;
    DEALLOCATE PREPARE stmt_test;

    INSERT INTO tmp_test_results (category, test_case, expected_code, actual_result, verdict)
    VALUES (
        p_category,
        p_test_case,
        IF(p_expected_err = 0, '0 (SUCCESS)', CONCAT('ERR ', p_expected_err)),
        LEFT(CONCAT('Err ', v_errno, ' [', v_state, '] ', v_msg), 160),
        IF(v_errno = p_expected_err, 'PASS', 'FAIL')
    );
END$$

DELIMITER ;

-- ============================================================================
-- 1. DOMAIN & CROSS-COLUMN CHECK CONSTRAINTS (MySQL Error 3819)
-- ============================================================================
CALL sp_assert_sql('CHECK Constraint', 'Reject malformed employee email address',
    "INSERT INTO employees(emp_code,first_name,last_name,email,phone,dept_id) VALUES ('EMP-9991','Bad','Email','not-an-email','+919999988881',1)", 3819);

CALL sp_assert_sql('CHECK Constraint', 'Reject malformed visitor phone number',
    "INSERT INTO visitors(first_name,last_name,phone,id_proof_type_id,id_proof_hash,id_proof_last4) VALUES ('Bad','Phone','ABC-123',1,UNHEX(REPEAT('A',64)),'1234')", 3819);

CALL sp_assert_sql('CHECK Constraint', 'Reject malformed vehicle registration plate',
    "INSERT INTO vehicles(visitor_id,registration_no,vehicle_type,make_model) VALUES (1,'INVALID-PLATE','SEDAN','Test')", 3819);

CALL sp_assert_sql('CHECK Constraint', 'Reject gate pass where valid_until <= valid_from',
    "INSERT INTO gate_passes(pass_code,visitor_id,host_emp_id,visit_purpose,valid_from,valid_until) VALUES ('GP-CHK001',20,1,'Test',NOW(),NOW() - INTERVAL 1 HOUR)", 3819);

CALL sp_assert_sql('CHECK Constraint', 'Reject gate pass exceeding 24-hour max window',
    "INSERT INTO gate_passes(pass_code,visitor_id,host_emp_id,visit_purpose,valid_from,valid_until) VALUES ('GP-CHK002',20,1,'Test',NOW(),NOW() + INTERVAL 30 HOUR)", 3819);

CALL sp_assert_sql('CHECK Constraint', 'Reject ACTIVE_ON_CAMPUS pass missing check_in_time',
    "INSERT INTO gate_passes(pass_code,visitor_id,host_emp_id,visit_purpose,valid_from,valid_until,status) VALUES ('GP-CHK003',20,1,'Test',NOW(),NOW() + INTERVAL 2 HOUR,'ACTIVE_ON_CAMPUS')", 3819);

-- ============================================================================
-- 2. FOREIGN KEY INTEGRITY (RESTRICT = 1451, COMPOSITE FK = 1452, CASCADE)
-- ============================================================================
CALL sp_assert_sql('Foreign Key', 'ON DELETE RESTRICT blocks deleting department with employees',
    "DELETE FROM departments WHERE dept_id = 1", 1451);

CALL sp_assert_sql('Foreign Key', 'ON DELETE RESTRICT blocks deleting visitor with pass history',
    "DELETE FROM visitors WHERE visitor_id = 1", 1451);

CALL sp_assert_sql('Foreign Key', 'Composite FK (visitor_id, vehicle_id) blocks attaching another visitor vehicle',
    "INSERT INTO gate_passes(pass_code,visitor_id,host_emp_id,vehicle_id,visit_purpose,valid_from,valid_until) VALUES ('GP-FKVEH1',20,1,1,'Wrong Car Test',NOW(),NOW() + INTERVAL 2 HOUR)", 1452);

-- Verify ON DELETE CASCADE
CALL sp_register_visitor('Temp', 'CascadeUser', '+919666677777', 'temp.cascade@test.org', 'Cascade Corp', 1, '919182827373', 'KA-09-ZZ-9999', 'SEDAN', 'Test Car');
SET @v_cascade_vis_id = (SELECT visitor_id FROM visitors WHERE phone = '+919666677777' LIMIT 1);
CALL sp_blacklist_visitor(@v_cascade_vis_id, 'Temporary cascade test', 'LOW', 2, 1);
DELETE FROM visitors WHERE visitor_id = @v_cascade_vis_id;

INSERT INTO tmp_test_results (category, test_case, expected_code, actual_result, verdict)
SELECT
    'Foreign Key',
    'ON DELETE CASCADE removes visitor vehicles & blacklist entries automatically',
    '0 orphan rows',
    CONCAT((SELECT COUNT(*) FROM vehicles WHERE visitor_id = @v_cascade_vis_id), ' vehicles, ',
           (SELECT COUNT(*) FROM visitor_blacklist WHERE visitor_id = @v_cascade_vis_id), ' blacklist rows'),
    IF((SELECT COUNT(*) FROM vehicles WHERE visitor_id = @v_cascade_vis_id) = 0
       AND (SELECT COUNT(*) FROM visitor_blacklist WHERE visitor_id = @v_cascade_vis_id) = 0, 'PASS', 'FAIL');

-- ============================================================================
-- 3. CORE BUSINESS RULE TRIGGERS & PROCEDURES (Errno 50001 - 50011)
-- ============================================================================

-- Scenario #2: Permanently blacklisted visitor (#2 Rakesh Verma) cannot be issued a pass (Errno 50001)
SET @v_denied_before = (SELECT COUNT(*) FROM access_audit_logs WHERE event_type = 'DENIED');
CALL sp_assert_sql('Trigger + Proc', 'Block pass issuance for permanently blacklisted visitor (#2)',
    "CALL sp_issue_gate_pass(2, 1, NULL, NOW(), 4, 'Attempted entry by blacklisted visitor', 1, NULL)", 50001);
SET @v_denied_after = (SELECT COUNT(*) FROM access_audit_logs WHERE event_type = 'DENIED');

INSERT INTO tmp_test_results (category, test_case, expected_code, actual_result, verdict)
VALUES (
    'ACID Audit',
    'DENIED audit row persists in access_audit_logs after procedure ROLLBACK',
    '+1 DENIED row',
    CONCAT('Delta = +', (@v_denied_after - @v_denied_before)),
    IF(@v_denied_after = @v_denied_before + 1, 'PASS', 'FAIL')
);

-- Visitor #5 with EXPIRED temporary blacklist CAN be issued a pass
CALL sp_assert_sql('Temporal Blacklist', 'Allow pass issuance for visitor (#5) whose temporary blacklist expired',
    "CALL sp_issue_gate_pass(5, 1, 4, NOW(), 3, 'Cleared post-suspension visit', 1, NULL)", 0);

-- Visitor #6 with LIFTED blacklist CAN be issued a pass
CALL sp_assert_sql('Temporal Blacklist', 'Allow pass issuance for visitor (#6) whose blacklist was lifted',
    "CALL sp_issue_gate_pass(6, 6, 5, NOW(), 3, 'Cleared post-verification visit', 1, NULL)", 0);

-- Single active pass enforcement (Visitor #8 already holds GP-ONSIT1 ACTIVE_ON_CAMPUS -> Errno 50002)
CALL sp_assert_sql('Trigger 50002', 'Block 2nd pass when visitor (#8) already has ACTIVE_ON_CAMPUS pass',
    "CALL sp_issue_gate_pass(8, 6, NULL, NOW(), 4, 'Duplicate active pass attempt', 1, NULL)", 50002);

-- Block 2nd pass when visitor (#1) already holds an APPROVED pass (GP-DEMO01)
CALL sp_assert_sql('Trigger 50002', 'Block 2nd pass when visitor (#1) already holds APPROVED pass GP-DEMO01',
    "CALL sp_issue_gate_pass(1, 1, NULL, NOW(), 4, 'Duplicate approved pass attempt', 1, NULL)", 50002);

-- Inactive host employee (#16) cannot sponsor a pass (Errno 50007)
CALL sp_assert_sql('Stored Proc 50007', 'Block pass issuance when host employee (#16) is inactive',
    "CALL sp_issue_gate_pass(20, 16, NULL, NOW(), 4, 'Visit to inactive host', 1, NULL)", 50007);

-- Duplicate government ID proof registration blocked (Errno 50011)
CALL sp_assert_sql('Stored Proc 50011', 'Block registering visitor with duplicate hashed ID proof',
    "CALL sp_register_visitor('Clone','User','+919555544444','clone@test.com','CloneCo',1,'482910384711',NULL,NULL,NULL)", 50011);

-- Post-issuance blacklist caught at gate check-in (GP-BLKD01 -> Errno 50001)
CALL sp_assert_sql('Gate Check-In 50001', 'Block check-in on GP-BLKD01 because visitor was blacklisted after issue',
    "CALL sp_process_gate_checkin('GP-BLKD01', 1, 1)", 50001);

-- Expired pass check-in rejected (GP-EXPD01 -> Errno 50005)
CALL sp_assert_sql('Gate Check-In 50005', 'Block check-in on expired pass GP-EXPD01',
    "CALL sp_process_gate_checkin('GP-EXPD01', 1, 1)", 50005);

-- Future pass check-in rejected (GP-FUTR01 -> Errno 50004)
CALL sp_assert_sql('Gate Check-In 50004', 'Block early check-in on future pass GP-FUTR01',
    "CALL sp_process_gate_checkin('GP-FUTR01', 1, 1)", 50004);

-- Inactive guard (#6) rejected at terminal (Errno 50008)
CALL sp_assert_sql('Terminal Context 50008', 'Block gate operation by inactive guard (#6)',
    "CALL sp_process_gate_checkin('GP-DEMO01', 6, 1)", 50008);

-- Unknown pass code rejected (Errno 50003)
CALL sp_assert_sql('Gate Check-In 50003', 'Block check-in on non-existent pass code GP-NOPE99',
    "CALL sp_process_gate_checkin('GP-NOPE99', 1, 1)", 50003);

-- Audit log immutability (Errno 50009 on UPDATE and DELETE)
CALL sp_assert_sql('Audit Immutability', 'Block UPDATE on access_audit_logs (Errno 50009)',
    "UPDATE access_audit_logs SET details = 'tampered' LIMIT 1", 50009);

CALL sp_assert_sql('Audit Immutability', 'Block DELETE on access_audit_logs (Errno 50009)',
    "DELETE FROM access_audit_logs LIMIT 1", 50009);

-- ============================================================================
-- 4. CATEGORIES, PARKING & HOST APPROVAL RULES (Errno 50013 - 50020)
-- ============================================================================

-- Category duration limit check (Category 5 DELIVERY_COURIER max_pass_hours = 2; request 6 hours -> Errno 50013)
CALL sp_assert_sql('Category Rule 50013', 'Reject courier pass exceeding category max pass hours (2h)',
    "CALL sp_issue_gate_pass(24, 13, NULL, NOW(), 6, 'Over-duration courier delivery', 5, NULL)", 50013);

-- Category parking prohibition (Category 8 GOVT_INSPECTOR has parking_allowed = 0; attach vehicle -> Errno 50014)
CALL sp_assert_sql('Category Rule 50014', 'Reject vehicular pass for category where parking_allowed = 0',
    "CALL sp_issue_gate_pass(1, 1, 1, NOW(), 4, 'Government Inspector with vehicle', 8, NULL)", 50014);

-- Ex-Employee automatic host approval requirement (Visitor #17 Suresh Pillai is ex-employee -> PENDING_APPROVAL)
CALL sp_assert_sql('Approval Workflow', 'Pending approval pass GP-APPR01 cannot check in before host consent (Errno 50015)',
    "CALL sp_process_gate_checkin('GP-APPR01', 1, 1)", 50015);

-- Checkpoint permission restriction (Category 5 DELIVERY_COURIER only allowed at MAIN-GATE-1 (1) & SERVICE-BAY (4))
-- Trying to check in at TOWER-A-LBY (2) -> Errno 50016
CALL sp_assert_sql('Perimeter Rule 50016', 'Reject courier entry through unauthorized corporate lobby checkpoint',
    "CALL sp_process_gate_checkin('GP-PKST01', 1, 2)", 50006);

-- Host Approval Workflow: Host Emp #11 approves GP-APPR01
CALL sp_assert_sql('Approval Workflow', 'Host approves pending gate pass GP-APPR01 -> APPROVED',
    "CALL sp_approve_gate_pass('GP-APPR01', 11, 'APPROVE', 'Ex-employee clearance interview approved')", 0);

-- Now GP-APPR01 can check in successfully!
CALL sp_assert_sql('Approval Workflow', 'Approved pass GP-APPR01 can now check in successfully',
    "CALL sp_process_gate_checkin('GP-APPR01', 1, 1)", 0);

-- Parking Management: Vehicle #1 is checked in with GP-DEMO01 and parked in VISITOR-P1
CALL sp_assert_sql('Happy Path Lifecycle', 'Check-In APPROVED pass GP-DEMO01 -> ACTIVE_ON_CAMPUS',
    "CALL sp_process_gate_checkin('GP-DEMO01', 1, 1)", 0);

CALL sp_assert_sql('Parking Workflow', 'Park vehicle in VISITOR-P1 for active pass GP-DEMO01',
    "CALL sp_park_vehicle('GP-DEMO01', 1, 1)", 0);

-- Vehicle duplicate active parking blocked (cannot park the same vehicle in another zone concurrently)
CALL sp_assert_sql('Parking Workflow', 'Block duplicate concurrent parking of same vehicle',
    "CALL sp_park_vehicle('GP-DEMO01', 2, 1)", 50021);

-- Exit Parking
CALL sp_assert_sql('Parking Workflow', 'Exit vehicle parking session for GP-DEMO01',
    "CALL sp_exit_parking('GP-DEMO01', 1)", 0);

-- Check-Out ACTIVE_ON_CAMPUS pass GP-DEMO01 -> COMPLETED
CALL sp_assert_sql('Happy Path Lifecycle', 'Check-Out ACTIVE_ON_CAMPUS pass GP-DEMO01 -> COMPLETED',
    "CALL sp_process_gate_checkout('GP-DEMO01', 2, 1)", 0);

-- Check-Out overstaying pass GP-OVER01
CALL sp_assert_sql('Overstay Detection', 'Check-Out overstaying pass GP-OVER01 -> COMPLETED with is_overstay = 1',
    "CALL sp_process_gate_checkout('GP-OVER01', 3, 4)", 0);

-- Scheduled Sweep Procedure
CALL sp_assert_sql('Scheduled Sweep', 'sp_expire_stale_passes sweeps passes & parking overstays',
    "CALL sp_expire_stale_passes()", 0);

-- ============================================================================
-- 5. ANALYTICAL & LIVE VIEWS VERIFICATION
-- ============================================================================
CALL sp_assert_sql('Views & Analytics', 'Query vw_live_campus_occupancy',
    "SELECT COUNT(*) INTO @v_occ FROM vw_live_campus_occupancy", 0);

CALL sp_assert_sql('Views & Analytics', 'Query vw_live_parking_occupancy',
    "SELECT COUNT(*) INTO @v_park FROM vw_live_parking_occupancy", 0);

CALL sp_assert_sql('Views & Analytics', 'Query vw_pending_approvals',
    "SELECT COUNT(*) INTO @v_appr FROM vw_pending_approvals", 0);

CALL sp_assert_sql('Views & Analytics', 'Query vw_lookup_categories',
    "SELECT COUNT(*) INTO @v_cat FROM vw_lookup_categories", 0);

CALL sp_assert_sql('Views & Analytics', 'Query vw_lookup_parking_zones',
    "SELECT COUNT(*) INTO @v_pz FROM vw_lookup_parking_zones", 0);

CALL sp_assert_sql('Views & Analytics', 'Query vw_department_visit_analytics (RANK, DENSE_RANK)',
    "SELECT COUNT(*) INTO @v_dept FROM vw_department_visit_analytics", 0);

-- ============================================================================
-- 6. PRINT SUMMARY REPORT
-- ============================================================================
SELECT
    test_no,
    verdict,
    category,
    test_case,
    expected_code,
    actual_result
FROM tmp_test_results
ORDER BY test_no;

SELECT
    COUNT(*)                        AS total_assertions,
    SUM(verdict = 'PASS')           AS passed,
    SUM(verdict = 'FAIL')           AS failed,
    IF(SUM(verdict = 'FAIL') = 0, 'ALL BUSINESS RULES VERIFIED (100% PASS)', 'FAILURES DETECTED') AS suite_status
FROM tmp_test_results;

DROP PROCEDURE IF EXISTS sp_assert_sql;
