-- ============================================================================
-- Corporate Visitor Gate Pass System (CVGPS) — Indexing & EXPLAIN ANALYZE Defense
-- File: database/03_indexing_and_explain.sql
-- Purpose: Populates 50,000 synthetic historical gate passes and executes
--          side-by-side EXPLAIN ANALYZE benchmarks comparing B-Tree composite
--          indexes against IGNORE INDEX full-table scans.
-- Note: After running this benchmark, re-run setup_db.ps1 to restore the clean
--       edge-case seed state for UI demonstrations.
-- ============================================================================

USE cvgps_pro;
SET NAMES utf8mb4;

SELECT 'Generating 50,000 synthetic gate pass rows for realistic B-Tree depth...' AS benchmark_step;
CALL sp_generate_load(50000);

SELECT
    (SELECT COUNT(*) FROM gate_passes)       AS total_gate_passes,
    (SELECT COUNT(*) FROM access_audit_logs) AS total_audit_logs;

-- ============================================================================
-- BENCHMARK 1: High-Traffic Security Gate Terminal Pass Lookup
-- Index Defended: uk_pass_code (UNIQUE B-Tree on pass_code)
-- ============================================================================
SELECT '=== BENCHMARK 1A: Gate Lookup WITH UNIQUE INDEX uk_pass_code (O(log N) const lookup) ===' AS query_plan;
EXPLAIN ANALYZE
SELECT pass_id, visitor_id, host_emp_id, status, valid_from, valid_until
FROM gate_passes
WHERE pass_code = 'GP-DEMO01';

SELECT '=== BENCHMARK 1B: Gate Lookup WITHOUT INDEX (Full Table Scan over ~50,000 rows) ===' AS query_plan;
EXPLAIN ANALYZE
SELECT pass_id, visitor_id, host_emp_id, status, valid_from, valid_until
FROM gate_passes IGNORE INDEX (uk_pass_code)
WHERE pass_code = 'GP-DEMO01';

-- ============================================================================
-- BENCHMARK 2: Live Campus Occupancy Filter + Chronological Sort
-- Index Defended: idx_gp_status_checkin (status, check_in_time)
-- ============================================================================
SELECT '=== BENCHMARK 2A: Live Campus Occupancy WITH COMPOSITE INDEX idx_gp_status_checkin ===' AS query_plan;
EXPLAIN ANALYZE
SELECT pass_id, pass_code, visitor_id, host_emp_id, check_in_time, valid_until
FROM gate_passes
WHERE status = 'ACTIVE_ON_CAMPUS'
  AND check_in_time >= NOW() - INTERVAL 1 DAY
ORDER BY check_in_time ASC;

SELECT '=== BENCHMARK 2B: Live Campus Occupancy WITHOUT INDEX (Table Scan + Filesort) ===' AS query_plan;
EXPLAIN ANALYZE
SELECT pass_id, pass_code, visitor_id, host_emp_id, check_in_time, valid_until
FROM gate_passes IGNORE INDEX (idx_gp_status_checkin, idx_gp_status_validuntil, uk_gp_active_visitor)
WHERE status = 'ACTIVE_ON_CAMPUS'
  AND check_in_time >= NOW() - INTERVAL 1 DAY
ORDER BY check_in_time ASC;

-- ============================================================================
-- BENCHMARK 3: Host Employee Schedule Lookup (Foreign Key + Range Scan)
-- Index Defended: idx_gp_host_validfrom (host_emp_id, valid_from)
-- ============================================================================
SELECT '=== BENCHMARK 3A: Host Schedule Lookup WITH COMPOSITE INDEX idx_gp_host_validfrom ===' AS query_plan;
EXPLAIN ANALYZE
SELECT pass_id, pass_code, visitor_id, status, valid_from, valid_until
FROM gate_passes
WHERE host_emp_id = 1
  AND valid_from >= NOW() - INTERVAL 14 DAY
ORDER BY valid_from DESC;

SELECT '=== BENCHMARK 3B: Host Schedule Lookup WITHOUT INDEX (Full Table Scan + Filesort) ===' AS query_plan;
EXPLAIN ANALYZE
SELECT pass_id, pass_code, visitor_id, status, valid_from, valid_until
FROM gate_passes IGNORE INDEX (idx_gp_host_validfrom)
WHERE host_emp_id = 1
  AND valid_from >= NOW() - INTERVAL 14 DAY
ORDER BY valid_from DESC;

-- ============================================================================
-- BENCHMARK 4: Scheduled Auto-Expiry Sweep (Event Scheduler Probe)
-- Index Defended: idx_gp_status_validuntil (status, valid_until)
-- ============================================================================
SELECT '=== BENCHMARK 4A: Stale Approved Pass Sweep WITH COMPOSITE INDEX idx_gp_status_validuntil ===' AS query_plan;
EXPLAIN ANALYZE
SELECT pass_id, pass_code, valid_until
FROM gate_passes
WHERE status = 'APPROVED'
  AND valid_until < NOW();

SELECT '=== BENCHMARK 4B: Stale Approved Pass Sweep WITHOUT INDEX ===' AS query_plan;
EXPLAIN ANALYZE
SELECT pass_id, pass_code, valid_until
FROM gate_passes IGNORE INDEX (idx_gp_status_validuntil, idx_gp_status_checkin, uk_gp_active_visitor)
WHERE status = 'APPROVED'
  AND valid_until < NOW();

-- ============================================================================
-- BENCHMARK 5: Per-Pass Audit Trail Retrieval
-- Index Defended: idx_audit_pass_time (pass_id, event_at)
-- ============================================================================
SELECT '=== BENCHMARK 5A: Pass Audit History WITH COMPOSITE INDEX idx_audit_pass_time ===' AS query_plan;
EXPLAIN ANALYZE
SELECT log_id, event_type, from_status, to_status, event_at, details
FROM access_audit_logs
WHERE pass_id = 1
ORDER BY event_at DESC;

SELECT '=== BENCHMARK 5B: Pass Audit History WITHOUT INDEX (Full Scan over ~50,000+ audit rows) ===' AS query_plan;
EXPLAIN ANALYZE
SELECT log_id, event_type, from_status, to_status, event_at, details
FROM access_audit_logs IGNORE INDEX (idx_audit_pass_time)
WHERE pass_id = 1
ORDER BY event_at DESC;

