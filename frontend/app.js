/*
 * CVGPS Operations Console Frontend Driver v2.0 (frontend/app.js)
 * Zero client-side business validation — every operation invokes the Flask
 * thin gateway (`CALL sp_*` / `SELECT * FROM vw_*`) and renders database-level
 * outcomes, lifecycle states, or SQLSTATE '45000' signals directly.
 */

const state = {
  visitors: [],
  employees: [],
  vehicles: [],
  guards: [],
  checkpoints: [],
  categories: [],
  parkingZones: [],
  idProofTypes: [],
  blacklist: [],
  autoRefreshTimer: null,
};

function setLastSql(sql) {
  if (sql) {
    document.getElementById("last-sql-code").textContent = sql;
  }
}

function showSignalBanner(payload, isSuccess = false) {
  const banner = document.getElementById("signal-banner");
  const badge = document.getElementById("signal-badge");
  const title = document.getElementById("signal-title");
  const msg = document.getElementById("signal-message");
  const enforced = document.getElementById("signal-enforced-by");
  const sqlEl = document.getElementById("signal-sql");

  banner.classList.remove("hidden", "is-success");
  if (isSuccess) {
    banner.classList.add("is-success");
    badge.textContent = `SQLSTATE 00000 · ${payload.status_code || "OK"}`;
    title.textContent = "ACID Transaction Committed";
    msg.textContent = payload.message || "Database operation succeeded.";
    enforced.textContent = "Executed via SQL SECURITY DEFINER Stored Procedure";
    sqlEl.textContent = payload.sql || "";
  } else {
    badge.textContent = `SQLSTATE ${payload.sqlstate || "45000"} · ERR ${payload.errno || ""}`;
    title.textContent = `${payload.kind || "BUSINESS_RULE"} — ${payload.rule_code || "ABORTED"}`;
    msg.textContent = payload.message || "Database rejected operation.";
    enforced.textContent = `Enforced by: ${payload.enforced_by || "MySQL Engine"}`;
    sqlEl.textContent = payload.sql || "";
  }
}

async function apiCall(url, options = {}) {
  const res = await fetch(url, {
    headers: { "Content-Type": "application/json" },
    ...options,
  });
  const data = await res.json();
  if (data.sql) {
    setLastSql(data.sql);
  }
  if (!res.ok || !data.ok) {
    showSignalBanner(data, false);
    throw data;
  }
  return data;
}

