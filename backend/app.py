"""
Thin Flask API Server for CVGPS (backend/app.py)
Serves the minimalist single-page frontend and exposes thin REST endpoints
that delegate 100% of business logic, state transitions, and analytics to MySQL.
"""

import os
from pathlib import Path
from typing import Any, Dict

from flask import Flask, jsonify, request, send_from_directory

from db import call_procedure, execute_raw_security_probe, format_sql_preview, query_view
from errors import format_mysql_error

FRONTEND_DIR = Path(__file__).resolve().parent.parent / "frontend"

app = Flask(__name__, static_folder=str(FRONTEND_DIR), static_url_path="")


@app.route("/")
def serve_index():
    return send_from_directory(str(FRONTEND_DIR), "index.html")


@app.route("/api/health", methods=["GET"])
def api_health():
    try:
        rows, sql = query_view("vw_live_campus_occupancy")
        return jsonify({
            "ok": True,
            "db_user": os.getenv("DB_USER", "gp_app"),
            "database": os.getenv("DB_NAME", "cvgps_pro"),
            "active_on_campus": len(rows),
            "sql": sql,
        })
    except Exception as exc:
        payload, status = format_mysql_error(exc, "SELECT * FROM vw_live_campus_occupancy;")
        return jsonify(payload), status


@app.route("/api/lookups", methods=["GET"])
def api_lookups():
    """Fetch dropdown reference data from read-only lookup views."""
    try:
        visitors, _ = query_view("vw_lookup_visitors")
        employees, _ = query_view("vw_lookup_employees")
        vehicles, _ = query_view("vw_lookup_vehicles")
        guards, _ = query_view("vw_lookup_guards")
        checkpoints, _ = query_view("vw_lookup_checkpoints")
        id_types, _ = query_view("vw_lookup_id_proof_types")
        blacklist, _ = query_view("vw_blacklist_status")
        categories, _ = query_view("vw_lookup_categories")
        parking_zones, _ = query_view("vw_lookup_parking_zones")
        return jsonify({
            "ok": True,
            "visitors": visitors,
            "employees": employees,
            "vehicles": vehicles,
            "guards": guards,
            "checkpoints": checkpoints,
            "id_proof_types": id_types,
            "blacklist": blacklist,
            "categories": categories,
            "parking_zones": parking_zones,
            "sql": "SELECT * FROM vw_lookup_visitors, vw_lookup_employees, vw_lookup_categories, vw_lookup_parking_zones;",
        })
    except Exception as exc:
        payload, status = format_mysql_error(exc, "SELECT * FROM vw_lookup_*;")
        return jsonify(payload), status


@app.route("/api/occupancy", methods=["GET"])
def api_occupancy():
    try:
        rows, sql = query_view("vw_live_campus_occupancy")
        return jsonify({"ok": True, "rows": rows, "count": len(rows), "sql": sql})
    except Exception as exc:
        payload, status = format_mysql_error(exc, "SELECT * FROM vw_live_campus_occupancy;")
        return jsonify(payload), status


@app.route("/api/parking", methods=["GET"])
def api_parking():
    """Fetch live parking sessions across zones."""
    try:
        rows, sql = query_view("vw_live_parking_occupancy")
        zones, _ = query_view("vw_lookup_parking_zones")
        return jsonify({"ok": True, "rows": rows, "zones": zones, "count": len(rows), "sql": sql})
    except Exception as exc:
        payload, status = format_mysql_error(exc, "SELECT * FROM vw_live_parking_occupancy;")
        return jsonify(payload), status


@app.route("/api/approvals", methods=["GET"])
def api_approvals():
    """Fetch passes waiting for host employee authorization."""
    try:
        rows, sql = query_view("vw_pending_approvals")
        return jsonify({"ok": True, "rows": rows, "count": len(rows), "sql": sql})
    except Exception as exc:
        payload, status = format_mysql_error(exc, "SELECT * FROM vw_pending_approvals;")
        return jsonify(payload), status


