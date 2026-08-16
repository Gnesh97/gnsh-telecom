# gnsh-telecom

Standalone, server-authoritative GSM and telecom infrastructure for FiveM.

## Phase 8 status

The foundation, authoritative tower domain, spatial index, basic coverage engine, dynamic tower selection, capacity/congestion engine, environment modifiers, service availability engine and player connection manager are implemented. The resource boots without QBCore, Qbox, ESX or a phone resource. `TowerRegistry` validates tower definitions, stores immutable static configuration, and initializes isolated runtime state for every tower. `SpatialIndex` maps coverage-overlapping towers into configurable x/y grid cells and returns deterministic candidate lists. `Coverage` applies exact distance and operational-state filtering, `Signal` calculates the normalized distance score and applies server-configured environment modifiers, `Selection` ranks candidates using signal, load, health and optional technology penalties, `Capacity` counts serving players and derives effective capacity, load and congestion effects, and `Services` evaluates voice, SMS, data, GPS and emergency independently. The server keeps one in-memory connection state per player and the client reports bounded position and environment context for reevaluation.

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

Tower definitions belong in `shared/config.lua` under `Config.Towers`:

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

For the first player smoke test, temporarily set `Config.Debug.enabled = true` and `Config.Debug.logLevel = 'debug'`. The client F8 console then reports serving tower, effective signal, signal level, technology, per-service availability, congestion, load, data performance, call setup reliability and SMS delay whenever the authoritative connection state changes. Restore debug logging after testing.
