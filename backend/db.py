"""
Thin MySQL Database Gateway (backend/db.py)
Connects strictly as the least-privilege user `gp_app`.
Contains ZERO business logic — only executes Stored Procedures (`CALL sp_*`)
and queries read-only Views (`SELECT * FROM vw_*`).
"""

import os
from datetime import date, datetime, time, timedelta
from decimal import Decimal
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Tuple

from dotenv import load_dotenv
import mysql.connector
from mysql.connector import pooling

load_dotenv(Path(__file__).resolve().parent / ".env")

_POOL: Optional[pooling.MySQLConnectionPool] = None

# Whitelist of read-only views exposed to the application
ALLOWED_VIEWS = {
    "vw_live_campus_occupancy",
    "vw_department_visit_analytics",
    "vw_daily_visit_trend",
    "vw_pass_audit_trail",
    "vw_pass_directory",
    "vw_pending_approvals",
    "vw_live_parking_occupancy",
    "vw_lookup_categories",
    "vw_lookup_parking_zones",
    "vw_lookup_visitors",
    "vw_lookup_employees",
    "vw_lookup_vehicles",
    "vw_lookup_guards",
    "vw_lookup_checkpoints",
    "vw_lookup_id_proof_types",
    "vw_blacklist_status",
}


def get_pool() -> pooling.MySQLConnectionPool:
    """Initialize or return the MySQL connection pool for `gp_app`."""
    global _POOL
    if _POOL is None:
        _POOL = pooling.MySQLConnectionPool(
            pool_name="cvgps_pool",
            pool_size=12,
            pool_reset_session=True,
            host=os.getenv("DB_HOST", "127.0.0.1"),
            port=int(os.getenv("DB_PORT", "3306")),
            database=os.getenv("DB_NAME", "cvgps_pro"),
            user=os.getenv("DB_USER", "gp_app"),
            password=os.getenv("DB_PASSWORD", "CvgpsApp_2026_Secure"),
            charset="utf8mb4",
            use_unicode=True,
            autocommit=True,
        )
    return _POOL


def _serialize_value(val: Any) -> Any:
    if isinstance(val, (datetime, date, time)):
        return val.isoformat(sep=" ") if isinstance(val, datetime) else val.isoformat()
    if isinstance(val, timedelta):
        return str(val)
    if isinstance(val, Decimal):
        return float(val)
    if isinstance(val, (bytes, bytearray)):
        try:
            return val.decode("utf-8")
        except UnicodeDecodeError:
            return val.hex().upper()
    return val


def _serialize_rows(rows: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    return [{k: _serialize_value(v) for k, v in row.items()} for row in rows]


def format_sql_preview(proc_name: str, args: Sequence[Any]) -> str:
    """Format a human-readable SQL CALL preview for the UI SQL inspector bar."""
    formatted_args: List[str] = []
    for a in args:
        if a is None:
            formatted_args.append("NULL")
        elif isinstance(a, (int, float)):
            formatted_args.append(str(a))
        else:
            escaped = str(a).replace("'", "''")
            formatted_args.append(f"'{escaped}'")
    return f"CALL {proc_name}({', '.join(formatted_args)});"


def call_procedure(proc_name: str, args: Sequence[Any] = ()) -> Tuple[Dict[str, Any], str]:
    """
    Invoke a MySQL Stored Procedure using parameterized `CALL proc_name(%s, ...)`
    and return the first result row + the formatted SQL string.
    """
    sql_preview = format_sql_preview(proc_name, args)
    placeholders = ", ".join(["%s"] * len(args))
    stmt = f"CALL {proc_name}({placeholders})"

    conn = get_pool().get_connection()
    try:
        cursor = conn.cursor(dictionary=True)
        try:
            cursor.execute(stmt, tuple(args))
            result_row: Dict[str, Any] = {}
            if cursor.with_rows:
                rows = _serialize_rows(cursor.fetchall())
                if rows:
                    result_row = rows[0]
            # Drain any remaining result sets produced by the stored procedure
            while cursor.nextset():
                if cursor.with_rows:
                     extra = _serialize_rows(cursor.fetchall())
                     if extra and not result_row:
                         result_row = extra[0]
            conn.commit()
            return result_row, sql_preview
        finally:
            cursor.close()
    finally:
        conn.close()


def query_view(view_name: str, limit: Optional[int] = None) -> Tuple[List[Dict[str, Any]], str]:
    """Query one of the whitelisted read-only database views."""
    if view_name not in ALLOWED_VIEWS:
        raise ValueError(f"View '{view_name}' is not in ALLOWED_VIEWS.")

    sql = f"SELECT * FROM {view_name}"
    if limit is not None and int(limit) > 0:
        sql += f" LIMIT {int(limit)}"
    sql_preview = sql + ";"

    conn = get_pool().get_connection()
    try:
        cursor = conn.cursor(dictionary=True)
        try:
            cursor.execute(sql)
            rows = _serialize_rows(cursor.fetchall())
            return rows, sql_preview
        finally:
            cursor.close()
    finally:
        conn.close()


def execute_raw_security_probe(sql: str) -> Tuple[List[Dict[str, Any]], str]:
    """
    Used solely by the UI 'Security & Constraint Torture-Test' buttons to prove
    that direct table tampering by `gp_app` or audit log mutation is blocked by MySQL.
    """
    conn = get_pool().get_connection()
    try:
        cursor = conn.cursor(dictionary=True)
        try:
            cursor.execute(sql)
            rows = _serialize_rows(cursor.fetchall()) if cursor.with_rows else []
            return rows, sql
        finally:
            cursor.close()
    finally:
        conn.close()

