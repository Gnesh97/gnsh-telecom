# gnsh-telecom

Standalone, server-authoritative GSM and telecom infrastructure for FiveM.

## Core and operations status

The foundation, authoritative tower domain, spatial index, basic coverage engine, dynamic tower selection, capacity/congestion engine, environment modifiers, service availability engine, player connection manager, public telecom API, isolated phone bridge layer, basic failure engine and ACE-protected admin debug tools are implemented. The resource boots without QBCore, Qbox, ESX or a phone resource. `TowerRegistry` validates tower definitions, stores immutable static configuration, and initializes isolated runtime state for every tower. `SpatialIndex` maps coverage-overlapping towers into configurable x/y grid cells and returns deterministic candidate lists. `Coverage` applies exact distance and operational-state filtering, `Signal` calculates the normalized distance score and applies server-configured environment and failure modifiers, `Selection` ranks candidates using signal, load, health and optional technology penalties, `Capacity` counts serving players and derives effective capacity, load and congestion effects, and `Services` evaluates voice, SMS, data, GPS and emergency independently. The server keeps one in-memory connection state per player and the client reports bounded position and environment context for reevaluation.

Selection weights are configurable under `Config.Selection`:

```lua
Config.Selection = {
    signalWeight = 1.0,
    loadPenaltyWeight = 0.25,
    healthPenaltyWeight = 0.20,
    technologyPenaltyWeight = 0.10,
}
```

Selection results include `scoreDetails` for server-side diagnostics. Set `Config.Debug.logLevel = 'debug'` to print a selected tower's score, signal, load and health when a player's connection changes.

Capacity thresholds and congestion effects are configurable under `Config.Capacity`:

```lua
Config.Capacity = {
    thresholds = {
        busy = 60,
        congested = 80,
        critical = 95,
        overloaded = 100,
    },
    -- effects are configured for NORMAL, BUSY, CONGESTED, CRITICAL and OVERLOADED
}
```

Capacity is server-authoritative. A connection move updates both affected towers, preserves `rawSignal`, and recalculates effective signal, data performance, call setup reliability and SMS delay without random behavior. Tower runtime state exposes `connectedClients`, `effectiveCapacity`, `loadPercent` and `congestion`.

Environment modifiers are configured under `Config.Environment`. The client reports only a known category and optional configured zone ID; the server ignores arbitrary multipliers, unknown categories and zone IDs that do not match the player's reported position. Multipliers are limited to `0.0`–`1.0`, so an environment cannot increase signal above the distance-based value:

```lua
Config.Environment = {
    default = 'OPEN_AREA',
    multipliers = {
        OPEN_AREA = 1.00,
        URBAN = 0.90,
        BUILDING = 0.75,
        UNDERGROUND = 0.55,
        TUNNEL = 0.45,
        SPECIAL_ZONE = 0.80,
    },
    zones = {
        {
            id = 'DOWNTOWN_TUNNEL',
            coords = vector3(100.0, 200.0, 30.0),
            radius = 150.0,
            category = 'TUNNEL',
        },
    },
}
```

The environment detector uses configured zones and does not run per-frame raycasts. The authoritative connection state includes `environment.category`, `environment.zoneId` and the server-derived `environment.multiplier`.

Service consumers can query the policy through the server API:

```lua
local available, state = Services.CanUse(source, 'voice')
```

Each service state includes `available`, `signal`, `minimumSignal`, `reason` and `blockedBy`. The current connection state is also sent to the client for debug inspection.

Public exports and integration event contracts are documented in [API.md](API.md). They expose safe copies and return documented fallback values for invalid or disconnected players.

Phone integrations are optional. `Config.PhoneBridge = 'auto'` detects `lb-phone`, NPWD or QS Smartphone when started, then falls back to the generic bridge. An unavailable explicit bridge also falls back safely. Bridge interfaces and custom adapter instructions are documented in [BRIDGES.md](BRIDGES.md).

Failure effects are server-authoritative and data-driven. `FailureEngine.Create(towerId, failureType)` supports basic and advanced types including `ANTENNA_FAILURE`, `RADIO_FAILURE`, `SECTOR_FAILURE`, `RADIO_UNIT_FAILURE`, `COOLING_FAILURE`, `FIBER_FAILURE`, `BACKHAUL_FAILURE`, `CONTROLLER_FAILURE`, `SOFTWARE_FAILURE` and `HARDWARE_DEGRADATION`. Effects combine multiplicatively, can take the backhaul offline independently of radio signal, update connected players and restore when cleared. Set `Config.Features.Failures = false` to neutralize the engine. Automatic failure scheduling is disabled by default through `Config.FailureScheduler.enabled = false`; only manual failure creation is active.

## Operations and advanced modules

The post-core modules are present but the gameplay-facing modules remain disabled by default. Enable only the module that the server is ready to configure:

- `Incidents` creates one operational ticket per active failure and validates the full `OPEN` → `ACKNOWLEDGED` → `ASSIGNED` → `ON_ROUTE` → `DIAGNOSING` → `REPAIRING` → `RESOLVED` → `CLOSED` lifecycle.
- `Technician` adds server-side diagnosis and repair workflow hooks. Framework, inventory, target and dispatch integrations are adapters; the core does not require any of them.
- `NOC` adds an ACE-protected `/telecomnoc` NUI snapshot with tower, incident, backhaul, jammer and telemetry summaries.
- `Handover` applies score hysteresis, candidate hold time and post-handover cooldown to prevent border ping-pong.
- `Backhaul` adds configurable nodes, links, core reachability and cached route status. Radio signal may remain strong while services are blocked by an offline path.
- `Sabotage` and `Jammers` are server-authoritative, rate-limited and disabled by default. Clients send a target request; they never choose an arbitrary failure effect or final interference state.
- `Statistics` aggregates load, handover, failure, incident, sabotage and jammer counters in memory and flushes summaries at a configured interval.

