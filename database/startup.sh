#!/bin/bash

# Minimal PostgreSQL startup script with full paths
DB_NAME="myapp"
DB_USER="appuser"
DB_PASSWORD="dbuser123"
DB_PORT="5000"

echo "Starting PostgreSQL setup..."

# Find PostgreSQL version and set paths
PG_VERSION=$(ls /usr/lib/postgresql/ | head -1)
PG_BIN="/usr/lib/postgresql/${PG_VERSION}/bin"

echo "Found PostgreSQL version: ${PG_VERSION}"

# Check if PostgreSQL is already running on the specified port
if sudo -u postgres ${PG_BIN}/pg_isready -p ${DB_PORT} > /dev/null 2>&1; then
    echo "PostgreSQL is already running on port ${DB_PORT}!"
    echo "Database: ${DB_NAME}"
    echo "User: ${DB_USER}"
    echo "Port: ${DB_PORT}"
    echo ""
    echo "To connect to the database, use:"
    echo "psql -h localhost -U ${DB_USER} -d ${DB_NAME} -p ${DB_PORT}"
    
    # Check if connection info file exists
    if [ -f "db_connection.txt" ]; then
        echo "Or use: $(cat db_connection.txt)"
    fi
    
    echo ""
    echo "Script stopped - server already running."
    exit 0
fi

# Also check if there's a PostgreSQL process running (in case pg_isready fails)
if pgrep -f "postgres.*-p ${DB_PORT}" > /dev/null 2>&1; then
    echo "Found existing PostgreSQL process on port ${DB_PORT}"
    echo "Attempting to verify connection..."
    
    # Try to connect and verify the database exists
    if sudo -u postgres ${PG_BIN}/psql -p ${DB_PORT} -d ${DB_NAME} -c '\q' 2>/dev/null; then
        echo "Database ${DB_NAME} is accessible."
        echo "Script stopped - server already running."
        exit 0
    fi
fi

# Initialize PostgreSQL data directory if it doesn't exist
if [ ! -f "/var/lib/postgresql/data/PG_VERSION" ]; then
    echo "Initializing PostgreSQL..."
    sudo -u postgres ${PG_BIN}/initdb -D /var/lib/postgresql/data
fi

# Start PostgreSQL server in background
echo "Starting PostgreSQL server..."
sudo -u postgres ${PG_BIN}/postgres -D /var/lib/postgresql/data -p ${DB_PORT} &

# Wait for PostgreSQL to start
echo "Waiting for PostgreSQL to start..."
sleep 5

# Check if PostgreSQL is running
for i in {1..15}; do
    if sudo -u postgres ${PG_BIN}/pg_isready -p ${DB_PORT} > /dev/null 2>&1; then
        echo "PostgreSQL is ready!"
        break
    fi
    echo "Waiting... ($i/15)"
    sleep 2
done

# Create database and user
echo "Setting up database and user..."
sudo -u postgres ${PG_BIN}/createdb -p ${DB_PORT} ${DB_NAME} 2>/dev/null || echo "Database might already exist"

# Set up user and permissions with proper schema ownership
sudo -u postgres ${PG_BIN}/psql -p ${DB_PORT} -d postgres << EOF
-- Create user if doesn't exist
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${DB_USER}') THEN
        CREATE ROLE ${DB_USER} WITH LOGIN PASSWORD '${DB_PASSWORD}';
    END IF;
    ALTER ROLE ${DB_USER} WITH PASSWORD '${DB_PASSWORD}';
END
\$\$;

-- Grant database-level permissions
GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};

-- Connect to the specific database for schema-level permissions
\c ${DB_NAME}

-- For PostgreSQL 15+, we need to handle public schema permissions differently
-- First, grant usage on public schema
GRANT USAGE ON SCHEMA public TO ${DB_USER};

-- Grant CREATE permission on public schema
GRANT CREATE ON SCHEMA public TO ${DB_USER};

