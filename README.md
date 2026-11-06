# Smart-M-Flow-website

# Cboog Smart Parking — Phase 2 / Milestone 1

This milestone delivers the PostgreSQL schema, initial migration, development seed data, and a local PostgreSQL container definition. It does **not** yet include the Express API, authentication, live AI integration, or Socket.IO; those are subsequent milestones.

## Requirements

- Docker Desktop with Docker Compose, or PostgreSQL 14+ installed locally.
- PostgreSQL 16 is used by the supplied Compose configuration.

## Start the development database (Docker)

```bash
cp .env.example .env
# Edit .env and set a local password.
docker compose up -d
docker compose ps
```

The migration and development seed are automatically applied only when the PostgreSQL data volume is first initialized.

Connect using:

```bash
docker compose exec postgres psql -U cboog_app -d cboog_smart_parking
```

Check tables:

```sql
\dt
SELECT code, name, level_number FROM parking_floors;
SELECT z.code, COUNT(s.id) AS spaces
FROM parking_zones z
LEFT JOIN parking_spaces s ON s.zone_id = z.id
GROUP BY z.id, z.code
ORDER BY z.code;
```

## Run SQL manually (existing PostgreSQL)

Create a database and role using your own secure credentials, then:

```bash
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f database/migrations/001_initial_schema.sql
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f database/seeds/001_development_seed.sql
```

Do not apply the seed script to production. Seeded parking inventory is illustrative, starts with `unknown` status, and is not actual mall inventory.

## Data model

| Table | Purpose |
|---|---|
| `roles`, `users` | Identity and role assignment |\n| `permissions`, `role_permissions` | Fine-grained RBAC capability mapping |
| `parking_floors`, `parking_zones`, `parking_spaces` | Physical parking hierarchy and current space state |
| `vehicles`, `parking_sessions` | Customer vehicles and parking sessions |
| `camera_sources` | CCTV/video source registry for the future detector |
| `detection_events` | Raw, timestamped detector events and acceptance state |
| `occupancy_records` | Append-only history of accepted occupancy observations |
| `exit_observations` | Exit queue and congestion observations |
| `promotions`, `promotion_redemptions` | Campaign configuration and customer redemptions |
| `eco_rewards` | Append-only points and CO₂ ledger |
| `system_logs` | Operational and administrative audit events |

## Important implementation rules

1. `parking_spaces.current_status` is the latest accepted state for fast dashboard reads.
2. `occupancy_records` is the historical timeline. It is not overwritten when a space changes.
3. `detection_events` stores raw incoming observations, including rejected or low-confidence events.
4. The detector must never write directly to PostgreSQL. In the next milestone it will authenticate to a dedicated backend endpoint; the API will validate and persist events transactionally.
5. All timestamps are `TIMESTAMPTZ`; API clients should send ISO-8601 timestamps and the backend should normalize to UTC.
6. Role codes are `super_admin`, `admin`, `operator`, and `viewer`. Fine-grained role-permission mapping will be added with the RBAC API milestone.
7. The `users.password_hash` column stores only a password hash (Argon2id recommended for the API milestone), never a plaintext password.

## Reset local development database

This destroys the local database volume and all data in it:

```bash
docker compose down -v
docker compose up -d
```

Never run `down -v` against a database containing data you need.

## Production hardening still required

Before production: managed database or hardened PostgreSQL host, TLS, encrypted backups and restore drills, least-privilege database roles, secrets management, migration history/runner, monitoring, retention policies, and a reviewed threat model.