@app.route("/api/analytics", methods=["GET"])
def api_analytics():
    try:
        dept_rows, sql1 = query_view("vw_department_visit_analytics")
        daily_rows, sql2 = query_view("vw_daily_visit_trend")
        return jsonify({
            "ok": True,
            "departments": dept_rows,
            "daily_trend": daily_rows,
            "sql": f"{sql1} {sql2}",
        })
    except Exception as exc:
        payload, status = format_mysql_error(exc, "SELECT * FROM vw_department_visit_analytics;")
        return jsonify(payload), status


@app.route("/api/audit", methods=["GET"])
def api_audit():
    try:
        rows, sql = query_view("vw_pass_audit_trail", limit=150)
        return jsonify({"ok": True, "rows": rows, "count": len(rows), "sql": sql})
    except Exception as exc:
        payload, status = format_mysql_error(exc, "SELECT * FROM vw_pass_audit_trail;")
        return jsonify(payload), status


@app.route("/api/passes", methods=["GET"])
def api_passes_list():
    try:
        rows, sql = query_view("vw_pass_directory", limit=150)
        return jsonify({"ok": True, "rows": rows, "count": len(rows), "sql": sql})
    except Exception as exc:
        payload, status = format_mysql_error(exc, "SELECT * FROM vw_pass_directory;")
        return jsonify(payload), status


@app.route("/api/passes", methods=["POST"])
def api_issue_pass():
    """Invoke `sp_issue_gate_pass` directly in MySQL."""
    body: Dict[str, Any] = request.get_json(force=True, silent=True) or {}
    visitor_id = body.get("visitor_id")
    host_emp_id = body.get("host_emp_id")
    vehicle_id = body.get("vehicle_id") or None
    valid_from = body.get("valid_from") or None
    duration_hours = body.get("duration_hours", 4)
    visit_purpose = body.get("visit_purpose", "")
    category_id = body.get("category_id", 1)
    escort_emp_id = body.get("escort_emp_id") or None

    args = (
        int(visitor_id) if visitor_id not in (None, "") else None,
        int(host_emp_id) if host_emp_id not in (None, "") else None,
        int(vehicle_id) if vehicle_id not in (None, "", 0, "0") else None,
        valid_from,
        int(duration_hours) if duration_hours not in (None, "") else None,
        visit_purpose,
        int(category_id) if category_id not in (None, "") else 1,
        int(escort_emp_id) if escort_emp_id not in (None, "", 0, "0") else None,
    )
    sql_preview = format_sql_preview("sp_issue_gate_pass", args)
    try:
        result, sql = call_procedure("sp_issue_gate_pass", args)
        return jsonify({"ok": True, "result": result, "sql": sql}), 201
    except Exception as exc:
        payload, status = format_mysql_error(exc, sql_preview)
        return jsonify(payload), status


@app.route("/api/passes/approve", methods=["POST"])
def api_approve_pass():
    """Invoke `sp_approve_gate_pass` (Host approval or rejection)."""
    body: Dict[str, Any] = request.get_json(force=True, silent=True) or {}
    pass_code = body.get("pass_code", "")
    approver_emp_id = body.get("approver_emp_id", 1)
    decision = body.get("decision", "APPROVE")
    notes = body.get("notes", "Approved via Operations Console")

    args = (
        str(pass_code).strip(),
        int(approver_emp_id) if approver_emp_id not in (None, "") else 1,
        str(decision).strip().upper(),
        str(notes).strip(),
    )
    sql_preview = format_sql_preview("sp_approve_gate_pass", args)
    try:
        result, sql = call_procedure("sp_approve_gate_pass", args)
        return jsonify({"ok": True, "result": result, "sql": sql})
    except Exception as exc:
        payload, status = format_mysql_error(exc, sql_preview)
        return jsonify(payload), status


