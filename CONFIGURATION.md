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
    DeploymentTools = false,
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
- `Config.Deployment.defaultCoverageMinimum` supplies the default coverage minimum for archetype-backed towers.
- `Config.TowerArchetypes` defines reusable `METRO_MACRO`, `TOWN_MACRO`, `RURAL_MACRO`, `HIGHWAY_REPEATER` and `REMOTE_REPEATER` profiles.
- `Config.CoverageZones` defines deployment-intent labels. A tower's optional `class` and `coverageZone` are validated without replacing the existing tower schema.
- `Config.DeploymentSites` is a coordinate-free authoring catalog. It is not loaded into `Config.Towers` and cannot supply production coordinates.
- `Config.DeploymentTools` limits in-memory captures. Enable the editor only on a development server with the `gnsh_telecom_deployment_tools` convar; see [DEPLOYMENT_EDITOR.md](DEPLOYMENT_EDITOR.md).
- `Config.Framework` selects `auto`, `standalone`, `qbcore`, `qbox`, `esx` or `custom`; custom callbacks live under `Config.CustomFramework`.
- Framework money methods are optional; missing framework capabilities fail closed and are never required by Telecom Core.
- `Config.InventoryBridge` selects `auto`, `standalone`, `ox`, `qb`, `qs` or `custom`; custom callbacks live under `Config.CustomInventory`.
- Inventory-dependent actions fail closed when no provider is available; item-free actions remain usable.
- `Config.TargetBridge` selects `auto`, `native`, `ox`, `qb` or `custom`; custom callbacks live under `Config.CustomTarget`.
- Target callbacks submit intent only. Server-side tower, distance, permission, job, incident and session validation remains mandatory.

Production defaults have `Debug.enabled = false` and `Debug.logLevel = 'info'`. Keep debug logging off in production. The development fixture overlay is opt-in through `config/examples/towers.lua` followed by `config/development.lua`; neither file is loaded by the production manifest.
