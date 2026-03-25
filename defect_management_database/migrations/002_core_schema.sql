-- Migration 002: Core transactional schema for defect management.
-- Idempotent where possible; intended to be run on a fresh DB but safe for re-run if objects exist.

BEGIN;

-- =========================
-- Utility functions/triggers
-- =========================

-- Keep updated_at current on updates.
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Immutable audit log: prevent UPDATE/DELETE.
CREATE OR REPLACE FUNCTION prevent_mutation()
RETURNS trigger AS $$
BEGIN
  RAISE EXCEPTION 'Rows in % are immutable', TG_TABLE_NAME;
END;
$$ LANGUAGE plpgsql;

-- =========================
-- Enums
-- =========================
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'defect_severity') THEN
    CREATE TYPE defect_severity AS ENUM ('low','medium','high','critical');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'workflow_status') THEN
    CREATE TYPE workflow_status AS ENUM ('open','triaged','rca_required','rca_in_progress','actions_required','in_verification','closed','void');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'action_status') THEN
    CREATE TYPE action_status AS ENUM ('open','in_progress','blocked','done','verified','cancelled');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'audit_entity') THEN
    CREATE TYPE audit_entity AS ENUM ('user','role','config','defect','rca','corrective_action','alert','attachment');
  END IF;
END $$;

-- =========================
-- Auth/RBAC tables
-- =========================

