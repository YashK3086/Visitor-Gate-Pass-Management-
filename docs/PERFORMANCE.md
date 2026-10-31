# Indexing Strategy & `EXPLAIN ANALYZE` Performance Defense

All benchmarks below were executed against **MySQL 8.0.39 (InnoDB)** on this workspace using [`database/03_indexing_and_explain.sql`](../database/03_indexing_and_explain.sql) after populating **50,037 `gate_passes` rows** and **50,099 `access_audit_logs` rows** via `CALL sp_generate_load(50000)`.

---

## 1. Executive Summary of Measured Speedups

| # | High-Traffic Query Pattern | B-Tree Index Defended | Access Type (With Index) | Measured Time (With Index) | Access Type (`IGNORE INDEX`) | Measured Time (Without Index) | Speedup Factor |
|---|---|---|---|---|---|---|---|
| **1** | Gate Terminal Pass Code Lookup | `uk_pass_code (pass_code)` | `const` (1 row fetched before execution) | **0.0004 ms** (`400e-6 ms`) | Full Table Scan (`50,037` rows) | **16.30 ms** | **40,750× faster** |
| **2** | Live Campus Occupancy Filter + Sort | `idx_gp_status_checkin (status, check_in_time)` | Index Range Scan (`4` rows, zero filesort) | **0.0215 ms** | Full Table Scan + Filesort (`50,037` rows) | **23.20 ms** | **1,079× faster** |
| **3** | Host Employee 14-Day Schedule Lookup | `idx_gp_host_validfrom (host_emp_id, valid_from)` | Reverse Index Range Scan (`281` rows) | **0.810 ms** | Full Table Scan + Filesort (`50,037` rows) | **24.60 ms** | **30.4× faster** |
| **4** | Scheduled Auto-Expiry Sweep (`evt_expire_stale_passes`) | `idx_gp_status_validuntil (status, valid_until)` | Index Range Scan (`1` row) | **0.0314 ms** | Full Table Scan (`50,037` rows) | **20.20 ms** | **643× faster** |
| **5** | Per-Pass Compliance Audit Trail | `idx_audit_pass_time (pass_id, event_at)` | Reverse Index Lookup (`1` row, zero filesort) | **0.0351 ms** | Full Table Scan + Filesort (`50,099` rows) | **21.00 ms** | **598× faster** |

---

## 2. Detailed `EXPLAIN ANALYZE` Plans & Architectural Defense

### Benchmark 1: Security Gate Terminal Lookup (`uk_pass_code`)
Every check-in (`sp_process_gate_checkin`) and check-out (`sp_process_gate_checkout`) locks the pass row via:
```sql
SELECT pass_id, visitor_id, host_emp_id, status, valid_from, valid_until
FROM gate_passes
WHERE pass_code = 'GP-DEMO01'
FOR UPDATE;
```

- **With `UNIQUE KEY uk_pass_code (pass_code)`:**
  ```text
  -> Rows fetched before execution  (cost=0..0 rows=1) (actual time=300e-6..400e-6 rows=1 loops=1)
  ```
  *Why this matters for concurrency:* InnoDB resolves the unique secondary index in $O(\log N)$ time and places a targeted **record lock on that single row** rather than locking every scanned row across the table.
- **Without Index (`IGNORE INDEX (uk_pass_code)`):**
  ```text
  -> Filter: (gate_passes.pass_code = 'GP-DEMO01')  (cost=5133 rows=1) (actual time=0.13..16.3 rows=1 loops=1)
      -> Table scan on gate_passes  (cost=5133 rows=50129) (actual time=0.128..13.3 rows=50037 loops=1)
  ```
  *Consequence of missing index:* Not only is the query **40,750× slower**, a `SELECT ... FOR UPDATE` without an index locks **every row in `gate_passes`**, completely serializing all gates across the campus!

---

### Benchmark 2: Live Campus Occupancy (`idx_gp_status_checkin`)
Composite index `(status, check_in_time)` satisfies both the equality predicate `status = 'ACTIVE_ON_CAMPUS'`, the range predicate on `check_in_time`, and the `ORDER BY check_in_time ASC` sort order in a single B-Tree traversal:

