# Database design notes

## Relationship overview

- One role has many users; each user has one role. Roles and permissions are many-to-many through `role_permissions`.
- One floor has many zones; each zone has many parking spaces.
- A space has many occupancy history records and detection events.
- A camera source can observe a floor/zone and produce many detection events.
- A user can own multiple vehicles and create multiple parking sessions.
- A promotion has many redemptions; each redemption belongs to one user.
- Eco-rewards are ledger entries belonging to a user.
- Exit observations are timestamped observations optionally associated with a floor and camera.

## Why both detection_events and occupancy_records?

`detection_events` is the immutable-ish intake/audit record of what the AI service reported, including confidence, model version, payload, and whether the backend accepted it. `occupancy_records` records state observations used for historical analytics. The API will create/update these in one transaction after validation and confidence/stability rules. This prevents a low-confidence single frame from silently changing the operational state.

## RBAC

`roles` stores the four built-in role identities. `permissions` stores granular capability codes, and `role_permissions` maps capabilities to roles. The seed grants broad permissions to `super_admin`, operational permissions to `operator`, and read-only permissions to `viewer`. These grants are development defaults and must be reviewed for production.

## Current state vs history

`parking_spaces.current_status` is a materialized current-state field for fast reads. `occupancy_records` is append-only history. A future API transaction must update the current state and insert its history record together.

## Reservation and active session constraints

The initial schema includes `reserved` as a valid space state. A future reservation workflow may add a dedicated `parking_reservations` table if confirmed reservation lifecycle, expiry, and payment are required. A partial unique index prevents two active parking sessions from occupying the same space.

## Future extension points

- `camera_sources.configuration` stores camera integration metadata without putting credentials in the database.
- `detection_events.model_name/model_version` support model upgrades and comparison.
- `payload` JSONB columns preserve additional vendor/model metadata without frequent schema changes.
- `eco_rewards` is a ledger (positive or negative points delta) rather than a mutable balance. Balance is calculated by summing entries.
- `promotion_redemptions` tracks coupon issuance and use separately from campaign configuration.
