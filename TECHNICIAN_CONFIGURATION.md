# Technician configuration

Technician gameplay requires both `Config.Features.Incidents = true` and `Config.Features.Technician = true`.

```lua
Config.Technician = {
    jobs = { technician = true, telecom = true },
    interactionDistance = 5.0,
    diagnosticDurationMs = 2500,
    repairDurationMs = 10000,
    requiredItems = {
        RADIO_UNIT_FAILURE = 'radio_replacement',
        FIBER_FAILURE = 'fiber_splice_kit',
    },
    components = {
        RADIO_UNIT = {
            requiredTool = 'rf_meter',
            requiredPart = 'radio_replacement',
            repairable = true,
            replaceable = true,
        },
    },
    verification = {
        minimumTowerHealth = 1,
        requireBackhaul = true,
        requireServices = true,
    },
    allowAdmin = true,
}
```

Framework job lookup, inventory checks and target interactions are adapters. A missing adapter, or an inventory adapter without verified item operations, fails closed. `requiredItems` remains the compatibility part map; `components` adds canonical component definitions, tools and parts. The built-in component names are `ANTENNA`, `SECTOR`, `RADIO_UNIT`, `FIBER_TRANSCEIVER`, `COOLING`, `CONTROLLER` and `BACKHAUL_ROUTER`.

Maintenance is represented by a server-owned work order. Its lifecycle is:

```text
OFFERED → ACCEPTED → EN_ROUTE → ON_SITE → DIAGNOSING
→ READY_FOR_REPAIR → REPAIRING → VERIFYING → COMPLETED
```

The incident remains active after physical repair. Post-repair verification checks the cleared failure projection, component/radio/sector health, backhaul reachability, service policy and tower health. Only a successful verification clears the failure and transitions the incident to `RESOLVED`; a failed verification returns the work order to `REPAIRING`.

The client workflow is available through `/telecomtech` when the technician and incident features are enabled:

```text
/telecomtech diagnose INC-000001
/telecomtech accept WO-000001
/telecomtech travel WO-000001
/telecomtech arrive WO-000001
/telecomtech diagnose_complete DIAG-100000-1
/telecomtech begin INC-000001
/telecomtech complete REPAIR-100000-2
/telecomtech verify WO-000001
/telecomtech cancel REPAIR-100000-2 player left site
```

`accept`, `travel`, `arrive` and `verify` use the returned work-order ID. `diagnose` and `begin` remain compatibility entrypoints: they create/advance the work order automatically and return server-owned session IDs. Diagnostic responses expose observations (for example RF output, sector, backhaul RX, controller and temperature) without the exact failure type or ID. These commands only submit requests; the server remains authoritative for job, distance, assignment, item/tool, identity, duration, replay and incident-state validation.
