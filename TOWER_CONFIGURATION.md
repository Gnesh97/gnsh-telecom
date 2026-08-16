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

When using backhaul, map the tower ID in `Config.Backhaul.towerNodes` in the same server-owned configuration surface. A tower with a healthy radio but no route to a configured core keeps its signal calculation but loses network services.

The production manifest does not load `config/examples/towers.lua` or `config/development.lua`. Keep test coordinates and test node IDs in those files so they cannot silently become production topology.
