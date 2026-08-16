# Changelog

## 0.1.0 - Unreleased

- Added standalone FiveM resource foundation.
- Added centralized configuration, enums, feature flags, utilities and localization.
- Added server/client bootstrap and configuration validation.
- Added tower validation, deterministic static registry and isolated runtime tower state.
- Added configurable spatial index with neighboring-cell coverage mapping, candidate statistics and atomic rebuilds.
- Added pure distance-based raw signal calculation and exact coverage candidate filtering.
- Added authoritative per-player connection lifecycle, reevaluation and client position reporting.
- Added debug output for client-side connection state changes.
- Added dynamic tower scoring with configurable signal, load, health and technology weighting.
- Added deterministic candidate ranking, offline exclusion and selection debug details.
- Added independent service availability evaluation for voice, SMS, data, GPS and emergency.
- Added structured service blocking reasons and the `Services.CanUse` query API.
- Added server-authoritative capacity accounting per serving tower.
- Added configurable load thresholds, congestion states and deterministic congestion effects.
- Added effective signal, data performance, call setup reliability and SMS delay metadata.
- Added server-authoritative environment categories, configurable signal multiplier zones and bounded client environment reporting.
- Added environment validation that rejects unknown categories, malformed zones and signal-gain multipliers.
- Added versioned public telecom exports for signal, network, tower and service queries.
- Added server-side connection, signal, tower, network type and service change events with defensive snapshots.
- Added optional generic, LB Phone, NPWD, QS Smartphone and custom bridge adapters with safe detection and generic fallback.
- Added custom phone bridge interface documentation.
- Added data-driven basic failure engine with antenna, radio, cooling and hardware degradation effects.
- Added deterministic multi-failure aggregation, manual clear/restore and disabled-feature behavior.
- Added automatic failure scheduler stub disabled by default.
- Added ACE-protected admin debug commands for tower, player, NOC, failure and load inspection.
- Added in-memory tower load overrides for controlled single-player congestion checks.
- Added audit records for successful admin debug actions.
- Added an opt-in client debug overlay with signal, capacity, environment and failure telemetry.
- Added framework-free pure Lua test harness.