Configuration examples and security boundaries are documented in [CONFIGURATION.md](CONFIGURATION.md), [TECHNICIAN_CONFIGURATION.md](TECHNICIAN_CONFIGURATION.md), [NOC_GUIDE.md](NOC_GUIDE.md) and [SECURITY.md](SECURITY.md).

## Phase 13 persistence

Persistent state is configured under `Config.Persistence`:

```lua
Config.Persistence = {
    enabled = true,
    adapter = 'auto', -- auto, memory or oxmysql
    auditRetention = 200,
    maxPayloadBytes = 4096,
    maxRetries = 3,
    retryIntervalMs = 5000,
}
```

`auto` uses the optional `oxmysql` adapter when it is available and otherwise keeps telecom gameplay authoritative in memory. The resource does not require QBCore, a phone resource or oxmysql to start. With oxmysql on its supported MySQL/MariaDB database, migrations create `telecom_schema`, `telecom_failures` and `telecom_audit`; active failures and bounded audit history are restored before the resource publishes its started event. Invalid or stale rows are skipped individually and reported without aborting startup. Database outages keep current gameplay state in memory and retry queued writes when the database recovers.

Only active failure records and audit history are persisted. Current player signal, serving tower, player connections, tower occupancy, load counters, spatial-index state and debug load overrides are runtime state and are intentionally recreated after restart. SQL is isolated in the persistence adapter and uses bound parameters. The initial schema is also available at `server/persistence/schema/001_initial.sql`.

## Admin debug tools

The server commands below accept the ACE node configured in `Config.Debug.adminAce` (`gnsh-telecom.admin` by default), the existing `admin`, `god` or standard `command` ACE. Numeric and string player source IDs are supported, and the server console is always allowed. The resource also consumes txAdmin's server-side admin events, so a player who is an authenticated txAdmin admin can use the commands without a personal identifier or framework-specific permission file. They are intended for controlled single-player checks; the final multiplayer/load gate remains a separate runtime test.

For a portable installation, map the server's own admin group to the resource ACE in that server's `server.cfg` if it does not already grant `admin`, `god` or `command`:

```text
add_ace group.admin gnsh-telecom.admin allow
```

Do not copy another server's identifier lines. Keep each installation's own `add_principal`/admin-group mapping in its private server configuration. txAdmin panel membership and FiveM ACE are separate providers; the resource supports both. When only txAdmin membership is used, a player joining or an admin-permission update populates the runtime cache. If the resource is restarted while an already-connected admin remains online, reconnect that player or use the ACE fallback above so the state can be re-established immediately.

```text
/telecomdebug
/telecom tower <towerId>
/telecom towers
/telecom signal [playerId]
/telecom fail <towerId> <failureType>
/telecom repair <towerId>
/telecom technician <diagnose|diagnose_complete|diagnose_cancel|begin|complete|cancel> <incidentId|sessionId> [reason]
/telecomtech <diagnose|diagnose_complete|diagnose_cancel|begin|complete|cancel> <incidentId|sessionId> [reason]
/telecom load <towerId> <percent|clear>
/telecom noc
/telecomnoc
```

`/telecomdebug` toggles a client-only overlay. It is off by default and shows the current tower, distance, signal, capacity/congestion, environment, failure modifiers and alternative scores when those values are available. `/telecom load` is an in-memory test override and is cleared by restart or by using `clear`.

Production tower definitions belong in `config/towers.lua` under `Config.Towers`:

```lua
Config.Towers = {
    {
        id = 'LS_VIN_01',
        coords = vector3(250.0, -1000.0, 29.0),
        coverage = {
            radius = 1500.0,
            minimum = 50.0,
        },
        technologies = { '4G', '5G' },
        capacity = {
            maximum = 500,
        },
    },
}
```

Supported technologies are `EDGE`, `3G`, `4G` and `5G`. Duplicate IDs, invalid coordinates, coverage values, technologies or capacity prevent startup.

Production backhaul topology, if enabled, is also configured in `config/towers.lua`:

```lua
Config.Features.Backhaul = true
Config.Backhaul.towerNodes = {
    LS_VIN_01 = 'AGG-LS-01',
}
Config.Backhaul.coreNodes = { 'CORE-01' }
Config.Backhaul.nodes = {
    { id = 'AGG-LS-01', type = 'AGGREGATION' },
    { id = 'CORE-01', type = 'CORE' },
}
Config.Backhaul.links = {
    { id = 'LINK-LS', from = 'LS_VIN_01', to = 'AGG-LS-01', type = 'FIBER' },
    { id = 'LINK-CORE', from = 'AGG-LS-01', to = 'CORE-01', type = 'FIBER' },
}
```

Production defaults contain no towers and no test backhaul nodes. Development fixtures live in `config/examples/towers.lua`; `config/development.lua` is an optional development overlay and is not loaded by the production manifest.

## Start

Add the resource to `server.cfg`:

```text
ensure gnsh-telecom
```

No framework or phone dependency is required.

## Tests

Pure Lua tests run with Lua 5.4:

```text
lua5.4 tests/run.lua
```

FiveM runtime behavior is verified separately through resource start/restart/stop smoke tests.

For a development smoke test, load `config/examples/towers.lua` followed by `config/development.lua` in a development-only manifest. The client F8 console then reports serving tower, effective signal, signal level, technology, per-service availability, congestion, load, environment, failure modifiers and jammer interference whenever the authoritative connection state changes. Restore the production manifest after testing. FiveM runtime behavior and the multiplayer/load gate remain a `DEFERRED MULTIPLAYER GATE` for this phase.
