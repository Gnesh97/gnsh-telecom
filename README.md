# gnsh-telecom

Standalone, server-authoritative GSM and telecom infrastructure for FiveM.

## Phase 12 status

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

Failure effects are server-authoritative and data-driven. `FailureEngine.Create(towerId, failureType)` supports `ANTENNA_FAILURE`, `RADIO_FAILURE`, `COOLING_FAILURE` and `HARDWARE_DEGRADATION`. Effects combine multiplicatively, update connected players, and restore when cleared. Set `Config.Features.Failures = false` to neutralize the engine. Automatic failure scheduling is disabled by default through `Config.FailureScheduler.enabled = false`; only manual failure creation is active.

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
/telecom fail <towerId> <ANTENNA_FAILURE|RADIO_FAILURE|COOLING_FAILURE|HARDWARE_DEGRADATION>
/telecom repair <towerId>
/telecom load <towerId> <percent|clear>
/telecom noc
```

`/telecomdebug` toggles a client-only overlay. It is off by default and shows the current tower, distance, signal, capacity/congestion, environment, failure modifiers and alternative scores when those values are available. `/telecom load` is an in-memory test override and is cleared by restart or by using `clear`.

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

For the first player smoke test, temporarily set `Config.Debug.enabled = true` and `Config.Debug.logLevel = 'debug'`. The client F8 console then reports serving tower, effective signal, signal level, technology, per-service availability, congestion, load, environment and failure modifiers, data performance, call setup reliability and SMS delay whenever the authoritative connection state changes. Restore debug logging after testing.
