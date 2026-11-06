-- 001_initial_schema.sql
-- Cboog Smart Parking: PostgreSQL initial schema
-- Requires PostgreSQL 14+ (gen_random_uuid() is built in).

BEGIN;

CREATE TABLE roles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code VARCHAR(40) NOT NULL UNIQUE,
    name VARCHAR(80) NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT roles_code_format CHECK (code ~ '^[a-z][a-z0-9_]*$')
);

CREATE TABLE permissions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code VARCHAR(80) NOT NULL UNIQUE,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT permissions_code_format CHECK (code ~ '^[a-z][a-z0-9_]*([.][a-z][a-z0-9_]*)+$')
);

CREATE TABLE role_permissions (
    role_id UUID NOT NULL REFERENCES roles(id) ON UPDATE RESTRICT ON DELETE CASCADE,
    permission_id UUID NOT NULL REFERENCES permissions(id) ON UPDATE RESTRICT ON DELETE CASCADE,
    granted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (role_id, permission_id)
);
CREATE INDEX role_permissions_permission_id_idx ON role_permissions(permission_id);

CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    role_id UUID NOT NULL REFERENCES roles(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    email VARCHAR(254) NOT NULL,
    password_hash TEXT NOT NULL,
    full_name VARCHAR(160) NOT NULL,
    phone VARCHAR(30),
    status VARCHAR(20) NOT NULL DEFAULT 'active',
    email_verified_at TIMESTAMPTZ,
    last_login_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ,
    CONSTRAINT users_status_check CHECK (status IN ('active', 'inactive', 'locked', 'pending')),
    CONSTRAINT users_email_lowercase CHECK (email = LOWER(email))
);
CREATE UNIQUE INDEX users_email_active_uq ON users(email) WHERE deleted_at IS NULL;
CREATE INDEX users_role_id_idx ON users(role_id);
CREATE INDEX users_status_idx ON users(status);

