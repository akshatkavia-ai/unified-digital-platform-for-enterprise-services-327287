-- 001_seed.sql
-- Minimal seed data (idempotent)

BEGIN;

-- Seed a demo user (password hash is just a placeholder; backend registration should create real hashes)
INSERT INTO iam_users (id, email, password_hash, is_active, mfa_enabled)
VALUES (
  '00000000-0000-0000-0000-000000000001',
  'demo@example.com',
  '$2b$12$stub.stub.stub.stub.stub.stub.stub.stub.stub.stubstub',
  TRUE,
  FALSE
)
ON CONFLICT (email) DO NOTHING;

-- Seed an example application
INSERT INTO applications (id, applicant_name, service_code, status, payload, created_by_user_id)
VALUES (
  '00000000-0000-0000-0000-000000000101',
  'Acme Industries',
  'CONFORMITY_CERT',
  'submitted',
  '{"notes":"Seeded application"}'::jsonb,
  '00000000-0000-0000-0000-000000000001'
)
ON CONFLICT (id) DO NOTHING;

-- Seed an example workflow task
INSERT INTO workflow_tasks (id, title, description, status, application_id, assignee_user_id, created_by_user_id)
VALUES (
  '00000000-0000-0000-0000-000000000201',
  'Review application',
  'Initial review of seeded application',
  'open',
  '00000000-0000-0000-0000-000000000101',
  '00000000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-000000000001'
)
ON CONFLICT (id) DO NOTHING;

-- Seed an example document metadata
INSERT INTO documents_metadata (document_id, filename, content_type, size_bytes, tags, extra, created_by_user_id)
VALUES (
  'doc_001',
  'certificate.pdf',
  'application/pdf',
  1024,
  ARRAY['certificate','final']::text[],
  '{"source":"seed"}'::jsonb,
  '00000000-0000-0000-0000-000000000001'
)
ON CONFLICT (document_id) DO NOTHING;

-- Seed an example ticket
INSERT INTO tickets (id, subject, description, category, priority, status, created_by_user_id)
VALUES (
  '00000000-0000-0000-0000-000000000301',
  'Unable to upload document',
  'The upload button shows an error. Please assist.',
  'documents',
  'normal',
  'open',
  '00000000-0000-0000-0000-000000000001'
)
ON CONFLICT (id) DO NOTHING;

-- Seed an example inspection
INSERT INTO inspections (id, application_id, location_text, scheduled_at, status, created_by_user_id)
VALUES (
  '00000000-0000-0000-0000-000000000401',
  '00000000-0000-0000-0000-000000000101',
  'Industrial Area, Sector 21',
  NOW() + INTERVAL '7 days',
  'scheduled',
  '00000000-0000-0000-0000-000000000001'
)
ON CONFLICT (id) DO NOTHING;

-- Seed an example payment
INSERT INTO payments (id, reference_type, reference_id, amount_paise, currency, status, gateway_redirect_url, created_by_user_id)
VALUES (
  '00000000-0000-0000-0000-000000000501',
  'application',
  '00000000-0000-0000-0000-000000000101',
  10000,
  'INR',
  'created',
  'https://example.invalid/pay',
  '00000000-0000-0000-0000-000000000001'
)
ON CONFLICT (id) DO NOTHING;

-- Seed an audit record
INSERT INTO audit_log (id, actor_user_id, action, entity_type, entity_id, metadata)
VALUES (
  '00000000-0000-0000-0000-000000000901',
  '00000000-0000-0000-0000-000000000001',
  'seed.init',
  'system',
  'seed',
  '{"note":"Seeded initial demo data"}'::jsonb
)
ON CONFLICT (id) DO NOTHING;

COMMIT;
