-- Development-only seed data. Do not use these records as live mall inventory.
BEGIN;

INSERT INTO roles (code, name, description) VALUES
 ('super_admin', 'Super Admin', 'Full system administration access'),
 ('admin', 'Admin', 'Manage parking operations and business settings'),
 ('operator', 'Operator', 'Monitor parking and handle operational updates'),
 ('viewer', 'Viewer', 'Read-only access to dashboards and reports')
ON CONFLICT (code) DO NOTHING;

INSERT INTO permissions (code, description) VALUES
 ('dashboard.read', 'View dashboard metrics'),
 ('parking.read', 'View parking floors, zones, and spaces'),
 ('parking.write', 'Update parking occupancy and space records'),
 ('zones.manage', 'Create and manage parking floors and zones'),
 ('ai.ingest', 'Submit authenticated AI detection observations'),
 ('traffic.read', 'View exit traffic observations'),
 ('promotions.read', 'View promotional campaigns'),
 ('promotions.manage', 'Create and manage promotional campaigns'),
 ('rewards.read', 'View Eco-Rewards ledger and reports'),
 ('rewards.manage', 'Adjust Eco-Rewards under audited workflows'),
 ('users.manage', 'Manage users and role assignments'),
 ('reports.read', 'View and export operational reports'),
 ('logs.read', 'View system and audit logs'),
 ('system.manage', 'Manage system-wide configuration')
ON CONFLICT (code) DO NOTHING;

-- Development role grants. Production grants must be reviewed before deployment.
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r
JOIN permissions p ON
    r.code = 'super_admin'
    OR (r.code = 'admin' AND p.code <> 'system.manage')
    OR (r.code = 'operator' AND p.code IN ('dashboard.read','parking.read','parking.write','ai.ingest','traffic.read','promotions.read','rewards.read'))
    OR (r.code = 'viewer' AND p.code IN ('dashboard.read','parking.read','traffic.read','promotions.read','rewards.read','reports.read'))
ON CONFLICT DO NOTHING;

INSERT INTO parking_floors (code, name, level_number, description, display_order)
VALUES ('B1', 'Basement 1', -1, 'Development sample floor', 1)
ON CONFLICT (code) DO NOTHING;

WITH floor_row AS (
    SELECT id FROM parking_floors WHERE code = 'B1'
)
INSERT INTO parking_zones (floor_id, code, name, description, capacity)
SELECT floor_row.id, z.code, z.name, 'Development seed zone; replace with surveyed mall layout', z.capacity
FROM floor_row
CROSS JOIN (VALUES
    ('B1-A', 'Zone A', 4),
    ('B1-B', 'Zone B', 4),
    ('B1-C', 'Zone C', 4)
) AS z(code, name, capacity)
ON CONFLICT (floor_id, code) DO NOTHING;

INSERT INTO parking_spaces (zone_id, code, current_status)
SELECT z.id, s.code, 'unknown'
FROM parking_zones z
CROSS JOIN LATERAL (
    SELECT z.code || '-' || LPAD(n::text, 2, '0') AS code
    FROM generate_series(1, 4) AS n
) s
WHERE z.code IN ('B1-A', 'B1-B', 'B1-C')
ON CONFLICT (zone_id, code) DO NOTHING;

INSERT INTO promotions (
    code, title, description, reward_type, reward_value,
    starts_at, ends_at, trigger_congestion_levels, status
)
VALUES (
    'DEV-EXIT-10', 'Development Exit Delay Offer',
    'Sample campaign for local development only',
    'percentage_discount', 10,
    NOW(), NOW() + INTERVAL '30 days',
    ARRAY['high', 'critical'], 'draft'
)
ON CONFLICT (code) DO NOTHING;

COMMIT;
