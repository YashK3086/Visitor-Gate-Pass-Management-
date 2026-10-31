-- ============================================================================
-- Corporate Visitor Gate Pass System (CVGPS) — Two-Session Concurrency Demo
-- File: database/05_concurrency_demo.sql
-- Purpose: Step-by-step interactive walkthrough for two MySQL Workbench / CLI
--          sessions demonstrating pessimistic row-level locking (SELECT ... FOR UPDATE)
--          inside sp_process_gate_checkin and the generated-column unique index.
-- ============================================================================

-- ============================================================================
-- PART A: PESSIMISTIC ROW-LEVEL LOCKING AT THE GATE TERMINAL
-- Scenario: Two security guards at adjacent lanes scan 'GP-DEMO01' simultaneously.
-- ============================================================================

-- [SESSION 1] Step 1: Begin transaction and acquire exclusive X-lock on GP-DEMO01
USE cvgps_pro;
START TRANSACTION;
SELECT pass_id, pass_code, status, valid_from, valid_until
  FROM gate_passes
 WHERE pass_code = 'GP-DEMO01'
   FOR UPDATE;
-- Session 1 now holds an InnoDB X record lock on uk_pass_code ('GP-DEMO01') and clustered PK.

-- [SESSION 2] Step 2 (run while Session 1 is still uncommitted):
-- Attempt to check in the exact same pass from a second terminal:
USE cvgps_pro;
CALL sp_process_gate_checkin('GP-DEMO01', 2, 1);
-- OBSERVE: Session 2 BLOCKS on `SELECT ... WHERE pass_code = 'GP-DEMO01' FOR UPDATE`
-- waiting for Session 1 to release the row lock.

-- [SESSION 3 / Inspector] Optional: Inspect the live lock wait in performance_schema:
SELECT
    r.trx_id                AS waiting_trx_id,
    r.trx_mysql_thread_id   AS waiting_thread,
    r.trx_query             AS waiting_query,
    b.trx_id                AS blocking_trx_id,
    b.trx_mysql_thread_id   AS blocking_thread
FROM performance_schema.data_lock_waits w
JOIN information_schema.innodb_trx b ON b.trx_id = w.blocking_engine_transaction_id
JOIN information_schema.innodb_trx r ON r.trx_id = w.requesting_engine_transaction_id;

-- [SESSION 1] Step 3: Complete check-in and COMMIT
UPDATE gate_passes
   SET status = 'ACTIVE_ON_CAMPUS',
       check_in_time = NOW(),
       check_in_guard_id = 1,
       check_in_checkpoint_id = 1
 WHERE pass_code = 'GP-DEMO01';
COMMIT;

-- [SESSION 2] Step 4: Immediately unblocks upon Session 1's COMMIT, reads the
-- newly committed status ('ACTIVE_ON_CAMPUS'), and aborts cleanly with:
-- ERROR 50006 (45000): ILLEGAL STATE TRANSITION: Pass GP-DEMO01 is currently ACTIVE_ON_CAMPUS
-- Plus a 'DENIED' entry is written to access_audit_logs!