-- Make the user owner of all future objects they create in public schema
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO ${DB_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO ${DB_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO ${DB_USER};
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TYPES TO ${DB_USER};

-- If you want the user to be able to create objects without restrictions,
-- you can make them the owner of the public schema (optional but effective)
-- ALTER SCHEMA public OWNER TO ${DB_USER};

-- Alternative: Grant all privileges on schema public to the user
GRANT ALL ON SCHEMA public TO ${DB_USER};

-- Ensure the user can work with any existing objects
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO ${DB_USER};
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO ${DB_USER};
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO ${DB_USER};
EOF

# Additionally, connect to the specific database to ensure permissions
sudo -u postgres ${PG_BIN}/psql -p ${DB_PORT} -d ${DB_NAME} << EOF
-- Double-check permissions are set correctly in the target database
GRANT ALL ON SCHEMA public TO ${DB_USER};
GRANT CREATE ON SCHEMA public TO ${DB_USER};

-- Show current permissions for debugging
\dn+ public
EOF

# Save connection command to a file
echo "psql postgresql://${DB_USER}:${DB_PASSWORD}@localhost:${DB_PORT}/${DB_NAME}" > db_connection.txt
echo "Connection string saved to db_connection.txt"

# Save environment variables to a file
cat > db_visualizer/postgres.env << EOF
export POSTGRES_URL="postgresql://localhost:${DB_PORT}/${DB_NAME}"
export POSTGRES_USER="${DB_USER}"
export POSTGRES_PASSWORD="${DB_PASSWORD}"
export POSTGRES_DB="${DB_NAME}"
export POSTGRES_PORT="${DB_PORT}"
EOF

echo "Environment variables saved to db_visualizer/postgres.env"
echo "To use with Node.js viewer, run: source db_visualizer/postgres.env"
echo ""

# ---------------------------------------------------------------------------
# Schema / migration-like initialization (idempotent)
# Contract:
# - Inputs: DB_NAME, DB_USER, DB_PASSWORD, DB_PORT (from this script)
# - Side effects: Creates schemas/tables/indexes and inserts minimal seed data
# - Errors: Any SQL error will stop initialization and surface in logs
# - Invariants: All objects are created with IF NOT EXISTS; seeds use ON CONFLICT
# ---------------------------------------------------------------------------
echo "Initializing application schemas and seed data (idempotent)..."

CONN_URL="postgresql://${DB_USER}:${DB_PASSWORD}@localhost:${DB_PORT}/${DB_NAME}"

# Extensions
psql "${CONN_URL}" -c "CREATE EXTENSION IF NOT EXISTS pgcrypto;"

# Schemas
psql "${CONN_URL}" -c "CREATE SCHEMA IF NOT EXISTS iam;"
psql "${CONN_URL}" -c "CREATE SCHEMA IF NOT EXISTS app;"
psql "${CONN_URL}" -c "CREATE SCHEMA IF NOT EXISTS inspections;"
psql "${CONN_URL}" -c "CREATE SCHEMA IF NOT EXISTS billing;"
psql "${CONN_URL}" -c "CREATE SCHEMA IF NOT EXISTS documents;"
psql "${CONN_URL}" -c "CREATE SCHEMA IF NOT EXISTS audit;"

# IAM
psql "${CONN_URL}" -c "CREATE TABLE IF NOT EXISTS iam.tenants (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), slug text NOT NULL UNIQUE, name text NOT NULL, status text NOT NULL DEFAULT 'active', created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now());"
psql "${CONN_URL}" -c "CREATE TABLE IF NOT EXISTS iam.users (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), tenant_id uuid NOT NULL REFERENCES iam.tenants(id) ON DELETE CASCADE, email text NOT NULL, phone text, full_name text, password_hash text, is_email_verified boolean NOT NULL DEFAULT false, is_mfa_enabled boolean NOT NULL DEFAULT false, status text NOT NULL DEFAULT 'active', created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(), UNIQUE(tenant_id, email));"
psql "${CONN_URL}" -c "CREATE TABLE IF NOT EXISTS iam.roles (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), tenant_id uuid NOT NULL REFERENCES iam.tenants(id) ON DELETE CASCADE, code text NOT NULL, name text NOT NULL, description text, is_system boolean NOT NULL DEFAULT false, created_at timestamptz NOT NULL DEFAULT now(), UNIQUE(tenant_id, code));"
psql "${CONN_URL}" -c "CREATE TABLE IF NOT EXISTS iam.user_roles (user_id uuid NOT NULL REFERENCES iam.users(id) ON DELETE CASCADE, role_id uuid NOT NULL REFERENCES iam.roles(id) ON DELETE CASCADE, created_at timestamptz NOT NULL DEFAULT now(), PRIMARY KEY(user_id, role_id));"
psql "${CONN_URL}" -c "CREATE TABLE IF NOT EXISTS iam.sessions (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), tenant_id uuid NOT NULL REFERENCES iam.tenants(id) ON DELETE CASCADE, user_id uuid NOT NULL REFERENCES iam.users(id) ON DELETE CASCADE, issued_at timestamptz NOT NULL DEFAULT now(), expires_at timestamptz NOT NULL, revoked_at timestamptz, ip_address inet, user_agent text);"
psql "${CONN_URL}" -c "CREATE INDEX IF NOT EXISTS idx_users_tenant_email ON iam.users(tenant_id, email);"

# Applications + workflow/BPM primitives
psql "${CONN_URL}" -c "CREATE TABLE IF NOT EXISTS app.applications (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), tenant_id uuid NOT NULL REFERENCES iam.tenants(id) ON DELETE CASCADE, application_no text NOT NULL, applicant_user_id uuid REFERENCES iam.users(id) ON DELETE SET NULL, type_code text NOT NULL, title text NOT NULL, description text, status text NOT NULL DEFAULT 'draft', submitted_at timestamptz, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(), UNIQUE(tenant_id, application_no));"
psql "${CONN_URL}" -c "CREATE INDEX IF NOT EXISTS idx_applications_tenant_status ON app.applications(tenant_id, status);"
psql "${CONN_URL}" -c "CREATE TABLE IF NOT EXISTS app.workflow_definitions (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), tenant_id uuid NOT NULL REFERENCES iam.tenants(id) ON DELETE CASCADE, code text NOT NULL, name text NOT NULL, version int NOT NULL DEFAULT 1, definition jsonb NOT NULL DEFAULT '{}'::jsonb, is_active boolean NOT NULL DEFAULT true, created_at timestamptz NOT NULL DEFAULT now(), UNIQUE(tenant_id, code, version));"
psql "${CONN_URL}" -c "CREATE TABLE IF NOT EXISTS app.workflow_instances (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), tenant_id uuid NOT NULL REFERENCES iam.tenants(id) ON DELETE CASCADE, workflow_definition_id uuid NOT NULL REFERENCES app.workflow_definitions(id) ON DELETE RESTRICT, subject_type text NOT NULL, subject_id uuid NOT NULL, status text NOT NULL DEFAULT 'running', started_at timestamptz NOT NULL DEFAULT now(), completed_at timestamptz);"
psql "${CONN_URL}" -c "CREATE TABLE IF NOT EXISTS app.tasks (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), tenant_id uuid NOT NULL REFERENCES iam.tenants(id) ON DELETE CASCADE, workflow_instance_id uuid REFERENCES app.workflow_instances(id) ON DELETE SET NULL, application_id uuid REFERENCES app.applications(id) ON DELETE CASCADE, assigned_to_user_id uuid REFERENCES iam.users(id) ON DELETE SET NULL, task_type text NOT NULL, title text NOT NULL, status text NOT NULL DEFAULT 'open', due_at timestamptz, created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now());"

# Inspections
psql "${CONN_URL}" -c "CREATE TABLE IF NOT EXISTS inspections.inspections (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), tenant_id uuid NOT NULL REFERENCES iam.tenants(id) ON DELETE CASCADE, application_id uuid NOT NULL REFERENCES app.applications(id) ON DELETE CASCADE, scheduled_at timestamptz, started_at timestamptz, completed_at timestamptz, status text NOT NULL DEFAULT 'scheduled', inspector_user_id uuid REFERENCES iam.users(id) ON DELETE SET NULL, location text, notes text, created_at timestamptz NOT NULL DEFAULT now());"
psql "${CONN_URL}" -c "CREATE INDEX IF NOT EXISTS idx_inspections_app ON inspections.inspections(application_id);"
psql "${CONN_URL}" -c "CREATE TABLE IF NOT EXISTS inspections.findings (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), inspection_id uuid NOT NULL REFERENCES inspections.inspections(id) ON DELETE CASCADE, severity text NOT NULL DEFAULT 'info', code text, description text NOT NULL, created_at timestamptz NOT NULL DEFAULT now());"

# Billing (fees/invoices)
psql "${CONN_URL}" -c "CREATE TABLE IF NOT EXISTS billing.fee_schedules (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), tenant_id uuid NOT NULL REFERENCES iam.tenants(id) ON DELETE CASCADE, code text NOT NULL, name text NOT NULL, amount_paise bigint NOT NULL, currency text NOT NULL DEFAULT 'INR', is_active boolean NOT NULL DEFAULT true, created_at timestamptz NOT NULL DEFAULT now(), UNIQUE(tenant_id, code));"
psql "${CONN_URL}" -c "CREATE TABLE IF NOT EXISTS billing.invoices (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), tenant_id uuid NOT NULL REFERENCES iam.tenants(id) ON DELETE CASCADE, application_id uuid REFERENCES app.applications(id) ON DELETE SET NULL, invoice_no text NOT NULL, status text NOT NULL DEFAULT 'issued', total_amount_paise bigint NOT NULL DEFAULT 0, currency text NOT NULL DEFAULT 'INR', issued_at timestamptz NOT NULL DEFAULT now(), paid_at timestamptz, created_at timestamptz NOT NULL DEFAULT now(), UNIQUE(tenant_id, invoice_no));"
psql "${CONN_URL}" -c "CREATE TABLE IF NOT EXISTS billing.invoice_items (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), invoice_id uuid NOT NULL REFERENCES billing.invoices(id) ON DELETE CASCADE, fee_schedule_id uuid REFERENCES billing.fee_schedules(id) ON DELETE SET NULL, description text NOT NULL, quantity int NOT NULL DEFAULT 1, unit_amount_paise bigint NOT NULL DEFAULT 0, line_total_paise bigint NOT NULL DEFAULT 0);"

# Documents metadata
psql "${CONN_URL}" -c "CREATE TABLE IF NOT EXISTS documents.document_objects (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), tenant_id uuid NOT NULL REFERENCES iam.tenants(id) ON DELETE CASCADE, storage_provider text NOT NULL DEFAULT 'local', storage_key text NOT NULL, content_type text, byte_size bigint, checksum_sha256 text, created_at timestamptz NOT NULL DEFAULT now(), UNIQUE(tenant_id, storage_provider, storage_key));"
psql "${CONN_URL}" -c "CREATE TABLE IF NOT EXISTS documents.document_links (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), tenant_id uuid NOT NULL REFERENCES iam.tenants(id) ON DELETE CASCADE, document_object_id uuid NOT NULL REFERENCES documents.document_objects(id) ON DELETE CASCADE, subject_type text NOT NULL, subject_id uuid NOT NULL, label text, created_at timestamptz NOT NULL DEFAULT now());"

# Audit logs
psql "${CONN_URL}" -c "CREATE TABLE IF NOT EXISTS audit.audit_events (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), tenant_id uuid REFERENCES iam.tenants(id) ON DELETE SET NULL, actor_user_id uuid REFERENCES iam.users(id) ON DELETE SET NULL, event_type text NOT NULL, subject_type text, subject_id uuid, ip_address inet, user_agent text, metadata jsonb NOT NULL DEFAULT '{}'::jsonb, created_at timestamptz NOT NULL DEFAULT now());"

# Minimal deterministic seed data for vertical slice
psql "${CONN_URL}" -c "INSERT INTO iam.tenants (id, slug, name, status) VALUES ('00000000-0000-0000-0000-000000000001','default','Default Tenant','active') ON CONFLICT (slug) DO NOTHING;"
psql "${CONN_URL}" -c "INSERT INTO iam.roles (id, tenant_id, code, name, description, is_system) VALUES ('00000000-0000-0000-0000-000000000010','00000000-0000-0000-0000-000000000001','ADMIN','Administrator','Platform administrator', true) ON CONFLICT (tenant_id, code) DO NOTHING;"
psql "${CONN_URL}" -c "INSERT INTO iam.roles (id, tenant_id, code, name, description, is_system) VALUES ('00000000-0000-0000-0000-000000000011','00000000-0000-0000-0000-000000000001','APPLICANT','Applicant','External applicant user', true) ON CONFLICT (tenant_id, code) DO NOTHING;"
psql "${CONN_URL}" -c "INSERT INTO iam.roles (id, tenant_id, code, name, description, is_system) VALUES ('00000000-0000-0000-0000-000000000012','00000000-0000-0000-0000-000000000001','INSPECTOR','Inspector','Field inspector', true) ON CONFLICT (tenant_id, code) DO NOTHING;"
psql "${CONN_URL}" -c "INSERT INTO iam.users (id, tenant_id, email, full_name, password_hash, is_email_verified, is_mfa_enabled, status) VALUES ('00000000-0000-0000-0000-000000001000','00000000-0000-0000-0000-000000000001','admin@example.com','System Admin','<seeded>', true, false, 'active') ON CONFLICT (tenant_id, email) DO NOTHING;"
psql "${CONN_URL}" -c "INSERT INTO iam.user_roles (user_id, role_id) VALUES ('00000000-0000-0000-0000-000000001000','00000000-0000-0000-0000-000000000010') ON CONFLICT DO NOTHING;"

# Keep workflow definition minimal to avoid shell quoting issues; backend can update definition JSON later.
psql "${CONN_URL}" -c "INSERT INTO app.workflow_definitions (id, tenant_id, code, name, version, definition, is_active) VALUES ('00000000-0000-0000-0000-000000002000','00000000-0000-0000-0000-000000000001','APP_SUBMISSION','Application Submission Workflow',1,'{}'::jsonb,true) ON CONFLICT (tenant_id, code, version) DO NOTHING;"

psql "${CONN_URL}" -c "INSERT INTO app.applications (id, tenant_id, application_no, applicant_user_id, type_code, title, description, status, submitted_at) VALUES ('00000000-0000-0000-0000-000000003000','00000000-0000-0000-0000-000000000001','APP-0001','00000000-0000-0000-0000-000000001000','CONFORMITY','Sample Application','Seeded sample application','submitted', now()) ON CONFLICT (tenant_id, application_no) DO NOTHING;"
psql "${CONN_URL}" -c "INSERT INTO inspections.inspections (id, tenant_id, application_id, scheduled_at, status, inspector_user_id, location, notes) VALUES ('00000000-0000-0000-0000-000000004000','00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000003000', now() + interval '7 days','scheduled','00000000-0000-0000-0000-000000001000','HQ','Seeded inspection') ON CONFLICT DO NOTHING;"
psql "${CONN_URL}" -c "INSERT INTO billing.fee_schedules (id, tenant_id, code, name, amount_paise, currency, is_active) VALUES ('00000000-0000-0000-0000-000000005000','00000000-0000-0000-0000-000000000001','APP_FEE','Application Fee', 100000,'INR', true) ON CONFLICT (tenant_id, code) DO NOTHING;"
psql "${CONN_URL}" -c "INSERT INTO billing.invoices (id, tenant_id, application_id, invoice_no, status, total_amount_paise, currency) VALUES ('00000000-0000-0000-0000-000000005100','00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000003000','INV-0001','issued', 100000,'INR') ON CONFLICT (tenant_id, invoice_no) DO NOTHING;"

echo "Application schema initialization complete."
echo ""

echo "PostgreSQL setup complete!"
echo "Database: ${DB_NAME}"
echo "User: ${DB_USER}"
echo "Port: ${DB_PORT}"
echo ""

echo "To connect to the database, use one of the following commands:"
echo "psql -h localhost -U ${DB_USER} -d ${DB_NAME} -p ${DB_PORT}"
echo "$(cat db_connection.txt)"
