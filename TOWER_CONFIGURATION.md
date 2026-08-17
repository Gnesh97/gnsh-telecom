# Tower configuration

Towers are declared in `config/towers.lua` under `Config.Towers`. Coordinates must contain numeric `x`, `y` and `z` values. In a FiveM config, use `vector3(x, y, z)`.

```lua
{
    id = 'LS_VIN_01',
    coords = vector3(250.0, -1000.0, 29.0),
    coverage = { radius = 1500.0, minimum = 50.0 },
    technologies = { '4G', '5G' },
    capacity = { maximum = 500 },
}
```

IDs must be unique. Supported technologies are `EDGE`, `3G`, `4G` and `5G`. Static definitions are never used as runtime storage; load, health, failures and connections are kept in a separate server state.

## Deployment archetypes and coverage zones

Tower `class` is optional. When present, it selects a reusable entry from
`Config.TowerArchetypes` and fills missing `coverage.radius` and
`capacity.maximum` values. `coverage.minimum` falls back to
`Config.Deployment.defaultCoverageMinimum` (50 by default). Explicit per-tower
values always win, so existing tower definitions without `class` remain valid.

```lua
{
    id = 'BC-HARMONY-01',
    class = 'TOWN_MACRO',
    coverageZone = 'TOWN',
    coords = vector3(250.0, -1000.0, 29.0),
    technologies = { '4G', '5G' },
}
```

Available archetypes are `METRO_MACRO`, `TOWN_MACRO`, `RURAL_MACRO`,
`HIGHWAY_REPEATER` and `REMOTE_REPEATER`. Available policy labels are
`METRO_CORE`, `METRO_EDGE`, `TOWN`, `HIGHWAY`, `RURAL`, `WILDERNESS` and
`INTENTIONAL_DEADZONE`. `coverageZone` describes deployment intent; it does not
itself change signal attenuation. Unknown classes and policy labels fail
validation.

The planned site catalog in `config/deployment_sites.lua` intentionally has no
`coords` field. Use the admin-only development editor in
[DEPLOYMENT_EDITOR.md](DEPLOYMENT_EDITOR.md) to visit and capture real FiveM
positions. A capture is temporary and must be reviewed before its exported
definition is copied into `config/towers.lua`.

When using backhaul, map the tower ID in `Config.Backhaul.towerNodes` in the same server-owned configuration surface. A tower with a healthy radio but no route to a configured core keeps its signal calculation but loses network services.

The production manifest does not load `config/examples/towers.lua` or `config/development.lua`. Keep test coordinates and test node IDs in those files so they cannot silently become production topology.
