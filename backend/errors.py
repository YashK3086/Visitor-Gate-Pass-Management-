"""
MySQL Error Translation Layer (backend/errors.py)
Maps custom SIGNAL SQLSTATE '45000' business rule errors (50001-50011) and
InnoDB constraint violations (3819 CHECK, 1062 UNIQUE, 1451/1452 FK, 1142/1370 Grants)
into structured JSON payloads for the frontend UI.
"""

from typing import Any, Dict, Tuple
import mysql.connector

CUSTOM_RULE_CATALOG: Dict[int, Tuple[str, str]] = {
    50001: ("BLACKLIST_BLOCK", "trg_prevent_blacklisted_visitor / sp_process_gate_checkin"),
    50002: ("SINGLE_ACTIVE_PASS_VIOLATION", "trg_enforce_single_active_pass"),
    50003: ("ENTITY_NOT_FOUND", "Stored Procedure Existence Check"),
    50004: ("PASS_NOT_YET_VALID", "sp_process_gate_checkin (valid_from > NOW())"),
    50005: ("PASS_EXPIRED", "sp_process_gate_checkin (NOW() > valid_until)"),
    50006: ("ILLEGAL_STATE_TRANSITION", "trg_enforce_state_machine / Gate Procedure"),
    50007: ("HOST_INACTIVE_OR_MISSING", "sp_issue_gate_pass"),
    50008: ("INVALID_TERMINAL_CONTEXT", "sp_process_gate_checkin / checkout"),
    50009: ("AUDIT_LOG_IMMUTABLE", "trg_audit_immutable_upd / trg_audit_immutable_del"),
    50010: ("INVALID_VALIDITY_WINDOW", "sp_issue_gate_pass"),
    50011: ("DUPLICATE_OR_INVALID_ID_PROOF", "sp_register_visitor"),
    50012: ("EX_EMPLOYEE_APPROVAL_REQUIRED", "sp_issue_gate_pass"),
    50013: ("EXCEEDS_CATEGORY_LIMIT", "sp_issue_gate_pass (visitor_categories.max_pass_hours)"),
    50014: ("PARKING_NOT_ALLOWED", "sp_issue_gate_pass / sp_park_vehicle"),
    50015: ("PASS_PENDING_APPROVAL", "sp_process_gate_checkin (host approval required)"),
    50016: ("CHECKPOINT_NOT_PERMITTED", "sp_process_gate_checkin (category_checkpoints)"),
    50017: ("TIME_WINDOW_VIOLATION", "sp_process_gate_checkin (category time windows)"),
    50018: ("ESCORT_REQUIRED", "sp_process_gate_checkin (visitor_categories.requires_escort)"),
    50019: ("PARKING_ZONE_FULL", "sp_park_vehicle (parking_zones.capacity)"),
    50020: ("VEHICLE_TYPE_NOT_ALLOWED", "sp_park_vehicle (parking_zones.allowed_vehicle_types)"),
    50021: ("VEHICLE_ALREADY_PARKED", "sp_park_vehicle / uk_active_vehicle_parking"),
}


def format_mysql_error(exc: Exception, executed_sql: str = "") -> Tuple[Dict[str, Any], int]:
    """Convert a mysql.connector.Error into a rich JSON response and HTTP status code."""
    if isinstance(exc, mysql.connector.Error):
        errno = int(exc.errno or 0)
        sqlstate = str(exc.sqlstate or "HY000")
        raw_msg = str(exc.msg or str(exc))

        if sqlstate == "45000" or errno in CUSTOM_RULE_CATALOG:
            rule_code, enforced_by = CUSTOM_RULE_CATALOG.get(
                errno, ("CUSTOM_BUSINESS_RULE", "MySQL Trigger / Stored Procedure")
            )
            return {
                "ok": False,
                "kind": "BUSINESS_RULE",
                "rule_code": rule_code,
                "enforced_by": enforced_by,
                "sqlstate": sqlstate,
                "errno": errno,
                "message": raw_msg,
                "sql": executed_sql,
            }, 409

        if errno == 3819:
            return {
                "ok": False,
                "kind": "CHECK_VIOLATION",
                "rule_code": "DOMAIN_CHECK_CONSTRAINT",
                "enforced_by": "MySQL InnoDB CHECK Constraint",
                "sqlstate": sqlstate,
                "errno": errno,
                "message": raw_msg,
                "sql": executed_sql,
            }, 422

        if errno == 1062:
            return {
                "ok": False,
                "kind": "DUPLICATE_KEY",
                "rule_code": "UNIQUE_INDEX_VIOLATION",
                "enforced_by": "MySQL InnoDB UNIQUE Index (uk_gp_active_visitor / uk_pass_code)",
                "sqlstate": sqlstate,
                "errno": errno,
                "message": raw_msg,
                "sql": executed_sql,
            }, 409

        if errno in (1451, 1452):
            return {
                "ok": False,
                "kind": "FK_VIOLATION",
                "rule_code": "REFERENTIAL_INTEGRITY_VIOLATION",
                "enforced_by": "MySQL InnoDB Foreign Key Constraint",
                "sqlstate": sqlstate,
                "errno": errno,
                "message": raw_msg,
                "sql": executed_sql,
            }, 409

        if errno in (1142, 1370):
            return {
                "ok": False,
                "kind": "PRIVILEGE_BLOCK",
                "rule_code": "LEAST_PRIVILEGE_ENFORCED",
                "enforced_by": "MySQL Grant System (gp_app user)",
                "sqlstate": sqlstate,
                "errno": errno,
                "message": raw_msg,
                "sql": executed_sql,
            }, 403

        return {
            "ok": False,
            "kind": "DATABASE_ERROR",
            "rule_code": "MYSQL_ENGINE_ERROR",
            "enforced_by": "MySQL Server",
            "sqlstate": sqlstate,
            "errno": errno,
            "message": raw_msg,
            "sql": executed_sql,
        }, 500

    return {
        "ok": False,
        "kind": "SERVER_ERROR",
        "rule_code": "UNEXPECTED_EXCEPTION",
        "enforced_by": "Python Connector Layer",
        "sqlstate": "HY000",
        "errno": -1,
        "message": str(exc),
        "sql": executed_sql,
    }, 500

