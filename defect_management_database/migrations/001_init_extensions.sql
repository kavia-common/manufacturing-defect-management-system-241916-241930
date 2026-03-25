-- Migration 001: Initialize extensions used by the schema.
-- Idempotent (safe to re-run).

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "citext";
