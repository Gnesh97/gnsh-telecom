# Changelog

All notable changes to gnsh-telecom are recorded here. The dev branch contains
unreleased work. The 0.1.0-rc.1 entry is a release-candidate baseline, not a
production release.

## Unreleased — dev

These changes are currently on dev after the release-candidate preparation.

### Added

- Added reusable tower deployment archetypes and coverage policy labels for
  metro, town, rural, highway, remote and intentional weak-service areas.
  ([b37346a](https://github.com/Gnesh97/gnsh-telecom/commit/b37346a))
- Added the development deployment editor, editable draft placement map and
  verified production-capture workflow.
  ([fed7052](https://github.com/Gnesh97/gnsh-telecom/commit/fed7052),
  [37ed891](https://github.com/Gnesh97/gnsh-telecom/commit/37ed891))
- Added production tower coverage rendering, verified capture import and
  requested coverage sites.
  ([9ba0903](https://github.com/Gnesh97/gnsh-telecom/commit/9ba0903),
  [85ffb8c](https://github.com/Gnesh97/gnsh-telecom/commit/85ffb8c),
  [34f7819](https://github.com/Gnesh97/gnsh-telecom/commit/34f7819))
- Added server-authoritative coverage sampling, heatmap, signal inspection and
  deterministic coverage expectations.
  ([fec9c22](https://github.com/Gnesh97/gnsh-telecom/commit/fec9c22),
  [e9baa26](https://github.com/Gnesh97/gnsh-telecom/commit/e9baa26))

### Changed

- Tuned urban, town, highway and wilderness coverage behavior using verified
  captures and intentional weak-zone expectations.
  ([fcc6d1e](https://github.com/Gnesh97/gnsh-telecom/commit/fcc6d1e),
  [c360f58](https://github.com/Gnesh97/gnsh-telecom/commit/c360f58))

### Fixed

- Corrected coverage-radius exposure, pause-map rendering, native radius
  preservation, numeric coercion and a custom highway site position.
  ([0f66e90](https://github.com/Gnesh97/gnsh-telecom/commit/0f66e90),
  [9b55df7](https://github.com/Gnesh97/gnsh-telecom/commit/9b55df7),
  [1f1f440](https://github.com/Gnesh97/gnsh-telecom/commit/1f1f440),
  [ea88f77](https://github.com/Gnesh97/gnsh-telecom/commit/ea88f77),
  [a07b7c6](https://github.com/Gnesh97/gnsh-telecom/commit/a07b7c6))

### Tests and documentation

- Added San Andreas anchor checks, verified wilderness captures, weak-zone
  expectations and final coverage balancing evidence.
  ([876c043](https://github.com/Gnesh97/gnsh-telecom/commit/876c043),
  [9ac5355](https://github.com/Gnesh97/gnsh-telecom/commit/9ac5355),
  [58d06a6](https://github.com/Gnesh97/gnsh-telecom/commit/58d06a6))
- Recorded deployment-track verification and draft-map state during the
  coverage rollout.
  ([2ff30ef](https://github.com/Gnesh97/gnsh-telecom/commit/2ff30ef),
  [bfeddc3](https://github.com/Gnesh97/gnsh-telecom/commit/bfeddc3),
  [9597c29](https://github.com/Gnesh97/gnsh-telecom/commit/9597c29),
  [d2cc06f](https://github.com/Gnesh97/gnsh-telecom/commit/d2cc06f))
- Consolidated installation, configuration, API, integration, security,
  compatibility and operations documentation into README.md.
  ([ebf390f](https://github.com/Gnesh97/gnsh-telecom/commit/ebf390f))
- Removed duplicated standalone guide files and internal documentation reports.
  ([175cf28](https://github.com/Gnesh97/gnsh-telecom/commit/175cf28))

## 0.1.0-rc.1 — 2026-08-17

Release-candidate packaging for the telecom foundation, universal integrations
and operations milestone. This is not a production release until real FiveM
runtime, provider-version, restart, clean-install and multiplayer evidence is
recorded.

### Added

- Added the universal bridge platform with lifecycle-safe provider contracts,
  health reporting and deterministic fallback.
  ([4138457](https://github.com/Gnesh97/gnsh-telecom/commit/4138457),
  [d60cfbc](https://github.com/Gnesh97/gnsh-telecom/commit/d60cfbc))
- Added standalone, QBCore, Qbox, ESX and custom framework bridges.
  ([334f592](https://github.com/Gnesh97/gnsh-telecom/commit/334f592))
- Added universal inventory, target, phone, notify, progress and dispatch
  adapters, including provider enforcement and restart-safe lifecycle handling.
  ([df13f15](https://github.com/Gnesh97/gnsh-telecom/commit/df13f15),
  [d71747b](https://github.com/Gnesh97/gnsh-telecom/commit/d71747b),
  [d9be47d](https://github.com/Gnesh97/gnsh-telecom/commit/d9be47d),
  [dc8d7af](https://github.com/Gnesh97/gnsh-telecom/commit/dc8d7af),
  [021e730](https://github.com/Gnesh97/gnsh-telecom/commit/021e730))
- Added client technician workflows and advanced maintenance gameplay with
  work orders, diagnostics, repairs and verification.
  ([1096402](https://github.com/Gnesh97/gnsh-telecom/commit/1096402),
  [9ff0938](https://github.com/Gnesh97/gnsh-telecom/commit/9ff0938))
- Added live NOC v2 and regional tower-to-core backhaul topology.
  ([919a983](https://github.com/Gnesh97/gnsh-telecom/commit/919a983),
  [189bbe5](https://github.com/Gnesh97/gnsh-telecom/commit/189bbe5))
- Added sector-aware cellular architecture, dynamic technology fallback and
  cascading outage propagation.
  ([cc6a84d](https://github.com/Gnesh97/gnsh-telecom/commit/cc6a84d),
  [a1f0ed5](https://github.com/Gnesh97/gnsh-telecom/commit/a1f0ed5),
  [c4c9fae](https://github.com/Gnesh97/gnsh-telecom/commit/c4c9fae))
- Added optional multi-operator support, subscriber/roaming simulation,
  telecom service sessions and configurable QoS prioritization.
  ([89ac671](https://github.com/Gnesh97/gnsh-telecom/commit/89ac671),
  [ef5c1c6](https://github.com/Gnesh97/gnsh-telecom/commit/ef5c1c6),
  [994ee92](https://github.com/Gnesh97/gnsh-telecom/commit/994ee92),
  [ea0aa7b](https://github.com/Gnesh97/gnsh-telecom/commit/ea0aa7b))
- Added the custom bridge registration SDK with ownership, capability,
  lifecycle and cleanup controls.
  ([0f1a542](https://github.com/Gnesh97/gnsh-telecom/commit/0f1a542))

### Fixed and hardened

- Hardened v1.0 release boundaries and server-authoritative gameplay trust
  boundaries.
  ([770e325](https://github.com/Gnesh97/gnsh-telecom/commit/770e325),
  [37d16ba](https://github.com/Gnesh97/gnsh-telecom/commit/37d16ba))
- Cleaned external session owners on resource stop and reconciled optional
  carrier state safely.
  ([c026610](https://github.com/Gnesh97/gnsh-telecom/commit/c026610),
  [bf58e22](https://github.com/Gnesh97/gnsh-telecom/commit/bf58e22))

### Validation and release process

- Added synthetic scale validation and the universal provider compatibility
  matrix with conservative EXPERIMENTAL labels.
  ([4e297cf](https://github.com/Gnesh97/gnsh-telecom/commit/4e297cf),
  [d212aff](https://github.com/Gnesh97/gnsh-telecom/commit/d212aff))
- Prepared the 0.1.0-rc.1 release-candidate package.
  ([5f42e18](https://github.com/Gnesh97/gnsh-telecom/commit/5f42e18))

## 0.1.0 — Foundation history

### Added

- Added the FiveM resource foundation, configuration system, localization,
  bootstrap validation, tower registry and spatial index.
- Added coverage, player connection lifecycle, dynamic tower selection,
  capacity/congestion, environment signal modifiers and service availability.
- Added the public telecom API, defensive state snapshots and integration
  events.
- Added optional phone bridges, the failure engine, ACE-protected admin/debug
  tools, persistence and operational modules.
- Added handover, incidents, technician workflows, backhaul, sabotage, jammers,
  statistics and the NOC foundation.

The foundation history is preserved here as a product summary; the detailed
implementation remains available through Git history.
