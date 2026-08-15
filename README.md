# gnsh-telecom

Standalone, server-authoritative GSM and telecom infrastructure for FiveM.

## Phase 1 status

The foundation, authoritative tower domain, spatial index and basic coverage engine are implemented. The resource boots without QBCore, Qbox, ESX or a phone resource. `TowerRegistry` validates tower definitions, stores immutable static configuration, and initializes isolated runtime state for every tower. `SpatialIndex` maps coverage-overlapping towers into configurable x/y grid cells and returns deterministic candidate lists. `Coverage` applies exact distance and operational-state filtering, while `Signal` calculates the pure normalized distance score.

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