// Populate all dropdowns from /api/lookups
async function loadLookups() {
  const data = await apiCall("/api/lookups");
  state.visitors = data.visitors || [];
  state.employees = data.employees || [];
  state.vehicles = data.vehicles || [];
  state.guards = data.guards || [];
  state.checkpoints = data.checkpoints || [];
  state.categories = data.categories || [];
  state.parkingZones = data.parking_zones || [];
  state.idProofTypes = data.id_proof_types || [];
  state.blacklist = data.blacklist || [];

  // Visitors dropdown
  const visSel = document.getElementById("issue-visitor");
  const blVisSel = document.getElementById("bl-visitor");
  const prevVis = visSel.value;
  visSel.innerHTML = state.visitors
    .map((v) => {
      const flags = [];
      if (v.is_currently_blacklisted) flags.push("⛔ BLACKLISTED");
      if (v.is_ex_employee) flags.push(`⚠ EX-EMPLOYEE (${v.ex_employee_exit_type || "LEFT"})`);
      if (v.current_active_pass) flags.push(`🟢 ACTIVE: ${v.current_active_pass}`);
      const flagStr = flags.length ? ` [${flags.join(" | ")}]` : "";
      return `<option value="${v.visitor_id}">#${v.visitor_id} · ${v.full_name} (${v.company_name})${flagStr}</option>`;
    })
    .join("");
  if (prevVis) visSel.value = prevVis;

  blVisSel.innerHTML = state.visitors
    .map((v) => `<option value="${v.visitor_id}">#${v.visitor_id} · ${v.full_name} (${v.company_name})</option>`)
    .join("");

  // Categories dropdown
  const catSel = document.getElementById("issue-category");
  catSel.innerHTML = state.categories
    .map((c) => `<option value="${c.category_id}" data-max-hours="${c.max_pass_hours}" data-max-park="${c.max_parking_minutes}" data-req-appr="${c.requires_host_approval}" data-req-esc="${c.requires_escort}" data-park-ok="${c.parking_allowed}" data-from="${c.allowed_from}" data-to="${c.allowed_to}">
      ${c.category_code} — ${c.category_name}
    </option>`)
    .join("");
  updateCategoryPill();

  // Host employees dropdown
  const hostSel = document.getElementById("issue-host");
  hostSel.innerHTML = state.employees
    .map((e) => {
      const inactiveTag = e.is_active ? "" : " [⚠ INACTIVE HOST]";
      return `<option value="${e.emp_id}">#${e.emp_id} · ${e.full_name} (${e.dept_code})${inactiveTag}</option>`;
    })
    .join("");

  // Escort employees dropdown
  const escortSel = document.getElementById("issue-escort");
  escortSel.innerHTML = `<option value="">— No Escort Required —</option>` +
    state.employees
      .filter((e) => e.is_active)
      .map((e) => `<option value="${e.emp_id}">#${e.emp_id} · ${e.full_name} (${e.dept_code})</option>`)
      .join("");

  // Filter vehicles for currently selected visitor
  updateVehicleDropdown();

  // Security Guards dropdown
  const guardSel = document.getElementById("term-guard");
  guardSel.innerHTML = state.guards
    .map((g) => {
      const tag = g.is_active ? `${g.shift_code}` : "⚠ INACTIVE";
      return `<option value="${g.guard_id}">${g.badge_no} · ${g.full_name} [${tag}]</option>`;
    })
    .join("");

  // Checkpoints dropdown
  const ckptSel = document.getElementById("term-checkpoint");
  ckptSel.innerHTML = state.checkpoints
    .map((c) => {
      const tag = c.is_active ? c.building_name : "⚠ INACTIVE";
      return `<option value="${c.checkpoint_id}">${c.checkpoint_code} · ${c.checkpoint_name} (${tag})</option>`;
    })
    .join("");

  // Parking Zones dropdown
  const zoneSel = document.getElementById("term-parking-zone");
  zoneSel.innerHTML = state.parkingZones
    .map((z) => `<option value="${z.zone_id}">${z.zone_code} · ${z.zone_name} (${z.available_slots}/${z.capacity} free)</option>`)
    .join("");

  // ID Proof Types
  const idTypeSel = document.getElementById("reg-id-type");
  idTypeSel.innerHTML = state.idProofTypes
    .map((t) => `<option value="${t.id_proof_type_id}">${t.type_code} — ${t.type_label}</option>`)
    .join("");

  renderBlacklistTable();
}

function updateCategoryPill() {
  const catSel = document.getElementById("issue-category");
  const opt = catSel.selectedOptions[0];
  if (!opt) return;
  const maxH = opt.dataset.maxHours;
  const maxP = opt.dataset.maxPark;
  const reqA = opt.dataset.reqAppr === "1";
  const reqE = opt.dataset.reqEsc === "1";
  const parkOk = opt.dataset.parkOk === "1";
  const fromT = opt.dataset.from;
  const toT = opt.dataset.to;

  const tags = [`Max Duration: ${maxH}h`];
  if (parkOk) {
    tags.push(`Parking Limit: ${maxP} min`);
  } else {
    tags.push(`🚫 No Parking Allowed`);
  }
  if (reqA) tags.push(`⚠ Host Approval Required`);
  if (reqE) tags.push(`🛡 Escort Required`);
  tags.push(`Gate Window: ${fromT}-${toT}`);

  document.getElementById("cat-policy-pill").textContent = tags.join(" | ");
}

function updateVehicleDropdown() {
  const visitorId = parseInt(document.getElementById("issue-visitor").value, 10);
  const vehSel = document.getElementById("issue-vehicle");
  const owned = state.vehicles.filter((v) => v.visitor_id === visitorId);
  const other = state.vehicles.filter((v) => v.visitor_id !== visitorId).slice(0, 2);

  let html = `<option value="">— Walk-In (No Vehicle) —</option>`;
  owned.forEach((v) => {
    html += `<option value="${v.vehicle_id}">✔ ${v.registration_no} (${v.vehicle_type} · ${v.make_model})</option>`;
  });
  other.forEach((v) => {
    html += `<option value="${v.vehicle_id}">⚠ ${v.registration_no} (Owned by ${v.owner_name} — Tests Composite FK 1452)</option>`;
  });
  vehSel.innerHTML = html;
}