@app.route("/api/parking/park", methods=["POST"])
def api_parking_park():
    """Invoke `sp_park_vehicle`."""
    body: Dict[str, Any] = request.get_json(force=True, silent=True) or {}
    pass_code = body.get("pass_code", "")
    zone_id = body.get("zone_id", 1)
    guard_id = body.get("guard_id", 1)

    args = (
        str(pass_code).strip(),
        int(zone_id) if zone_id not in (None, "") else 1,
        int(guard_id) if guard_id not in (None, "") else 1,
    )
    sql_preview = format_sql_preview("sp_park_vehicle", args)
    try:
        result, sql = call_procedure("sp_park_vehicle", args)
        return jsonify({"ok": True, "result": result, "sql": sql})
    except Exception as exc:
        payload, status = format_mysql_error(exc, sql_preview)
        return jsonify(payload), status


@app.route("/api/parking/exit", methods=["POST"])
def api_parking_exit():
    """Invoke `sp_exit_parking`."""
    body: Dict[str, Any] = request.get_json(force=True, silent=True) or {}
    pass_code = body.get("pass_code", "")
    guard_id = body.get("guard_id", 1)

    args = (
        str(pass_code).strip(),
        int(guard_id) if guard_id not in (None, "") else 1,
    )
    sql_preview = format_sql_preview("sp_exit_parking", args)
    try:
        result, sql = call_procedure("sp_exit_parking", args)
        return jsonify({"ok": True, "result": result, "sql": sql})
    except Exception as exc:
        payload, status = format_mysql_error(exc, sql_preview)
        return jsonify(payload), status


@app.route("/api/gate/checkin", methods=["POST"])
def api_gate_checkin():
    """Invoke `sp_process_gate_checkin` (executes SELECT ... FOR UPDATE inside MySQL)."""
    body: Dict[str, Any] = request.get_json(force=True, silent=True) or {}
    pass_code = body.get("pass_code", "")
    guard_id = body.get("guard_id", 1)
    checkpoint_id = body.get("checkpoint_id", 1)

    args = (
        str(pass_code).strip(),
        int(guard_id) if guard_id not in (None, "") else None,
        int(checkpoint_id) if checkpoint_id not in (None, "") else None,
    )
    sql_preview = format_sql_preview("sp_process_gate_checkin", args)
    try:
        result, sql = call_procedure("sp_process_gate_checkin", args)
        return jsonify({"ok": True, "result": result, "sql": sql})
    except Exception as exc:
        payload, status = format_mysql_error(exc, sql_preview)
        return jsonify(payload), status


@app.route("/api/gate/checkout", methods=["POST"])
def api_gate_checkout():
    """Invoke `sp_process_gate_checkout` (calculates duration & flags overstays in MySQL)."""
    body: Dict[str, Any] = request.get_json(force=True, silent=True) or {}
    pass_code = body.get("pass_code", "")
    guard_id = body.get("guard_id", 1)
    checkpoint_id = body.get("checkpoint_id", 1)

    args = (
        str(pass_code).strip(),
        int(guard_id) if guard_id not in (None, "") else None,
        int(checkpoint_id) if checkpoint_id not in (None, "") else None,
    )
    sql_preview = format_sql_preview("sp_process_gate_checkout", args)
    try:
        result, sql = call_procedure("sp_process_gate_checkout", args)
        return jsonify({"ok": True, "result": result, "sql": sql})
    except Exception as exc:
        payload, status = format_mysql_error(exc, sql_preview)
        return jsonify(payload), status


@app.route("/api/passes/revoke", methods=["POST"])
def api_revoke_pass():
    """Invoke `sp_revoke_gate_pass`."""
    body: Dict[str, Any] = request.get_json(force=True, silent=True) or {}
    args = (
        str(body.get("pass_code", "")).strip(),
        int(body.get("guard_id", 1)),
        str(body.get("reason", "Revoked via Security Console")),
    )
    sql_preview = format_sql_preview("sp_revoke_gate_pass", args)
    try:
        result, sql = call_procedure("sp_revoke_gate_pass", args)
        return jsonify({"ok": True, "result": result, "sql": sql})
    except Exception as exc:
        payload, status = format_mysql_error(exc, sql_preview)
        return jsonify(payload), status