CREATE TABLE parking_floors (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code VARCHAR(30) NOT NULL UNIQUE,
    name VARCHAR(100) NOT NULL,
    level_number INTEGER NOT NULL UNIQUE,
    description TEXT,
    display_order INTEGER NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE parking_zones (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    floor_id UUID NOT NULL REFERENCES parking_floors(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    code VARCHAR(40) NOT NULL,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    polygon JSONB,
    capacity INTEGER NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT parking_zones_capacity_check CHECK (capacity >= 0),
    CONSTRAINT parking_zones_floor_code_uq UNIQUE (floor_id, code),
    CONSTRAINT parking_zones_polygon_object CHECK (polygon IS NULL OR jsonb_typeof(polygon) IN ('object', 'array'))
);
CREATE INDEX parking_zones_floor_id_idx ON parking_zones(floor_id);

CREATE TABLE parking_spaces (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    zone_id UUID NOT NULL REFERENCES parking_zones(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    code VARCHAR(40) NOT NULL,
    space_type VARCHAR(30) NOT NULL DEFAULT 'standard',
    current_status VARCHAR(20) NOT NULL DEFAULT 'unknown',
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    position JSONB,
    last_seen_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT parking_spaces_type_check CHECK (space_type IN ('standard', 'accessible', 'ev', 'vip', 'motorcycle')),
    CONSTRAINT parking_spaces_status_check CHECK (current_status IN ('available', 'occupied', 'reserved', 'unknown', 'out_of_service')),
    CONSTRAINT parking_spaces_zone_code_uq UNIQUE (zone_id, code),
    CONSTRAINT parking_spaces_position_object CHECK (position IS NULL OR jsonb_typeof(position) = 'object')
);
CREATE INDEX parking_spaces_zone_status_idx ON parking_spaces(zone_id, current_status) WHERE is_active = TRUE;
CREATE INDEX parking_spaces_status_idx ON parking_spaces(current_status) WHERE is_active = TRUE;

CREATE TABLE vehicles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON UPDATE RESTRICT ON DELETE SET NULL,
    plate_number VARCHAR(30),
    plate_region VARCHAR(80),
    vehicle_type VARCHAR(30) NOT NULL DEFAULT 'car',
    color VARCHAR(40),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT vehicles_type_check CHECK (vehicle_type IN ('car', 'motorcycle', 'van', 'truck', 'other'))
);
CREATE UNIQUE INDEX vehicles_plate_uq ON vehicles(UPPER(plate_number), COALESCE(plate_region, '')) WHERE plate_number IS NOT NULL;
CREATE INDEX vehicles_user_id_idx ON vehicles(user_id);

CREATE TABLE camera_sources (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    floor_id UUID REFERENCES parking_floors(id) ON UPDATE RESTRICT ON DELETE SET NULL,
    zone_id UUID REFERENCES parking_zones(id) ON UPDATE RESTRICT ON DELETE SET NULL,
    code VARCHAR(60) NOT NULL UNIQUE,
    name VARCHAR(120) NOT NULL,
    source_type VARCHAR(20) NOT NULL DEFAULT 'cctv',
    status VARCHAR(20) NOT NULL DEFAULT 'inactive',
    configuration JSONB NOT NULL DEFAULT '{}'::jsonb,
    last_heartbeat_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT camera_sources_type_check CHECK (source_type IN ('cctv', 'video_file', 'test_stream', 'other')),
    CONSTRAINT camera_sources_status_check CHECK (status IN ('online', 'offline', 'inactive', 'error'))
);
CREATE INDEX camera_sources_zone_id_idx ON camera_sources(zone_id);

CREATE TABLE detection_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    camera_source_id UUID REFERENCES camera_sources(id) ON UPDATE RESTRICT ON DELETE SET NULL,
    parking_space_id UUID REFERENCES parking_spaces(id) ON UPDATE RESTRICT ON DELETE SET NULL,
    event_type VARCHAR(30) NOT NULL,
    detected_class VARCHAR(60),
    confidence NUMERIC(6,5),
    model_name VARCHAR(100),
    model_version VARCHAR(80),
    source_event_id VARCHAR(120),
    observed_at TIMESTAMPTZ NOT NULL,
    received_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    processed_at TIMESTAMPTZ,
    is_accepted BOOLEAN NOT NULL DEFAULT FALSE,
    rejection_reason TEXT,
    payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT detection_events_type_check CHECK (event_type IN ('vehicle_detected', 'space_available', 'space_occupied', 'space_reserved', 'no_detection', 'service_error')),
    CONSTRAINT detection_events_confidence_check CHECK (confidence IS NULL OR (confidence >= 0 AND confidence <= 1)),
    CONSTRAINT detection_events_payload_object CHECK (jsonb_typeof(payload) = 'object')
);
CREATE INDEX detection_events_observed_at_idx ON detection_events(observed_at DESC);
CREATE INDEX detection_events_space_time_idx ON detection_events(parking_space_id, observed_at DESC);
CREATE INDEX detection_events_camera_time_idx ON detection_events(camera_source_id, observed_at DESC);
CREATE UNIQUE INDEX detection_events_source_event_uq ON detection_events(camera_source_id, source_event_id)
    WHERE source_event_id IS NOT NULL;

CREATE TABLE occupancy_records (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    parking_space_id UUID NOT NULL REFERENCES parking_spaces(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    detection_event_id UUID REFERENCES detection_events(id) ON UPDATE RESTRICT ON DELETE SET NULL,
    status VARCHAR(20) NOT NULL,
    confidence NUMERIC(6,5),
    source VARCHAR(20) NOT NULL,
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT occupancy_records_status_check CHECK (status IN ('available', 'occupied', 'reserved', 'unknown', 'out_of_service')),
    CONSTRAINT occupancy_records_source_check CHECK (source IN ('ai', 'operator', 'system', 'import')),
    CONSTRAINT occupancy_records_confidence_check CHECK (confidence IS NULL OR (confidence >= 0 AND confidence <= 1))
);
CREATE INDEX occupancy_records_space_time_idx ON occupancy_records(parking_space_id, recorded_at DESC);
CREATE INDEX occupancy_records_recorded_at_idx ON occupancy_records(recorded_at DESC);

CREATE TABLE parking_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON UPDATE RESTRICT ON DELETE SET NULL,
    vehicle_id UUID REFERENCES vehicles(id) ON UPDATE RESTRICT ON DELETE SET NULL,
    parking_space_id UUID REFERENCES parking_spaces(id) ON UPDATE RESTRICT ON DELETE SET NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'active',
    started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    ended_at TIMESTAMPTZ,
    entry_reference VARCHAR(100),
    exit_reference VARCHAR(100),
    notes TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT parking_sessions_status_check CHECK (status IN ('active', 'completed', 'cancelled')),
    CONSTRAINT parking_sessions_time_check CHECK (ended_at IS NULL OR ended_at >= started_at)
);
CREATE INDEX parking_sessions_user_time_idx ON parking_sessions(user_id, started_at DESC);
CREATE INDEX parking_sessions_status_idx ON parking_sessions(status);
CREATE UNIQUE INDEX parking_sessions_one_active_space_uq ON parking_sessions(parking_space_id)
    WHERE status = 'active' AND parking_space_id IS NOT NULL;

CREATE TABLE exit_observations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    floor_id UUID REFERENCES parking_floors(id) ON UPDATE RESTRICT ON DELETE SET NULL,
    camera_source_id UUID REFERENCES camera_sources(id) ON UPDATE RESTRICT ON DELETE SET NULL,
    queue_length INTEGER,
    estimated_wait_seconds INTEGER,
    vehicle_flow_per_minute NUMERIC(10,2),
    congestion_level VARCHAR(20) NOT NULL,
    observed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    source VARCHAR(20) NOT NULL DEFAULT 'system',
    payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT exit_observations_queue_check CHECK (queue_length IS NULL OR queue_length >= 0),
    CONSTRAINT exit_observations_wait_check CHECK (estimated_wait_seconds IS NULL OR estimated_wait_seconds >= 0),
    CONSTRAINT exit_observations_flow_check CHECK (vehicle_flow_per_minute IS NULL OR vehicle_flow_per_minute >= 0),
    CONSTRAINT exit_observations_congestion_check CHECK (congestion_level IN ('low', 'moderate', 'high', 'critical', 'unknown')),
    CONSTRAINT exit_observations_source_check CHECK (source IN ('ai', 'operator', 'system', 'import'))
);
CREATE INDEX exit_observations_time_idx ON exit_observations(observed_at DESC);
CREATE INDEX exit_observations_level_time_idx ON exit_observations(congestion_level, observed_at DESC);