- **With `KEY idx_gp_status_checkin (status, check_in_time)`:**
  ```text
  -> Index range scan on gate_passes using idx_gp_status_checkin
     over (status = 'ACTIVE_ON_CAMPUS' AND '2026-10-29 22:43:02' <= check_in_time),
     with index condition: ((gate_passes.`status` = 'ACTIVE_ON_CAMPUS')
       and (gate_passes.check_in_time >= <cache>((now() - interval 1 day))))
     (cost=4.2 rows=4) (actual time=0.0142..0.0215 rows=4 loops=1)
  ```
- **Without Index:**
  ```text
  -> Sort: gate_passes.check_in_time  (cost=4298 rows=50129) (actual time=23.2..23.2 rows=4 loops=1)
      -> Filter: ((gate_passes.`status` = 'ACTIVE_ON_CAMPUS') and (gate_passes.check_in_time >= <cache>((now() - interval 1 day))))  (cost=4298 rows=50129) (actual time=0.0844..23.2 rows=4 loops=1)
          -> Table scan on gate_passes  (cost=4298 rows=50129) (actual time=0.0755..19.8 rows=50037 loops=1)
  ```

---

### Benchmark 3: Host Employee Schedule Lookup (`idx_gp_host_validfrom`)
Composite index `(host_emp_id, valid_from)` supports the foreign key join from `employees` AND range-scans `valid_from` in reverse index order (`(reverse)`), avoiding a `filesort`:

- **With `KEY idx_gp_host_validfrom (host_emp_id, valid_from)`:**
  ```text
  -> Index range scan on gate_passes using idx_gp_host_validfrom
     over (host_emp_id = 1 AND '2026-10-16 22:43:02' <= valid_from) (reverse),
     with index condition: ((gate_passes.host_emp_id = 1)
       and (gate_passes.valid_from >= <cache>((now() - interval 14 day))))
     (cost=127 rows=281) (actual time=0.388..0.81 rows=281 loops=1)
  ```
- **Without Index:**
  ```text
  -> Sort: gate_passes.valid_from DESC  (cost=4894 rows=50129) (actual time=24.6..24.6 rows=281 loops=1)
      -> Filter: ((gate_passes.host_emp_id = 1) and (gate_passes.valid_from >= <cache>((now() - interval 14 day))))  (cost=4894 rows=50129) (actual time=0.0281..24.5 rows=281 loops=1)
          -> Table scan on gate_passes  (cost=4894 rows=50129) (actual time=0.0258..21.8 rows=50037 loops=1)
  ```

---

### Benchmark 4: Scheduled Auto-Expiry Sweep (`idx_gp_status_validuntil`)
Because `evt_expire_stale_passes` runs every 60 seconds, it must never scan historical `COMPLETED` passes. The composite index `(status, valid_until)` narrows the sweep strictly to `(status = 'APPROVED' AND valid_until < NOW())`:

- **With `KEY idx_gp_status_validuntil (status, valid_until)`:**
  ```text
  -> Index range scan on gate_passes using idx_gp_status_validuntil
     over (status = 'APPROVED' AND valid_until < '2026-10-30 22:43:02'),
     with index condition: ((gate_passes.`status` = 'APPROVED') and (gate_passes.valid_until < <cache>(now())))
     (cost=0.71 rows=1) (actual time=0.0273..0.0314 rows=1 loops=1)
  ```
- **Without Index:**
  ```text
  -> Filter: ((gate_passes.`status` = 'APPROVED') and (gate_passes.valid_until < <cache>(now())))  (cost=4298 rows=4177) (actual time=0.0541..20.2 rows=1 loops=1)
      -> Table scan on gate_passes  (cost=4298 rows=50129) (actual time=0.048..16.6 rows=50037 loops=1)
  ```

---

### Benchmark 5: Per-Pass Audit Trail Lookup (`idx_audit_pass_time`)
- **With `KEY idx_audit_pass_time (pass_id, event_at)`:**
  ```text
  -> Index lookup on access_audit_logs using idx_audit_pass_time (pass_id=1) (reverse)
     (cost=0.35 rows=1) (actual time=0.0273..0.0351 rows=1 loops=1)
  ```
- **Without Index:**
  ```text
  -> Sort: access_audit_logs.event_at DESC  (cost=5122 rows=49700) (actual time=21..21 rows=1 loops=1)
      -> Filter: (access_audit_logs.pass_id = 1)  (cost=5122 rows=49700) (actual time=0.0952..21 rows=1 loops=1)
          -> Table scan on access_audit_logs  (cost=5122 rows=49700) (actual time=0.094..18.8 rows=50099 loops=1)
  ```

