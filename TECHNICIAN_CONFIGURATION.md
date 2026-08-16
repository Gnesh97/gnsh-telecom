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

Framework job lookup, inventory checks, target interactions and rewards are adapters. A missing adapter, or an inventory adapter without a verified add/refund operation for configured parts, fails closed. Begin and complete require the technician to be assigned and near the tower; cancellation remains available to the owning identity after leaving the site.

The client workflow is available through `/telecomtech` when the technician and incident features are enabled:

```text
/telecomtech diagnose INC-000001
/telecomtech diagnose_complete DIAG-100000-1
/telecomtech begin INC-000001
/telecomtech complete REPAIR-100000-2
/telecomtech cancel REPAIR-100000-2 player left site
```

`diagnose` and `begin` return server-owned session IDs. Complete or cancel using the returned session ID. These commands only submit a request. The server remains authoritative for job, distance, assignment, item, identity, duration and incident-state validation.