function badgeForStatus(status) {
  const map = {
    APPROVED: "badge-approved",
    PENDING_APPROVAL: "badge-expiring",
    ACTIVE_ON_CAMPUS: "badge-active",
    COMPLETED: "badge-completed",
    EXPIRED: "badge-expired",
    REVOKED: "badge-revoked",
    OVERSTAYING: "badge-overstay",
    PARKING_OVERSTAY: "badge-overstay",
    EXPIRING_SOON: "badge-expiring",
    WITHIN_WINDOW: "badge-active",
    NORMAL: "badge-active",
    ISSUED: "badge-approved",
    HOST_APPROVED: "badge-active",
    HOST_REJECTED: "badge-revoked",
    CHECKED_IN: "badge-active",
    CHECKED_OUT: "badge-completed",
    PARKED: "badge-approved",
    PARKING_EXIT: "badge-completed",
    OVERSTAY_FLAGGED: "badge-overstay",
    DENIED: "badge-denied",
  };
  return `<span class="badge ${map[status] || "badge-completed"}">${status}</span>`;
}

// Load Live Campus Occupancy View
async function loadOccupancy() {
  const data = await apiCall("/api/occupancy");
  const rows = data.rows || [];
  document.getElementById("badge-occ-count").textContent = rows.length;

  const pill = document.getElementById("health-pill");
  pill.className = "pill pill-ok";
  pill.textContent = `● MySQL 8.0 Connected (gp_app) · ${rows.length} Active on Campus`;

  const tbody = document.getElementById("tbody-occupancy");
  if (!rows.length) {
    tbody.innerHTML = `<tr><td colspan="14" style="text-align:center;color:#64748b;padding:1.2rem;">No visitors currently checked in on campus.</td></tr>`;
    return;
  }

  tbody.innerHTML = rows
    .map(
      (r) => `
      <tr class="${r.is_overstaying ? "row-overstay" : ""}">
        <td><span class="code-link" data-pass="${r.pass_code}">${r.pass_code}</span></td>
        <td>${badgeForStatus(r.occupancy_alert)}</td>
        <td><strong>${r.visitor_name}</strong></td>
        <td><span class="badge badge-approved">${r.category_code}</span></td>
        <td>${r.visitor_company}</td>
        <td><code>${r.masked_id_proof}</code></td>
        <td>
          <code>${r.vehicle_reg_no}</code>
          ${r.parking_zone_code ? `<br><small style="color:#166534">🅿 ${r.parking_zone_code}</small>` : ""}
        </td>
        <td>${r.host_name} (<code>${r.dept_code}</code>)</td>
        <td><code>${r.entry_checkpoint_code}</code> · ${r.admitted_by_guard}</td>
        <td>${r.check_in_time}</td>
        <td>${r.valid_until}</td>
        <td><strong>${r.minutes_on_campus} min</strong></td>
        <td>${r.minutes_remaining < 0 ? `<strong style="color:#b91c1c">${r.minutes_remaining} min (OVERDUE)</strong>` : `${r.minutes_remaining} min`}</td>
        <td>
          <button class="btn btn-warning btn-sm btn-quick-checkout" data-pass="${r.pass_code}">
            Check Out
          </button>
        </td>
      </tr>
    `
    )
    .join("");
}

// Load Host Approvals Queue View (vw_pending_approvals)
async function loadApprovals() {
  const data = await apiCall("/api/approvals");
  const rows = data.rows || [];
  document.getElementById("badge-appr-count").textContent = rows.length;

  const tbody = document.getElementById("tbody-approvals");
  if (!rows.length) {
    tbody.innerHTML = `<tr><td colspan="10" style="text-align:center;color:#64748b;padding:1.2rem;">No gate passes currently pending host approval.</td></tr>`;
    return;
  }

  tbody.innerHTML = rows
    .map(
      (r) => `
      <tr>
        <td><span class="code-link" data-pass="${r.pass_code}">${r.pass_code}</span></td>
        <td><strong>${r.visitor_name}</strong> (${r.visitor_company})</td>
        <td>
          ${r.is_ex_employee ? `<span class="tag-exemp">EX-EMPLOYEE: ${r.ex_employee_exit_type}</span>` : `<span class="badge badge-approved">NEW VISITOR</span>`}
        </td>
        <td><span class="badge badge-approved">${r.category_code}</span></td>
        <td>${r.host_name} (<code>${r.dept_name}</code>)</td>
        <td><code>${r.vehicle_reg_no}</code></td>
        <td style="white-space:normal;max-width:240px;">${r.visit_purpose}</td>
        <td><code>${r.requested_at}</code></td>
        <td><code>${r.valid_from} to ${r.valid_until}</code></td>
        <td>
          <div style="display:flex;gap:0.35rem;">
            <button class="btn-success-sm btn-approve-pass" data-pass="${r.pass_code}" data-host="${r.host_emp_id}">
              ✔ Approve
            </button>
            <button class="btn-danger-sm btn-reject-pass" data-pass="${r.pass_code}" data-host="${r.host_emp_id}">
              ✕ Reject
            </button>
          </div>
        </td>
      </tr>
    `
    )
    .join("");
}