CREATE TABLE promotions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code VARCHAR(60) NOT NULL UNIQUE,
    title VARCHAR(160) NOT NULL,
    description TEXT,
    reward_type VARCHAR(30) NOT NULL,
    reward_value NUMERIC(12,2),
    starts_at TIMESTAMPTZ NOT NULL,
    ends_at TIMESTAMPTZ NOT NULL,
    trigger_congestion_levels TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    max_redemptions INTEGER,
    redemption_count INTEGER NOT NULL DEFAULT 0,
    status VARCHAR(20) NOT NULL DEFAULT 'draft',
    created_by UUID REFERENCES users(id) ON UPDATE RESTRICT ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT promotions_reward_type_check CHECK (reward_type IN ('percentage_discount', 'fixed_discount', 'points', 'coupon', 'other')),
    CONSTRAINT promotions_reward_value_check CHECK (reward_value IS NULL OR reward_value >= 0),
    CONSTRAINT promotions_dates_check CHECK (ends_at > starts_at),
    CONSTRAINT promotions_limits_check CHECK ((max_redemptions IS NULL OR max_redemptions >= 0) AND redemption_count >= 0),
    CONSTRAINT promotions_status_check CHECK (status IN ('draft', 'scheduled', 'active', 'paused', 'expired', 'archived')),
    CONSTRAINT promotions_trigger_levels_check CHECK (trigger_congestion_levels <@ ARRAY['low','moderate','high','critical']::TEXT[])
);
CREATE INDEX promotions_status_dates_idx ON promotions(status, starts_at, ends_at);

CREATE TABLE promotion_redemptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    promotion_id UUID NOT NULL REFERENCES promotions(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    user_id UUID NOT NULL REFERENCES users(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    redeemed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    redemption_code VARCHAR(100) NOT NULL UNIQUE,
    status VARCHAR(20) NOT NULL DEFAULT 'issued',
    used_at TIMESTAMPTZ,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    CONSTRAINT promotion_redemptions_status_check CHECK (status IN ('issued', 'used', 'expired', 'cancelled'))
);
CREATE INDEX promotion_redemptions_user_time_idx ON promotion_redemptions(user_id, redeemed_at DESC);
CREATE INDEX promotion_redemptions_promotion_idx ON promotion_redemptions(promotion_id);

CREATE TABLE eco_rewards (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON UPDATE RESTRICT ON DELETE RESTRICT,
    points_delta INTEGER NOT NULL,
    co2_saved_kg NUMERIC(12,4) NOT NULL DEFAULT 0,
    activity_type VARCHAR(40) NOT NULL,
    reference_type VARCHAR(40),
    reference_id UUID,
    description TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT eco_rewards_nonzero_check CHECK (points_delta <> 0 OR co2_saved_kg <> 0),
    CONSTRAINT eco_rewards_co2_check CHECK (co2_saved_kg >= 0)
);
CREATE INDEX eco_rewards_user_time_idx ON eco_rewards(user_id, created_at DESC);
CREATE INDEX eco_rewards_activity_idx ON eco_rewards(activity_type, created_at DESC);

CREATE TABLE system_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_user_id UUID REFERENCES users(id) ON UPDATE RESTRICT ON DELETE SET NULL,
    level VARCHAR(12) NOT NULL DEFAULT 'info',
    category VARCHAR(50) NOT NULL,
    action VARCHAR(100) NOT NULL,
    message TEXT NOT NULL,
    entity_type VARCHAR(60),
    entity_id UUID,
    ip_address INET,
    user_agent TEXT,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT system_logs_level_check CHECK (level IN ('debug', 'info', 'warning', 'error', 'critical'))
);
CREATE INDEX system_logs_created_at_idx ON system_logs(created_at DESC);
CREATE INDEX system_logs_category_time_idx ON system_logs(category, created_at DESC);
CREATE INDEX system_logs_actor_time_idx ON system_logs(actor_user_id, created_at DESC);

-- Keep updated_at consistent for mutable entities.
CREATE FUNCTION set_updated_at() RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER users_set_updated_at BEFORE UPDATE ON users FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER floors_set_updated_at BEFORE UPDATE ON parking_floors FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER zones_set_updated_at BEFORE UPDATE ON parking_zones FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER spaces_set_updated_at BEFORE UPDATE ON parking_spaces FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER vehicles_set_updated_at BEFORE UPDATE ON vehicles FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER cameras_set_updated_at BEFORE UPDATE ON camera_sources FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER promotions_set_updated_at BEFORE UPDATE ON promotions FOR EACH ROW EXECUTE FUNCTION set_updated_at();

COMMIT;
