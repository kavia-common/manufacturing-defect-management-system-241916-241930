-- Migration 003: Indexes and analytics-friendly views.

BEGIN;

-- =========================
-- Indexes for configs
-- =========================
CREATE INDEX IF NOT EXISTS idx_defect_types_active ON config_defect_types(is_active);
CREATE INDEX IF NOT EXISTS idx_lines_active ON config_lines(is_active);
CREATE INDEX IF NOT EXISTS idx_shifts_active ON config_shifts(is_active);
CREATE INDEX IF NOT EXISTS idx_parts_active ON config_parts(is_active);

-- =========================
-- Defects indexes
-- =========================
CREATE INDEX IF NOT EXISTS idx_defects_occurred_at ON defects(occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_defects_reported_at ON defects(reported_at DESC);
CREATE INDEX IF NOT EXISTS idx_defects_status ON defects(status);
CREATE INDEX IF NOT EXISTS idx_defects_severity ON defects(severity);
CREATE INDEX IF NOT EXISTS idx_defects_line ON defects(line_id);
CREATE INDEX IF NOT EXISTS idx_defects_shift ON defects(shift_id);
CREATE INDEX IF NOT EXISTS idx_defects_part ON defects(part_id);
CREATE INDEX IF NOT EXISTS idx_defects_defect_type ON defects(defect_type_id);

-- Composite indexes for common dashboard filters
CREATE INDEX IF NOT EXISTS idx_defects_line_occurred_at ON defects(line_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_defects_type_occurred_at ON defects(defect_type_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_defects_status_occurred_at ON defects(status, occurred_at DESC);

-- RCA
CREATE INDEX IF NOT EXISTS idx_defect_rca_completed_at ON defect_rca(completed_at DESC);

-- Corrective actions
CREATE INDEX IF NOT EXISTS idx_actions_due_date ON corrective_actions(due_date);
CREATE INDEX IF NOT EXISTS idx_actions_status ON corrective_actions(status);
CREATE INDEX IF NOT EXISTS idx_actions_defect ON corrective_actions(defect_id);
CREATE INDEX IF NOT EXISTS idx_actions_owner ON corrective_actions(owner_user_id);

-- Alerts
CREATE INDEX IF NOT EXISTS idx_alerts_active ON alerts(is_active, triggered_at DESC);
CREATE INDEX IF NOT EXISTS idx_alerts_entity ON alerts(entity_type, entity_id);

-- Audit logs
CREATE INDEX IF NOT EXISTS idx_audit_logs_at ON audit_logs(at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_logs_entity ON audit_logs(entity_type, entity_id);

-- =========================
-- Dashboard aggregation views
-- =========================

-- Pareto by defect type (counts and quantities)
CREATE OR REPLACE VIEW vw_pareto_defect_types AS
SELECT
  d.defect_type_id,
  t.code AS defect_type_code,
  t.name AS defect_type_name,
  COUNT(*) AS defect_count,
  SUM(d.quantity)::bigint AS total_quantity,
  MIN(d.occurred_at) AS first_seen_at,
  MAX(d.occurred_at) AS last_seen_at
FROM defects d
JOIN config_defect_types t ON t.id = d.defect_type_id
WHERE d.status <> 'void'
GROUP BY d.defect_type_id, t.code, t.name
ORDER BY total_quantity DESC, defect_count DESC;

-- Trend by day/line/severity
CREATE OR REPLACE VIEW vw_trends_daily AS
SELECT
  date_trunc('day', d.occurred_at)::date AS day,
  d.line_id,
  l.code AS line_code,
  l.name AS line_name,
  d.severity,
  COUNT(*) AS defect_count,
  SUM(d.quantity)::bigint AS total_quantity
FROM defects d
JOIN config_lines l ON l.id = d.line_id
WHERE d.status <> 'void'
GROUP BY 1,2,3,4,5
ORDER BY day DESC;

-- Open actions due soon/overdue view (used to generate alerts in backend scheduler)
CREATE OR REPLACE VIEW vw_actions_due AS
SELECT
  a.*,
  (a.due_date < CURRENT_DATE) AS is_overdue,
  (a.due_date BETWEEN CURRENT_DATE AND (CURRENT_DATE + INTERVAL '3 days')) AS is_due_soon
FROM corrective_actions a
WHERE a.status IN ('open','in_progress','blocked')
  AND a.due_date IS NOT NULL;

COMMIT;
