-- Seed 001: Master/config data. Safe to re-run using ON CONFLICT.

BEGIN;

-- Roles
INSERT INTO roles (name, description)
VALUES
  ('quality_engineer', 'Quality engineer with full defect/RCA/action privileges'),
  ('production_supervisor', 'Supervisor who can log defects and manage actions'),
  ('operator', 'Operator who can log defects')
ON CONFLICT (name) DO UPDATE SET description = EXCLUDED.description;

-- Lines
INSERT INTO config_lines (code, name, plant, is_active)
VALUES
  ('LINE_A', 'Line A', 'Plant 1', true),
  ('LINE_B', 'Line B', 'Plant 1', true)
ON CONFLICT (code) DO UPDATE SET name = EXCLUDED.name, plant = EXCLUDED.plant, is_active = EXCLUDED.is_active;

-- Shifts (example)
INSERT INTO config_shifts (code, name, start_time, end_time, is_active)
VALUES
  ('SHIFT_1', 'Shift 1', '06:00', '14:00', true),
  ('SHIFT_2', 'Shift 2', '14:00', '22:00', true),
  ('SHIFT_3', 'Shift 3', '22:00', '06:00', true)
ON CONFLICT (code) DO UPDATE SET name = EXCLUDED.name, start_time = EXCLUDED.start_time, end_time = EXCLUDED.end_time, is_active = EXCLUDED.is_active;

-- Parts
INSERT INTO config_parts (part_no, name, customer, is_active)
VALUES
  ('P-1000', 'Widget 1000', 'Acme', true),
  ('P-2000', 'Widget 2000', 'Acme', true)
ON CONFLICT (part_no) DO UPDATE SET name = EXCLUDED.name, customer = EXCLUDED.customer, is_active = EXCLUDED.is_active;

-- Defect types
INSERT INTO config_defect_types (code, name, category, is_active)
VALUES
  ('SCRATCH', 'Scratch', 'Cosmetic', true),
  ('CRACK', 'Crack', 'Structural', true),
  ('MISSING_PART', 'Missing Part', 'Assembly', true),
  ('MISALIGN', 'Misalignment', 'Assembly', true)
ON CONFLICT (code) DO UPDATE SET name = EXCLUDED.name, category = EXCLUDED.category, is_active = EXCLUDED.is_active;

COMMIT;
