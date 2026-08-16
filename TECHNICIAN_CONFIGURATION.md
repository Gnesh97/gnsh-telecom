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
    allowAdmin = true,
}
```

Framework job lookup, inventory checks, target interactions and rewards are adapters. A missing adapter fails closed for a configured required item. A technician must be assigned to the incident, remain near the tower and pass the server-side state-transition checks.