CREATE TABLE IF NOT EXISTS roles (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  name citext NOT NULL UNIQUE,
  description text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS users (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  -- Supabase user id (auth.users.id) can be stored here for JWT mapping
  supabase_uid uuid UNIQUE,
  email citext UNIQUE,
  full_name text,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TRIGGER trg_users_updated_at
BEFORE UPDATE ON users
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS user_roles (
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role_id uuid NOT NULL REFERENCES roles(id) ON DELETE RESTRICT,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, role_id)
);

-- =========================
-- Config master tables
-- =========================

CREATE TABLE IF NOT EXISTS config_defect_types (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  code text NOT NULL UNIQUE,
  name text NOT NULL,
  category text,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TRIGGER trg_config_defect_types_updated_at
BEFORE UPDATE ON config_defect_types
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS config_lines (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  code text NOT NULL UNIQUE,
  name text NOT NULL,
  plant text,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TRIGGER trg_config_lines_updated_at
BEFORE UPDATE ON config_lines
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS config_shifts (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  code text NOT NULL UNIQUE,
  name text NOT NULL,
  start_time time NOT NULL,
  end_time time NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TRIGGER trg_config_shifts_updated_at
BEFORE UPDATE ON config_shifts
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS config_parts (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  part_no text NOT NULL UNIQUE,
  name text NOT NULL,
  customer text,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TRIGGER trg_config_parts_updated_at
BEFORE UPDATE ON config_parts
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Optional: defect severity rules per defect type/line/part (simple rule engine hook)
CREATE TABLE IF NOT EXISTS config_severity_rules (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  defect_type_id uuid REFERENCES config_defect_types(id) ON DELETE CASCADE,
  line_id uuid REFERENCES config_lines(id) ON DELETE CASCADE,
  part_id uuid REFERENCES config_parts(id) ON DELETE CASCADE,
  -- Condition metadata stored as JSON for backend evaluation, but keep severity as explicit for indexing.
  condition jsonb NOT NULL DEFAULT '{}'::jsonb,
  severity defect_severity NOT NULL,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  -- Avoid exact duplicates
  UNIQUE (defect_type_id, line_id, part_id, severity)
);

CREATE TRIGGER trg_config_severity_rules_updated_at
BEFORE UPDATE ON config_severity_rules
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- =========================
-- Defects
-- =========================

CREATE TABLE IF NOT EXISTS defects (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  defect_no bigserial UNIQUE,
  occurred_at timestamptz NOT NULL,
  reported_at timestamptz NOT NULL DEFAULT now(),

  line_id uuid NOT NULL REFERENCES config_lines(id) ON DELETE RESTRICT,
  shift_id uuid NOT NULL REFERENCES config_shifts(id) ON DELETE RESTRICT,
  part_id uuid REFERENCES config_parts(id) ON DELETE SET NULL,
  defect_type_id uuid NOT NULL REFERENCES config_defect_types(id) ON DELETE RESTRICT,

  severity defect_severity NOT NULL DEFAULT 'medium',
  quantity int NOT NULL DEFAULT 1 CHECK (quantity > 0),

  description text,
  -- e.g. operator name or station
  station text,

  status workflow_status NOT NULL DEFAULT 'open',

  created_by uuid REFERENCES users(id) ON DELETE SET NULL,
  updated_by uuid REFERENCES users(id) ON DELETE SET NULL,

  -- Denormalized convenience fields for dashboards / exports
  plant text,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TRIGGER trg_defects_updated_at
BEFORE UPDATE ON defects
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Status history (immutable)
CREATE TABLE IF NOT EXISTS defect_status_history (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  defect_id uuid NOT NULL REFERENCES defects(id) ON DELETE CASCADE,
  from_status workflow_status,
  to_status workflow_status NOT NULL,
  reason text,
  changed_by uuid REFERENCES users(id) ON DELETE SET NULL,
  changed_at timestamptz NOT NULL DEFAULT now()
);

CREATE TRIGGER trg_defect_status_history_immutable_u
BEFORE UPDATE ON defect_status_history
FOR EACH ROW EXECUTE FUNCTION prevent_mutation();

CREATE TRIGGER trg_defect_status_history_immutable_d
BEFORE DELETE ON defect_status_history
FOR EACH ROW EXECUTE FUNCTION prevent_mutation();

-- Attachments metadata (photo upload integration hook)
CREATE TABLE IF NOT EXISTS defect_attachments (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  defect_id uuid NOT NULL REFERENCES defects(id) ON DELETE CASCADE,
  storage_provider text NOT NULL DEFAULT 'supabase',
  bucket text,
  object_key text NOT NULL,
  url text,
  content_type text,
  bytes bigint CHECK (bytes IS NULL OR bytes >= 0),
  uploaded_by uuid REFERENCES users(id) ON DELETE SET NULL,
  uploaded_at timestamptz NOT NULL DEFAULT now()
);

-- =========================
-- RCA (Root Cause Analysis)
-- =========================

CREATE TABLE IF NOT EXISTS defect_rca (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  defect_id uuid NOT NULL UNIQUE REFERENCES defects(id) ON DELETE CASCADE,

  -- structured fields for reporting plus JSON for flexible prompts
  problem_statement text,
  root_cause text,
  containment_action text,
  why_analysis jsonb NOT NULL DEFAULT '[]'::jsonb, -- list of whys
  contributing_factors text,

  completed_by uuid REFERENCES users(id) ON DELETE SET NULL,
  completed_at timestamptz,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TRIGGER trg_defect_rca_updated_at
BEFORE UPDATE ON defect_rca
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- =========================
-- Corrective actions
-- =========================

CREATE TABLE IF NOT EXISTS corrective_actions (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  defect_id uuid NOT NULL REFERENCES defects(id) ON DELETE CASCADE,
  rca_id uuid REFERENCES defect_rca(id) ON DELETE SET NULL,

  title text NOT NULL,
  description text,

  owner_user_id uuid REFERENCES users(id) ON DELETE SET NULL,
  due_date date,
  status action_status NOT NULL DEFAULT 'open',

  created_by uuid REFERENCES users(id) ON DELETE SET NULL,
  updated_by uuid REFERENCES users(id) ON DELETE SET NULL,

  closed_at timestamptz,
  verified_by uuid REFERENCES users(id) ON DELETE SET NULL,
  verified_at timestamptz,

  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TRIGGER trg_corrective_actions_updated_at
BEFORE UPDATE ON corrective_actions
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Action status history (immutable)
CREATE TABLE IF NOT EXISTS corrective_action_status_history (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  corrective_action_id uuid NOT NULL REFERENCES corrective_actions(id) ON DELETE CASCADE,
  from_status action_status,
  to_status action_status NOT NULL,
  reason text,
  changed_by uuid REFERENCES users(id) ON DELETE SET NULL,
  changed_at timestamptz NOT NULL DEFAULT now()
);

CREATE TRIGGER trg_corrective_action_status_history_immutable_u
BEFORE UPDATE ON corrective_action_status_history
FOR EACH ROW EXECUTE FUNCTION prevent_mutation();

CREATE TRIGGER trg_corrective_action_status_history_immutable_d
BEFORE DELETE ON corrective_action_status_history
FOR EACH ROW EXECUTE FUNCTION prevent_mutation();

-- =========================
-- Alerts (due/overdue)
-- =========================

CREATE TABLE IF NOT EXISTS alerts (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  alert_type text NOT NULL, -- e.g. 'action_due', 'action_overdue', 'rca_missing'
  entity_type audit_entity NOT NULL,
  entity_id uuid NOT NULL,
  message text NOT NULL,
  severity defect_severity NOT NULL DEFAULT 'medium',
  is_active boolean NOT NULL DEFAULT true,
  triggered_at timestamptz NOT NULL DEFAULT now(),
  acknowledged_at timestamptz,
  acknowledged_by uuid REFERENCES users(id) ON DELETE SET NULL,
  closed_at timestamptz
);

-- =========================
-- Audit logs (immutable)
-- =========================

CREATE TABLE IF NOT EXISTS audit_logs (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  entity_type audit_entity NOT NULL,
  entity_id uuid,
  action text NOT NULL, -- create/update/delete/status_change/login/etc
  actor_user_id uuid REFERENCES users(id) ON DELETE SET NULL,
  at timestamptz NOT NULL DEFAULT now(),
  ip inet,
  user_agent text,
  -- Store before/after snapshots if desired
  before jsonb,
  after jsonb,
  meta jsonb NOT NULL DEFAULT '{}'::jsonb
);

CREATE TRIGGER trg_audit_logs_immutable_u
BEFORE UPDATE ON audit_logs
FOR EACH ROW EXECUTE FUNCTION prevent_mutation();

CREATE TRIGGER trg_audit_logs_immutable_d
BEFORE DELETE ON audit_logs
FOR EACH ROW EXECUTE FUNCTION prevent_mutation();

COMMIT;
