-- Seed 002: Demo data (users + a few defects + RCA + corrective actions).
-- Uses UPSERT patterns so it can be re-run in dev.

BEGIN;

-- Demo users (supabase_uid left NULL; backend can map later)
INSERT INTO users (email, full_name, is_active)
VALUES
  ('qe@example.com', 'Quality Engineer', true),
  ('supervisor@example.com', 'Production Supervisor', true),
  ('operator@example.com', 'Line Operator', true)
ON CONFLICT (email) DO UPDATE SET full_name = EXCLUDED.full_name, is_active = EXCLUDED.is_active;

-- Assign roles
WITH
  u_qe AS (SELECT id FROM users WHERE email='qe@example.com'),
  u_sup AS (SELECT id FROM users WHERE email='supervisor@example.com'),
  u_op AS (SELECT id FROM users WHERE email='operator@example.com'),
  r_qe AS (SELECT id FROM roles WHERE name='quality_engineer'),
  r_sup AS (SELECT id FROM roles WHERE name='production_supervisor'),
  r_op AS (SELECT id FROM roles WHERE name='operator')
INSERT INTO user_roles (user_id, role_id)
SELECT u_qe.id, r_qe.id FROM u_qe, r_qe
ON CONFLICT DO NOTHING;

WITH u_sup AS (SELECT id FROM users WHERE email='supervisor@example.com'),
     r_sup AS (SELECT id FROM roles WHERE name='production_supervisor')
INSERT INTO user_roles (user_id, role_id)
SELECT u_sup.id, r_sup.id FROM u_sup, r_sup
ON CONFLICT DO NOTHING;

WITH u_op AS (SELECT id FROM users WHERE email='operator@example.com'),
     r_op AS (SELECT id FROM roles WHERE name='operator')
INSERT INTO user_roles (user_id, role_id)
SELECT u_op.id, r_op.id FROM u_op, r_op
ON CONFLICT DO NOTHING;

-- Sample defects
WITH
  line AS (SELECT id, plant FROM config_lines WHERE code='LINE_A'),
  shift AS (SELECT id FROM config_shifts WHERE code='SHIFT_1'),
  part AS (SELECT id FROM config_parts WHERE part_no='P-1000'),
  dtype AS (SELECT id FROM config_defect_types WHERE code='SCRATCH'),
  actor AS (SELECT id FROM users WHERE email='operator@example.com')
INSERT INTO defects (occurred_at, line_id, shift_id, part_id, defect_type_id, severity, quantity, description, station, status, created_by, updated_by, plant)
SELECT
  now() - interval '2 days',
  line.id,
  shift.id,
  part.id,
  dtype.id,
  'medium'::defect_severity,
  5,
  'Surface scratch found during inspection',
  'Station 3',
  'rca_required'::workflow_status,
  actor.id,
  actor.id,
  line.plant
FROM line, shift, part, dtype, actor
ON CONFLICT (defect_no) DO NOTHING;

-- Add RCA for the latest defect and a corrective action
WITH
  d AS (SELECT id FROM defects ORDER BY created_at DESC LIMIT 1),
  qe AS (SELECT id FROM users WHERE email='qe@example.com')
INSERT INTO defect_rca (defect_id, problem_statement, root_cause, containment_action, why_analysis, contributing_factors, completed_by, completed_at)
SELECT
  d.id,
  'Scratches observed on finished part surfaces',
  'Improper handling during transfer between stations',
  'Added protective covers and retrained operators',
  '[\"Why 1: scratch occurred\", \"Why 2: part contacted fixture\", \"Why 3: transfer process lacks protection\"]'::jsonb,
  'Worn fixture edges',
  qe.id,
  now() - interval '1 day'
FROM d, qe
ON CONFLICT (defect_id) DO UPDATE SET
  problem_statement = EXCLUDED.problem_statement,
  root_cause = EXCLUDED.root_cause,
  containment_action = EXCLUDED.containment_action,
  why_analysis = EXCLUDED.why_analysis,
  contributing_factors = EXCLUDED.contributing_factors,
  completed_by = EXCLUDED.completed_by,
  completed_at = EXCLUDED.completed_at;

WITH
  d AS (SELECT id FROM defects ORDER BY created_at DESC LIMIT 1),
  r AS (SELECT id FROM defect_rca WHERE defect_id = (SELECT id FROM d)),
  sup AS (SELECT id FROM users WHERE email='supervisor@example.com'),
  qe AS (SELECT id FROM users WHERE email='qe@example.com')
INSERT INTO corrective_actions (defect_id, rca_id, title, description, owner_user_id, due_date, status, created_by, updated_by)
SELECT
  d.id,
  r.id,
  'Deburr/replace worn fixture edges',
  'Inspect fixture edges and replace/deburr to remove sharp contact points',
  sup.id,
  (CURRENT_DATE + INTERVAL '5 days')::date,
  'open'::action_status,
  qe.id,
  qe.id
FROM d, r, sup, qe
ON CONFLICT DO NOTHING;

COMMIT;