// Load Live Parking Management (vw_live_parking_occupancy & vw_lookup_parking_zones)
async function loadParking() {
  const data = await apiCall("/api/parking");
  const rows = data.rows || [];
  const zones = data.zones || [];
  document.getElementById("badge-park-count").textContent = rows.length;

  // Render Parking Zones Cards
  const cardsContainer = document.getElementById("parking-zones-cards");
  cardsContainer.innerHTML = zones
    .map((z) => {
      const isFull = z.available_slots === 0;
      const pct = z.occupancy_pct;
      const fillClass = isFull ? "full" : pct > 75 ? "warn" : "";
      return `
      <div class="parking-zone-card">
        <div class="pzone-head">
          <span class="pzone-code">${z.zone_code}</span>
          <span class="pzone-avail ${isFull ? "full" : ""}">${isFull ? "FULL" : `${z.available_slots} Free`}</span>
        </div>
        <div class="pzone-name">${z.zone_name}</div>
        <div class="pzone-types">Types: ${z.allowed_vehicle_types}</div>
        <div class="progress-track">
          <div class="progress-fill ${fillClass}" style="width: ${Math.min(100, pct)}%"></div>
        </div>
        <div style="font-size: 10.5px; color:#64748b; margin-top:0.3rem; display:flex; justify-content:space-between;">
          <span>Occupied: ${z.occupied_slots} / ${z.capacity}</span>
          <span><strong>${pct}%</strong></span>
        </div>
      </div>
    `;
    })
    .join("");

  // Render Active Parked Vehicles Table
  const tbody = document.getElementById("tbody-parking");
  if (!rows.length) {
    tbody.innerHTML = `<tr><td colspan="11" style="text-align:center;color:#64748b;padding:1.2rem;">No vehicles currently parked in campus lots.</td></tr>`;
    return;
  }

  tbody.innerHTML = rows
    .map(
      (r) => `
      <tr class="${r.is_overstay ? "row-overstay" : ""}">
        <td>${badgeForStatus(r.parking_alert)}</td>
        <td><span class="code-link" data-pass="${r.pass_code}">${r.pass_code}</span></td>
        <td><strong><code>${r.registration_no}</code></strong></td>
        <td>${r.vehicle_type} (${r.make_model})</td>
        <td>${r.visitor_name}</td>
        <td><span class="badge badge-approved">${r.zone_code}</span></td>
        <td><code>${r.parked_at}</code></td>
        <td><strong>${r.minutes_parked} min</strong></td>
        <td>${r.allocated_minutes} min</td>
        <td>
          ${r.is_overstay ? `<span class="badge badge-overstay">PARKING OVERSTAY (+${r.minutes_parked - r.allocated_minutes}m)</span>` : `<span class="badge badge-active">${r.minutes_remaining}m left</span>`}
        </td>
        <td>
          <button class="btn btn-secondary btn-sm btn-quick-exit-park" data-pass="${r.pass_code}">
            Exit Bay
          </button>
        </td>
      </tr>
    `
    )
    .join("");
}

// Load Immutable Access Audit Trail View
async function loadAudit() {
  const data = await apiCall("/api/audit");
  const tbody = document.getElementById("tbody-audit");
  tbody.innerHTML = (data.rows || [])
    .map(
      (r) => `
      <tr class="${r.event_type === "DENIED" || r.event_type === "OVERSTAY_FLAGGED" ? "row-overstay" : ""}">
        <td><code>#${r.log_id}</code></td>
        <td><code>${r.event_at}</code></td>
        <td>${badgeForStatus(r.event_type)}</td>
        <td><span class="code-link" data-pass="${r.pass_code}">${r.pass_code}</span></td>
        <td><code>${r.from_status} → ${r.to_status}</code></td>
        <td>${r.visitor_name}</td>
        <td>${r.actor_guard}</td>
        <td><code>${r.checkpoint_code}</code></td>
        <td style="white-space:normal;max-width:460px;">${r.details}</td>
      </tr>
    `
    )
    .join("");
}