@app.route("/api/visitors", methods=["POST"])
def api_register_visitor():
    """Invoke `sp_register_visitor` (hashes ID proof inside MySQL)."""
    body: Dict[str, Any] = request.get_json(force=True, silent=True) or {}
    args = (
        body.get("first_name", ""),
        body.get("last_name", ""),
        body.get("phone", ""),
        body.get("email") or None,
        body.get("company_name") or None,
        int(body.get("id_proof_type_id", 1)),
        body.get("raw_id_number", ""),
        body.get("vehicle_reg_no") or None,
        body.get("vehicle_type") or None,
        body.get("vehicle_model") or None,
    )
    sql_preview = format_sql_preview("sp_register_visitor", args)
    try:
        result, sql = call_procedure("sp_register_visitor", args)
        return jsonify({"ok": True, "result": result, "sql": sql}), 201
    except Exception as exc:
        payload, status = format_mysql_error(exc, sql_preview)
        return jsonify(payload), status


@app.route("/api/blacklist", methods=["POST"])
def api_blacklist_visitor():
    """Invoke `sp_blacklist_visitor`."""
    body: Dict[str, Any] = request.get_json(force=True, silent=True) or {}
    dur = body.get("duration_hours")
    args = (
        int(body.get("visitor_id", 0)),
        body.get("reason", "Security policy violation"),
        body.get("severity", "HIGH"),
        int(dur) if dur not in (None, "", 0, "0") else None,
        int(body.get("guard_id", 1)),
    )
    sql_preview = format_sql_preview("sp_blacklist_visitor", args)
    try:
        result, sql = call_procedure("sp_blacklist_visitor", args)
        return jsonify({"ok": True, "result": result, "sql": sql}), 201
    except Exception as exc:
        payload, status = format_mysql_error(exc, sql_preview)
        return jsonify(payload), status


@app.route("/api/blacklist/lift", methods=["POST"])
def api_lift_blacklist():
    """Invoke `sp_lift_blacklist`."""
    body: Dict[str, Any] = request.get_json(force=True, silent=True) or {}
    args = (
        int(body.get("blacklist_id", 0)),
        body.get("lifted_reason", "Cleared by security administration"),
    )
    sql_preview = format_sql_preview("sp_lift_blacklist", args)
    try:
        result, sql = call_procedure("sp_lift_blacklist", args)
        return jsonify({"ok": True, "result": result, "sql": sql})
    except Exception as exc:
        payload, status = format_mysql_error(exc, sql_preview)
        return jsonify(payload), status


@app.route("/api/maintenance/expire-sweep", methods=["POST"])
def api_expire_sweep():
    """Manually trigger `sp_expire_stale_passes` (normally run every 1 min by evt_expire_stale_passes)."""
    sql_preview = "CALL sp_expire_stale_passes();"
    try:
        result, sql = call_procedure("sp_expire_stale_passes", ())
        return jsonify({"ok": True, "result": result, "sql": sql})
    except Exception as exc:
        payload, status = format_mysql_error(exc, sql_preview)
        return jsonify(payload), status


@app.route("/api/security-probe", methods=["POST"])
def api_security_probe():
    """
    Demonstrate least-privilege `gp_app` barriers directly from the UI
    (e.g., attempting direct SELECT on `sys_secrets` or `DELETE FROM access_audit_logs`).
    """
    body: Dict[str, Any] = request.get_json(force=True, silent=True) or {}
    probe_type = body.get("probe", "read_secrets")

    probes = {
        "read_secrets": "SELECT * FROM sys_secrets;",
        "direct_table_select": "SELECT * FROM gate_passes LIMIT 5;",
        "delete_audit": "DELETE FROM access_audit_logs WHERE log_id = 1;",
        "ungranted_proc": "CALL sp_generate_load(100);",
    }
    sql = probes.get(probe_type, probes["read_secrets"])
    try:
        rows, executed = execute_raw_security_probe(sql)
        return jsonify({"ok": True, "rows": rows, "sql": executed})
    except Exception as exc:
        payload, status = format_mysql_error(exc, sql)
        return jsonify(payload), status


if __name__ == "__main__":
    host = os.getenv("FLASK_HOST", "127.0.0.1")
    port = int(os.getenv("FLASK_PORT", "5000"))
    app.run(host=host, port=port, debug=False, threaded=True)

