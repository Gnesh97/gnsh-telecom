# gnsh-telecom

Standalone, server-authoritative GSM and telecom infrastructure for FiveM.

## Phase 6 status

The foundation, authoritative tower domain, spatial index, basic coverage engine, dynamic tower selection, service availability engine and player connection manager are implemented. The resource boots without QBCore, Qbox, ESX or a phone resource. `TowerRegistry` validates tower definitions, stores immutable static configuration, and initializes isolated runtime state for every tower. `SpatialIndex` maps coverage-overlapping towers into configurable x/y grid cells and returns deterministic candidate lists. `Coverage` applies exact distance and operational-state filtering, `Signal` calculates the normalized distance score, `Selection` ranks candidates using signal, load, health and optional technology penalties, and `Services` evaluates voice, SMS, data, GPS and emergency independently. The server keeps one in-memory connection state per player and the client reports bounded position context for reevaluation.

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

For the first player smoke test, temporarily set `Config.Debug.enabled = true` and `Config.Debug.logLevel = 'debug'`. The client F8 console then reports serving tower, signal, signal level, technology and per-service availability whenever the authoritative connection state changes. Restore debug logging after testing.