// Load Department Visit Analytics (Window Functions)
async function loadAnalytics() {
  const data = await apiCall("/api/analytics");
  const deptTbody = document.getElementById("tbody-analytics-dept");
  deptTbody.innerHTML = (data.departments || [])
    .map(
      (d) => `
      <tr>
        <td><strong>#${d.visit_rank}</strong></td>
        <td><code>#${d.visit_dense_rank}</code></td>
        <td><code>${d.dept_code}</code></td>
        <td><strong>${d.dept_name}</strong></td>
        <td>${d.building_name} (Fl ${d.floor_no})</td>
        <td><strong>${d.total_passes}</strong></td>
        <td>${d.active_now}</td>
        <td>${d.completed_visits}</td>
        <td>${d.overstay_incidents > 0 ? `<strong style="color:#b91c1c">${d.overstay_incidents}</strong>` : "0"}</td>
        <td>${d.avg_duration_min} min</td>
        <td>${d.pct_of_campus_traffic}%</td>
        <td><code>${d.cumulative_passes}</code></td>
        <td><code>${d.peak_arrival_window}</code></td>
      </tr>
    `
    )
    .join("");

  const dailyTbody = document.getElementById("tbody-analytics-daily");
  dailyTbody.innerHTML = (data.daily_trend || [])
    .map(
      (t) => `
      <tr>
        <td><code>${t.visit_date}</code></td>
        <td><strong>${t.daily_passes}</strong></td>
        <td>${t.completed_count}</td>
        <td>${t.overstay_count}</td>
        <td><code>${t.running_total_passes}</code></td>
        <td>${t.moving_avg_7d}</td>
      </tr>
    `
    )
    .join("");
}

// Load All Gate Passes View
async function loadPasses() {
  const data = await apiCall("/api/passes");
  const tbody = document.getElementById("tbody-passes");
  tbody.innerHTML = (data.rows || [])
    .map(
      (p) => `
      <tr class="${p.is_overstay ? "row-overstay" : ""}">
        <td><span class="code-link" data-pass="${p.pass_code}">${p.pass_code}</span></td>
        <td>${badgeForStatus(p.status)}</td>
        <td><strong>#${p.visitor_id} ${p.visitor_name}</strong> (${p.visitor_company})</td>
        <td><span class="badge badge-approved">${p.category_code}</span></td>
        <td>${p.host_name} (<code>${p.dept_code}</code>)</td>
        <td><code>${p.vehicle_reg_no}</code></td>
        <td>${p.visit_purpose}</td>
        <td><code>${p.valid_from}</code></td>
        <td><code>${p.valid_until}</code></td>
        <td><code>${p.check_in_time || "-"}</code></td>
        <td><code>${p.check_out_time || "-"}</code></td>
        <td>${p.visit_duration_min != null ? `${p.visit_duration_min} min` : "-"}</td>
        <td>${p.is_overstay ? `<span class="badge badge-overstay">YES</span>` : "No"}</td>
        <td>${p.approved_by || "-"}</td>
      </tr>
    `
    )
    .join("");
}

function renderBlacklistTable() {
  const tbody = document.getElementById("tbody-blacklist");
  if (!tbody) return;
  tbody.innerHTML = state.blacklist
    .map(
      (b) => `
      <tr>
        <td><code>#${b.blacklist_id}</code></td>
        <td><strong>#${b.visitor_id} ${b.visitor_name}</strong></td>
        <td><span class="badge ${b.severity === "CRITICAL" || b.severity === "HIGH" ? "badge-overstay" : "badge-expiring"}">${b.severity}</span></td>
        <td><code>${b.effective_state}</code></td>
        <td style="white-space:normal;max-width:260px;">${b.reason}</td>
        <td>
          ${
            b.effective_state === "ACTIVE_BLOCK"
              ? `<button class="btn btn-secondary btn-sm btn-lift-bl" data-id="${b.blacklist_id}">Lift Hold</button>`
              : `<span style="color:#64748b;font-size:11px;">${b.lifted_at || b.end_at || "Cleared"}</span>`
          }
        </td>
      </tr>
    `
    )
    .join("");
}

async function refreshAllViews() {
  try {
    await Promise.all([
      loadLookups(),
      loadOccupancy(),
      loadApprovals(),
      loadParking(),
      loadAudit(),
      loadAnalytics(),
      loadPasses(),
    ]);
  } catch (err) {
    console.error("Refresh error:", err);
  }
}

function setTerminalCode(code) {
  if (!code || code === "-") return;
  const input = document.getElementById("term-pass-code");
  input.value = code;
  input.focus();
  document.getElementById("terminal-result").innerHTML =
    `Loaded pass <code>${code}</code> into Security Gate Terminal. Click <strong>Check In</strong>, <strong>Park Vehicle</strong>, or <strong>Check Out</strong>.`;
}

