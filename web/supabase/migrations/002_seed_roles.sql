-- Seed: Role hierarchy
-- guest -> user -> admin -> superadmin
-- Idempotent: uses ON CONFLICT DO NOTHING

INSERT INTO rbac.roles (name, parent_id, description) VALUES
  ('guest', NULL, 'Unauthenticated visitor with read-only access')
  ON CONFLICT (name) DO NOTHING;

INSERT INTO rbac.roles (name, parent_id, description)
  SELECT 'user', id, 'Authenticated user with standard operational access'
  FROM rbac.roles WHERE name = 'guest'
  ON CONFLICT (name) DO NOTHING;

INSERT INTO rbac.roles (name, parent_id, description)
  SELECT 'admin', id, 'Administrator with full configuration and user management'
  FROM rbac.roles WHERE name = 'user'
  ON CONFLICT (name) DO NOTHING;

INSERT INTO rbac.roles (name, parent_id, description)
  SELECT 'superadmin', id, 'Super administrator with unrestricted system access'
  FROM rbac.roles WHERE name = 'admin'
  ON CONFLICT (name) DO NOTHING;
