CREATE TABLE IF NOT EXISTS telecom_schema (
    version INT NOT NULL PRIMARY KEY,
    applied_at BIGINT NOT NULL
);

CREATE TABLE IF NOT EXISTS telecom_failures (
    id VARCHAR(64) NOT NULL PRIMARY KEY,
    tower_id VARCHAR(64) NOT NULL,
    failure_type VARCHAR(64) NOT NULL,
    active TINYINT NOT NULL,
    created_at BIGINT NOT NULL,
    source BIGINT NULL,
    reason VARCHAR(512) NULL,
    metadata_json TEXT NOT NULL,
    updated_at BIGINT NOT NULL,
    INDEX idx_telecom_failures_tower_active (tower_id, active)
);

CREATE TABLE IF NOT EXISTS telecom_audit (
    id VARCHAR(64) NOT NULL PRIMARY KEY,
    source BIGINT NOT NULL,
    action VARCHAR(128) NOT NULL,
    details_json TEXT NOT NULL,
    timestamp BIGINT NOT NULL,
    INDEX idx_telecom_audit_timestamp (timestamp, id)
);

CREATE TABLE IF NOT EXISTS telecom_subscribers (
    player_id VARCHAR(128) NOT NULL PRIMARY KEY,
    sim_id VARCHAR(64) NOT NULL UNIQUE,
    carrier_id VARCHAR(64) NOT NULL,
    roaming_allowed TINYINT NOT NULL,
    service_class VARCHAR(32) NOT NULL,
    INDEX idx_telecom_subscribers_carrier (carrier_id)
);