// Event Listeners Setup
document.addEventListener("DOMContentLoaded", () => {
  refreshAllViews();

  // Auto-refresh occupancy, approvals, and parking every 5 seconds
  state.autoRefreshTimer = setInterval(() => {
    const chk = document.getElementById("chk-auto-refresh");
    if (chk && chk.checked) {
      loadOccupancy().catch(() => {});
      loadApprovals().catch(() => {});
      loadParking().catch(() => {});
    }
  }, 5000);

  document.getElementById("issue-visitor").addEventListener("change", updateVehicleDropdown);
  document.getElementById("issue-category").addEventListener("change", updateCategoryPill);

  document.getElementById("btn-close-banner").addEventListener("click", () => {
    document.getElementById("signal-banner").classList.add("hidden");
  });

  document.getElementById("btn-refresh-all").addEventListener("click", () => {
    refreshAllViews();
  });

  // Manual Expiry Sweep Button
  document.getElementById("btn-expire-sweep").addEventListener("click", async () => {
    try {
      const data = await apiCall("/api/maintenance/expire-sweep", { method: "POST" });
      showSignalBanner({ ...data.result, sql: data.sql }, true);
      await refreshAllViews();
    } catch (_) {}
  });

  // 1. Issue Gate Pass Form
  document.getElementById("form-issue-pass").addEventListener("submit", async (e) => {
    e.preventDefault();
    const payload = {
      visitor_id: document.getElementById("issue-visitor").value,
      host_emp_id: document.getElementById("issue-host").value,
      category_id: document.getElementById("issue-category").value,
      vehicle_id: document.getElementById("issue-vehicle").value || null,
      duration_hours: document.getElementById("issue-duration").value,
      escort_emp_id: document.getElementById("issue-escort").value || null,
      visit_purpose: document.getElementById("issue-purpose").value,
    };
    try {
      const data = await apiCall("/api/passes", {
        method: "POST",
        body: JSON.stringify(payload),
      });
      const r = data.result;
      document.getElementById("issued-pass-code").textContent = r.pass_code;
      document.getElementById("issued-pass-uuid").textContent = `UUIDv1: ${r.pass_uuid} · Valid until ${r.valid_until}`;
      document.getElementById("issued-pass-box").classList.remove("hidden");
      setTerminalCode(r.pass_code);
      showSignalBanner({ ...r, sql: data.sql }, true);
      await refreshAllViews();
    } catch (_) {
      await loadAudit();
    }
  });

  document.getElementById("btn-send-to-terminal").addEventListener("click", () => {
    const code = document.getElementById("issued-pass-code").textContent;
    setTerminalCode(code);
  });

  // 2. Gate Terminal Check-In
  document.getElementById("btn-checkin").addEventListener("click", async () => {
    const payload = {
      pass_code: document.getElementById("term-pass-code").value,
      guard_id: document.getElementById("term-guard").value,
      checkpoint_id: document.getElementById("term-checkpoint").value,
    };
    try {
      const data = await apiCall("/api/gate/checkin", {
        method: "POST",
        body: JSON.stringify(payload),
      });
      const r = data.result;
      document.getElementById("terminal-result").innerHTML =
        `<strong style="color:#15803d">✔ ${r.status_code}:</strong> ${r.message}`;
      showSignalBanner({ ...r, sql: data.sql }, true);
      await refreshAllViews();
    } catch (err) {
      document.getElementById("terminal-result").innerHTML =
        `<strong style="color:#b91c1c">✖ ERR ${err.errno || ""} (${err.sqlstate || "45000"}):</strong> ${err.message || ""}`;
      await loadAudit();
    }
  });

  // 3. Gate Terminal Check-Out
  document.getElementById("btn-checkout").addEventListener("click", async () => {
    const payload = {
      pass_code: document.getElementById("term-pass-code").value,
      guard_id: document.getElementById("term-guard").value,
      checkpoint_id: document.getElementById("term-checkpoint").value,
    };
    try {
      const data = await apiCall("/api/gate/checkout", {
        method: "POST",
        body: JSON.stringify(payload),
      });
      const r = data.result;
      const color = r.is_overstay ? "#b45309" : "#15803d";
      document.getElementById("terminal-result").innerHTML =
        `<strong style="color:${color}">✔ ${r.status_code} (${r.visit_duration_min} min):</strong> ${r.message}`;
      showSignalBanner({ ...r, sql: data.sql }, true);
      await refreshAllViews();
    } catch (err) {
      document.getElementById("terminal-result").innerHTML =
        `<strong style="color:#b91c1c">✖ ERR ${err.errno || ""} (${err.sqlstate || "45000"}):</strong> ${err.message || ""}`;
      await loadAudit();
    }
  });

  // 4. Park Vehicle Button
  document.getElementById("btn-park").addEventListener("click", async () => {
    const payload = {
      pass_code: document.getElementById("term-pass-code").value,
      zone_id: document.getElementById("term-parking-zone").value,
      guard_id: document.getElementById("term-guard").value,
    };
    try {
      const data = await apiCall("/api/parking/park", {
        method: "POST",
        body: JSON.stringify(payload),
      });
      const r = data.result;
      document.getElementById("terminal-result").innerHTML =
        `<strong style="color:#15803d">✔ ${r.status_code}:</strong> ${r.message}`;
      showSignalBanner({ ...r, sql: data.sql }, true);
      await refreshAllViews();
    } catch (err) {
      document.getElementById("terminal-result").innerHTML =
        `<strong style="color:#b91c1c">✖ ERR ${err.errno || ""} (${err.sqlstate || "45000"}):</strong> ${err.message || ""}`;
      await loadAudit();
    }
  });

  // 5. Exit Parking Button
  document.getElementById("btn-exit-park").addEventListener("click", async () => {
    const payload = {
      pass_code: document.getElementById("term-pass-code").value,
      guard_id: document.getElementById("term-guard").value,
    };
    try {
      const data = await apiCall("/api/parking/exit", {
        method: "POST",
        body: JSON.stringify(payload),
      });
      const r = data.result;
      document.getElementById("terminal-result").innerHTML =
        `<strong style="color:#15803d">✔ ${r.status_code}:</strong> ${r.message}`;
      showSignalBanner({ ...r, sql: data.sql }, true);
      await refreshAllViews();
    } catch (err) {
      document.getElementById("terminal-result").innerHTML =
        `<strong style="color:#b91c1c">✖ ERR ${err.errno || ""} (${err.sqlstate || "45000"}):</strong> ${err.message || ""}`;
      await loadAudit();
    }
  });

  // 6. Gate Terminal Revoke
  document.getElementById("btn-revoke").addEventListener("click", async () => {
    const payload = {
      pass_code: document.getElementById("term-pass-code").value,
      guard_id: document.getElementById("term-guard").value,
      reason: "Revoked at Security Gate Terminal",
    };
    try {
      const data = await apiCall("/api/passes/revoke", {
        method: "POST",
        body: JSON.stringify(payload),
      });
      document.getElementById("terminal-result").innerHTML =
        `<strong>✔ REVOKED:</strong> ${data.result.message}`;
      showSignalBanner({ ...data.result, sql: data.sql }, true);
      await refreshAllViews();
    } catch (err) {
      document.getElementById("terminal-result").innerHTML =
        `<strong style="color:#b91c1c">✖ ERR ${err.errno || ""}:</strong> ${err.message || ""}`;
      await loadAudit();
    }
  });

  // Scenario Matrix Clicks
  document.querySelectorAll(".scenario-chip").forEach((btn) => {
    btn.addEventListener("click", async () => {
      const action = btn.dataset.action;
      if (action === "fill-code") {
        setTerminalCode(btn.dataset.code);
      } else if (action === "issue-blacklisted") {
        try {
          await apiCall("/api/passes", {
            method: "POST",
            body: JSON.stringify({
              visitor_id: 2,
              host_emp_id: 1,
              category_id: 1,
              vehicle_id: null,
              duration_hours: 4,
              visit_purpose: "Attempted entry by blacklisted visitor #2",
            }),
          });
        } catch (_) {
          await loadAudit();
        }
      } else if (action === "issue-duplicate") {
        try {
          await apiCall("/api/passes", {
            method: "POST",
            body: JSON.stringify({
              visitor_id: 8,
              host_emp_id: 6,
              category_id: 1,
              vehicle_id: null,
              duration_hours: 4,
              visit_purpose: "Attempted duplicate active pass for visitor #8",
            }),
          });
        } catch (_) {
          await loadAudit();
        }
      } else if (action === "issue-courier-overdur") {
        try {
          await apiCall("/api/passes", {
            method: "POST",
            body: JSON.stringify({
              visitor_id: 22,
              host_emp_id: 13,
              category_id: 5, // DELIVERY_COURIER max is 2h
              vehicle_id: 12,
              duration_hours: 6, // Exceeds 2h cap
              visit_purpose: "Delivery attempt exceeding category limit",
            }),
          });
        } catch (_) {
          await loadAudit();
        }
      } else if (action === "probe-audit-delete") {
        try {
          await apiCall("/api/security-probe", {
            method: "POST",
            body: JSON.stringify({ probe: "delete_audit" }),
          });
        } catch (_) {}
      }
    });
  });

  // Tab Navigation
  document.querySelectorAll(".tab-btn").forEach((btn) => {
    btn.addEventListener("click", () => {
      document.querySelectorAll(".tab-btn").forEach((b) => b.classList.remove("active"));
      document.querySelectorAll(".tab-pane").forEach((p) => p.classList.remove("active"));
      btn.classList.add("active");
      document.getElementById(btn.dataset.tab).classList.add("active");
    });
  });

  // Delegated click handlers inside tables (clickable pass codes, quick checkout, approvals, lift blacklist)
  document.body.addEventListener("click", async (e) => {
    const codeLink = e.target.closest(".code-link");
    if (codeLink) {
      setTerminalCode(codeLink.dataset.pass);
      return;
    }

    const quickOut = e.target.closest(".btn-quick-checkout");
    if (quickOut) {
      const code = quickOut.dataset.pass;
      setTerminalCode(code);
      document.getElementById("btn-checkout").click();
      return;
    }

    const quickExitPark = e.target.closest(".btn-quick-exit-park");
    if (quickExitPark) {
      const code = quickExitPark.dataset.pass;
      setTerminalCode(code);
      document.getElementById("btn-exit-park").click();
      return;
    }

    // Host Approval Actions
    const approveBtn = e.target.closest(".btn-approve-pass");
    if (approveBtn) {
      const code = approveBtn.dataset.pass;
      const hostId = approveBtn.dataset.host || 1;
      try {
        const data = await apiCall("/api/passes/approve", {
          method: "POST",
          body: JSON.stringify({
            pass_code: code,
            approver_emp_id: hostId,
            decision: "APPROVE",
            notes: "Approved by host employee via console",
          }),
        });
        showSignalBanner({ ...data.result, sql: data.sql }, true);
        await refreshAllViews();
        setTerminalCode(code);
      } catch (_) {}
      return;
    }

    const rejectBtn = e.target.closest(".btn-reject-pass");
    if (rejectBtn) {
      const code = rejectBtn.dataset.pass;
      const hostId = rejectBtn.dataset.host || 1;
      try {
        const data = await apiCall("/api/passes/approve", {
          method: "POST",
          body: JSON.stringify({
            pass_code: code,
            approver_emp_id: hostId,
            decision: "REJECT",
            notes: "Declined by host employee",
          }),
        });
        showSignalBanner({ ...data.result, sql: data.sql }, true);
        await refreshAllViews();
      } catch (_) {}
      return;
    }

    const liftBtn = e.target.closest(".btn-lift-bl");
    if (liftBtn) {
      const blId = liftBtn.dataset.id;
      try {
        const data = await apiCall("/api/blacklist/lift", {
          method: "POST",
          body: JSON.stringify({
            blacklist_id: blId,
            lifted_reason: "Lifted by Security Admin via Console",
          }),
        });
        showSignalBanner({ ...data.result, sql: data.sql }, true);
        await refreshAllViews();
      } catch (_) {}
    }
  });

  // Register Visitor Form
  document.getElementById("form-register-visitor").addEventListener("submit", async (e) => {
    e.preventDefault();
    const payload = {
      first_name: document.getElementById("reg-fname").value,
      last_name: document.getElementById("reg-lname").value,
      phone: document.getElementById("reg-phone").value,
      email: document.getElementById("reg-email").value,
      id_proof_type_id: document.getElementById("reg-id-type").value,
      raw_id_number: document.getElementById("reg-id-num").value,
      company_name: document.getElementById("reg-company").value,
      vehicle_reg_no: document.getElementById("reg-veh-plate").value,
      vehicle_type: "SEDAN",
      vehicle_model: "Registered Vehicle",
    };
    try {
      const data = await apiCall("/api/visitors", {
        method: "POST",
        body: JSON.stringify(payload),
      });
      showSignalBanner({ ...data.result, sql: data.sql }, true);
      e.target.reset();
      await refreshAllViews();
    } catch (_) {}
  });

  // Blacklist Visitor Form
  document.getElementById("form-blacklist").addEventListener("submit", async (e) => {
    e.preventDefault();
    const payload = {
      visitor_id: document.getElementById("bl-visitor").value,
      severity: document.getElementById("bl-severity").value,
      reason: document.getElementById("bl-reason").value,
      duration_hours: document.getElementById("bl-hours").value || null,
      guard_id: document.getElementById("term-guard").value || 1,
    };
    try {
      const data = await apiCall("/api/blacklist", {
        method: "POST",
        body: JSON.stringify(payload),
      });
      showSignalBanner({ ...data.result, sql: data.sql }, true);
      await refreshAllViews();
    } catch (_) {}
  });
});
