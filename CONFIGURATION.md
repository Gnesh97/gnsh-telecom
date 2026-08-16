# Configuration

Baseline defaults and feature switches live in `config/default.lua`. Server-owned tower and backhaul topology belongs in `config/towers.lua`. `shared/config.lua` validates the assembled configuration; optional modules remain controlled by feature flags.

```lua
Config.Features = {
    Capacity = true,
    Failures = true,
    Handover = true,
    Incidents = false,
    Technician = false,
    NOC = false,
    Backhaul = false,
    Sabotage = false,
    Jammers = false,
    Statistics = false,
}
```

Important settings:

- `Config.Handover` controls score advantage, candidate hold and cooldown.
- `Config.Incidents` maps failure types to severity and controls automatic ticket creation.
- `Config.Technician` defines allowed jobs, interaction distance and required parts.
- `Config.NOC` defines the NOC ACE and maximum tower rows sent to the UI.
- `Config.Backhaul` defines nodes, links, core nodes and tower-to-node mappings.
- `Config.Sabotage` defines action-to-failure mappings; clients cannot override them.
- `Config.Jammers` defines limits, radius, strength, duration and supported technologies.
- `Config.Statistics` defines aggregate flush cadence and retention limits.

Production defaults have `Debug.enabled = false` and `Debug.logLevel = 'info'`. Keep debug logging off in production. The development fixture overlay is opt-in through `config/examples/towers.lua` followed by `config/development.lua`; neither file is loaded by the production manifest.
