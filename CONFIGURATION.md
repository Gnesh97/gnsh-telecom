# Configuration

All balancing and feature switches live in `shared/config.lua`. Optional modules are disabled by their feature flag unless explicitly enabled.

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

Keep `Debug.enabled` and especially `Debug.logLevel = 'debug'` off in production after diagnostics are complete.
