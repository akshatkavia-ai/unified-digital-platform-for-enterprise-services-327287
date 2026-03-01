-- 001_init.sql
-- Minimal schema for Unified Digital Platform (UDP)
-- Focus: persistence for users/audit + core domain entities

BEGIN;

-- Enable useful extensions (uuid + citext for case-insensitive email)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "citext";

-- -------------------------
-- IAM: users
-- -------------------------
CREATE TABLE IF NOT EXISTS iam_users (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  email CITEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  mfa_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_iam_users_email ON iam_users (email);

-- -------------------------
-- Audit log
-- -------------------------
CREATE TABLE IF NOT EXISTS audit_log (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  actor_user_id UUID NULL REFERENCES iam_users(id) ON DELETE SET NULL,
  action TEXT NOT NULL,
  entity_type TEXT NULL,
  entity_id TEXT NULL,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  ip_address TEXT NULL,
  user_agent TEXT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_audit_log_created_at ON audit_log (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_log_action ON audit_log (action);
CREATE INDEX IF NOT EXISTS idx_audit_log_actor_user_id ON audit_log (actor_user_id);

-- -------------------------
-- Applications
-- -------------------------
CREATE TABLE IF NOT EXISTS applications (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  applicant_name TEXT NOT NULL,
  service_code TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'submitted',
  payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_by_user_id UUID NULL REFERENCES iam_users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_applications_service_code ON applications (service_code);
CREATE INDEX IF NOT EXISTS idx_applications_status ON applications (status);
CREATE INDEX IF NOT EXISTS idx_applications_created_at ON applications (created_at DESC);

-- -------------------------
-- Workflow tasks
-- -------------------------
CREATE TABLE IF NOT EXISTS workflow_tasks (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  title TEXT NOT NULL,
  description TEXT NULL,
  status TEXT NOT NULL DEFAULT 'open',
  application_id UUID NULL REFERENCES applications(id) ON DELETE SET NULL,
  assignee_user_id UUID NULL REFERENCES iam_users(id) ON DELETE SET NULL,
  created_by_user_id UUID NULL REFERENCES iam_users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_workflow_tasks_status ON workflow_tasks (status);
CREATE INDEX IF NOT EXISTS idx_workflow_tasks_application_id ON workflow_tasks (application_id);
CREATE INDEX IF NOT EXISTS idx_workflow_tasks_assignee_user_id ON workflow_tasks (assignee_user_id);

-- -------------------------
-- Documents metadata
-- -------------------------
CREATE TABLE IF NOT EXISTS documents_metadata (
  document_id TEXT PRIMARY KEY,
  filename TEXT NOT NULL,
  content_type TEXT NOT NULL,
  size_bytes BIGINT NOT NULL CHECK (size_bytes >= 0),
  tags TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  extra JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_by_user_id UUID NULL REFERENCES iam_users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_documents_metadata_created_at ON documents_metadata (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_documents_metadata_tags ON documents_metadata USING GIN (tags);
CREATE INDEX IF NOT EXISTS idx_documents_metadata_extra ON documents_metadata USING GIN (extra);

-- -------------------------
-- Tickets (helpdesk)
-- -------------------------
CREATE TABLE IF NOT EXISTS tickets (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  subject TEXT NOT NULL,
  description TEXT NOT NULL,
  category TEXT NULL,
  priority TEXT NOT NULL DEFAULT 'normal',
  status TEXT NOT NULL DEFAULT 'open',
  created_by_user_id UUID NULL REFERENCES iam_users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_tickets_status ON tickets (status);
CREATE INDEX IF NOT EXISTS idx_tickets_priority ON tickets (priority);
CREATE INDEX IF NOT EXISTS idx_tickets_created_at ON tickets (created_at DESC);

-- -------------------------
-- Inspections
-- -------------------------
CREATE TABLE IF NOT EXISTS inspections (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  application_id UUID NULL REFERENCES applications(id) ON DELETE SET NULL,
  location_text TEXT NULL,
  scheduled_at TIMESTAMPTZ NULL,
  status TEXT NOT NULL DEFAULT 'scheduled',
  created_by_user_id UUID NULL REFERENCES iam_users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_inspections_application_id ON inspections (application_id);
CREATE INDEX IF NOT EXISTS idx_inspections_status ON inspections (status);
CREATE INDEX IF NOT EXISTS idx_inspections_created_at ON inspections (created_at DESC);

-- -------------------------
-- Payments
-- -------------------------
CREATE TABLE IF NOT EXISTS payments (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  reference_type TEXT NOT NULL,
  reference_id TEXT NOT NULL,
  amount_paise BIGINT NOT NULL CHECK (amount_paise >= 0),
  currency TEXT NOT NULL DEFAULT 'INR',
  status TEXT NOT NULL DEFAULT 'created',
  gateway_redirect_url TEXT NULL,
  created_by_user_id UUID NULL REFERENCES iam_users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_payments_reference ON payments (reference_type, reference_id);
CREATE INDEX IF NOT EXISTS idx_payments_status ON payments (status);
CREATE INDEX IF NOT EXISTS idx_payments_created_at ON payments (created_at DESC);

COMMIT;
