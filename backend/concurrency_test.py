"""
Multi-Threaded Pessimistic Locking Verification Script (backend/concurrency_test.py)
Demonstrates that `SELECT ... FOR UPDATE` inside `sp_process_gate_checkin`
serializes 10 simultaneous check-in requests for the same pass code:
  - Exactly 1 thread wins and transitions the pass to ACTIVE_ON_CAMPUS.
  - All other 9 threads wait on the InnoDB row lock, observe the new state after
    commit, and fail cleanly with SQLSTATE 45000 / Errno 50006 (ILLEGAL_STATE_TRANSITION).
"""

from concurrent.futures import ThreadPoolExecutor, as_completed
import threading
import time
from typing import Any, Dict

from db import call_procedure
from errors import format_mysql_error


def run_concurrency_test(num_threads: int = 10) -> Dict[str, Any]:
    print("=" * 78)
    print(f"CVGPS Concurrency & Pessimistic Locking Test ({num_threads} parallel threads)")
    print("=" * 78)

    # 1. Register a fresh visitor for the concurrency test so it is always repeatable
    suffix = str(int(time.time()) % 100000).zfill(5)
    reg_res, _ = call_procedure(
        "sp_register_visitor",
        (
            "Concurrent",
            f"Tester{suffix}",
            f"+9194000{suffix}",
            f"race.{suffix}@test.io",
            "Concurrency Lab",
            2,
            f"RACE{suffix}99",
            None,
            None,
            None,
        ),
    )
    visitor_id = int(reg_res["visitor_id"])

    # 2. Issue a fresh APPROVED gate pass (Category 1: MEETING_GUEST)
    issue_res, _ = call_procedure(
        "sp_issue_gate_pass",
        (visitor_id, 1, None, None, 2, "Pessimistic FOR UPDATE race condition test", 1, None),
    )
    pass_code = issue_res["pass_code"]
    print(f"[Setup] Issued fresh pass {pass_code} for Visitor #{visitor_id} (status = APPROVED)")

    barrier = threading.Barrier(num_threads)

    def worker(thread_idx: int) -> Dict[str, Any]:
        # Synchronize all threads so they hit CALL sp_process_gate_checkin at the exact same instant
        barrier.wait()
        t0 = time.perf_counter()
        try:
            res, _ = call_procedure("sp_process_gate_checkin", (pass_code, 1, 1))
            elapsed_ms = round((time.perf_counter() - t0) * 1000, 2)
            return {
                "thread": thread_idx,
                "outcome": "WIN (CHECKED_IN)",
                "errno": 0,
                "sqlstate": "00000",
                "elapsed_ms": elapsed_ms,
                "detail": res.get("message", ""),
            }
        except Exception as exc:
            err_payload, _ = format_mysql_error(exc)
            elapsed_ms = round((time.perf_counter() - t0) * 1000, 2)
            return {
                "thread": thread_idx,
                "outcome": "REJECTED_AFTER_LOCK",
                "errno": err_payload["errno"],
                "sqlstate": err_payload["sqlstate"],
                "elapsed_ms": elapsed_ms,
                "detail": err_payload["message"],
            }

    results = []
    with ThreadPoolExecutor(max_workers=num_threads) as pool:
        futures = [pool.submit(worker, i + 1) for i in range(num_threads)]
        for fut in as_completed(futures):
            results.append(fut.result())

    results.sort(key=lambda r: r["thread"])
    winners = [r for r in results if r["errno"] == 0]
    losers_50006 = [r for r in results if r["errno"] == 50006]

    print("-" * 78)
    for r in results:
        print(
            f"Thread #{r['thread']:02d} | {r['outcome']:20s} | "
            f"Errno {r['errno']:5d} [{r['sqlstate']}] | {r['elapsed_ms']:6.2f} ms | {r['detail'][:55]}"
        )
    print("-" * 78)
    print(f"Summary: {len(winners)} WINNER (Errno 0), {len(losers_50006)} SERIALIZED REJECTIONS (Errno 50006)")

    # Clean up the test pass by checking it out so it doesn't clutter live occupancy
    call_procedure("sp_process_gate_checkout", (pass_code, 1, 1))
    print(f"[Cleanup] Checked out test pass {pass_code} -> COMPLETED.")

    assert len(winners) == 1, f"Expected exactly 1 winner, got {len(winners)}"
    assert len(losers_50006) == num_threads - 1, f"Expected {num_threads - 1} 50006 rejections"
    print("VERDICT: PASS — Pessimistic row-level locking (SELECT ... FOR UPDATE) verified!")
    print("=" * 78)
    return {"pass_code": pass_code, "winners": len(winners), "losers": len(losers_50006)}


if __name__ == "__main__":
    run_concurrency_test(10)

