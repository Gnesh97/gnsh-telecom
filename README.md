# gnsh-telecom

[![Validate FiveM resource](https://github.com/Gnesh97/gnsh-telecom/actions/workflows/validate.yml/badge.svg?branch=dev)](https://github.com/Gnesh97/gnsh-telecom/actions/workflows/validate.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Release candidate](https://img.shields.io/badge/status-0.1.0--rc.1%20%7C%20experimental-orange.svg)](#status)

Standalone, server-authoritative GSM and telecom infrastructure for FiveM.

## Contents

- [Status](#status)
- [At a glance](#at-a-glance)
- [Features](#features)
- [Architecture](#architecture)
- [Installation](#installation)
- [Configuration](#configuration)
- [Public API](#public-api)
- [Integrations and compatibility](#integrations-and-compatibility)
- [Operations](#operations)
- [Security](#security)
- [Validation and current limitations](#validation-and-current-limitations)
- [Changelog and license](#changelog-and-license)

## Status

> `0.1.0-rc.1` is an experimental release candidate. It is not a
> production release until real FiveM runtime, provider-version,
> restart, clean-install and multiplayer evidence is recorded.

The resource boots without QBCore, Qbox, ESX, a phone resource or oxmysql.
Optional providers are isolated behind bridges, and the server remains the
authority for tower state, coverage, service availability, failures,
maintenance and operational tools.

## At a glance

| Property | Value |
| --- | --- |
| Runtime | FiveM / GTA V, Lua 5.4 |
| Architecture | Server-authoritative telecom core |
| Required dependencies | None |
| Optional integrations | QBCore, Qbox, ESX, phone, inventory, target, notify, progress and oxmysql providers |
| API schema | `1.0` |
| Resource version | `0.1.0-rc.1` |
| License | MIT |

## Features

### Core telecom

- Deterministic tower registry and server-owned runtime state.
- Spatial-indexed coverage candidate lookup.
- Distance-based signal, environment modifiers and technology selection.
- Dynamic tower selection using signal, load, health and technology weights.
- Server-authoritative player connections, handover hysteresis and capacity.
- Independent voice, SMS, data, GPS and emergency service policy.
- Service sessions and configurable QoS priorities.

### Operations

- Data-driven tower failures with restoration and connected-player updates.
- Incident tickets and validated operational state transitions.
- Optional technician work orders, diagnostics, parts, tools and verification.
- ACE-protected NOC snapshots with bounded full snapshots and deltas.
- Optional tower-to-aggregation-to-regional-POP-to-core backhaul routing.
- Optional carriers, subscribers and roaming.
- Optional sabotage, jammers and in-memory statistics, disabled by default.

### Integration and tooling

- Framework bridges for standalone, QBCore, Qbox, ESX and custom providers.
- Inventory, target, phone, notify, progress and dispatch bridge categories.
- Generic fallbacks when optional resources are absent or stopped.
- Runtime custom bridge SDK for external resources.
- Development-only tower capture, coverage heatmap and signal inspection tools.
- Pure Lua unit/compatibility tests and GitHub Actions validation.

## Architecture

```
flowchart LR
  C["FiveM clients"] --> S["Server-authoritative telecom core"]
  S --> N["Coverage / signal / selection / capacity"]
  S --> O["Failures / incidents / NOC / backhaul"]
  S --> B["Bridge platform"]
  B --> F["Standalone / QBCore / Qbox / ESX"]
  B --> P["Phone / inventory / target / notify / progress"]
  S --> D["Optional memory or oxmysql persistence"]
```

Client payloads are bounded context only. Final tower selection, signal,
service state, failure effects, permission checks and mutation outcomes are
recomputed or validated on the server.

## Installation

1. Copy gnsh-telecom into the server resources directory.
2. Add the resource to server.cfg:

   ```
   ensure gnsh-telecom
   ```

3. Add production tower definitions to config/towers.lua.
4. Restart the resource and confirm CONFIG_OK, RESOURCE_STARTED and the
   spatial-index startup log.

No framework, phone resource or database is required for the core. When
oxmysql is present and persistence is enabled, migrations are applied by the
optional persistence adapter. Current player connections and tower occupancy
remain runtime state and are intentionally recreated after restart.

For admin commands, map the existing server admin group to the resource ACE
when it is not already granted:

```
add_ace group.admin gnsh-telecom.admin allow
```

Do not copy identifiers or principal mappings from another server. Keep those
server-specific permissions in the private server.cfg.

## Configuration

### Production towers

Declare towers under Config.Towers in config/towers.lua:

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

Tower IDs must be unique. Coordinates require numeric x, y and z values.
Supported technologies are EDGE, 3G, 4G and 5G. Static tower definitions are
immutable configuration; load, health, failures and player connections are
kept in separate server runtime state.

Reusable tower classes are METRO_MACRO, TOWN_MACRO, RURAL_MACRO,
HIGHWAY_REPEATER and REMOTE_REPEATER. Deployment policy labels are
METRO_CORE, METRO_EDGE, TOWN, HIGHWAY, RURAL, WILDERNESS and
INTENTIONAL_DEADZONE.

Production does not load config/examples/towers.lua or config/development.lua.
Test coordinates and test topology must remain in those development-only files.

### Feature defaults

The current defaults in config/default.lua are:

| Feature | Default |
| --- | --- |
| Capacity | Enabled |
| Failures | Enabled |
| Incidents | Enabled |
| NOC | Enabled |
| Handover | Enabled |
| Backhaul | Enabled |
| Service sessions | Enabled |
| QoS | Enabled |
| Technician | Disabled |
| Carriers | Disabled |
| Sabotage | Disabled |
| Jammers | Disabled |
| Statistics | Disabled |
| Deployment tools | Disabled |
| Coverage debug | Disabled |

Production defaults keep Config.Debug.enabled = false and
Config.Debug.logLevel = info.

### Development-only coverage tools

Enable these only on a development server:

```
setr gnsh_telecom_coverage_tools 1
restart gnsh-telecom
```

Available commands:

```
/telecom_heatmap current
/telecom_heatmap region downtown
/telecom_heatmap region sandy
/telecom_heatmap region paleto
/telecom_heatmap all
/telecom_heatmap clear
/telecom_signal_inspect [playerId]
/telecom_signal_watch [on|off|status]
/telecom_coverage_expectations
/telecom_coverage_capture <anchorId> WEAK_OR_NONE
```

`/telecom_heatmap all` renders a bounded coarse grid over the full San Andreas
map in one overlay. It uses a wider sampling spacing than the named local
regions so the request remains safe for the server and pause-map blip budget.

The heatmap samples the existing server-authoritative pipeline. It does not
create towers, change connections or add a second gameplay coverage radius.

`/telecom_signal_watch on` starts a server-authoritative snapshot every three
seconds for the executing admin player. Each snapshot is printed to that
player's F8 console with coordinates, signal/band, selected tower, distance,
environment, interference, capacity and candidate details. Drive the test
route while it is enabled, then use `/telecom_signal_watch off` and send the
collected `signal_watch` lines for analysis. The interval is configurable with
`Config.CoverageDebug.signalWatchIntervalMs` and is clamped to 2–10 seconds.
The line keeps the currently connected signal separate from the best candidate
(`selectedSignal`) during handover hysteresis.

TP-07 gap candidates are intentionally draft-only until they are visually
validated in-game:

```
HW-SANDY-EAST-01       (2434.26, 2856.03, 48.54)
HW-SENORA-CORRIDOR-01  (2725.54, 4392.98, 47.80)
HW-DAVIS-FREEWAY-01    (-273.15, -1248.67, 36.88)
```

Use `/telecom_tower_drafts` to show these anchors, move to a safe roadside
structure, then capture the matching site id with `/telecom_tower_capture
<siteId>`. A capture is evidence for a later `Config.Towers` change; it does
not activate a production tower by itself.

### Persistence and backhaul

Persistence is optional and supports auto, memory and oxmysql adapters. Only
active failures, subscribers and bounded audit history are persisted.

When backhaul is enabled, the transport path is modeled as:

```
tower → aggregation → regional POP → core
```

Healthy radio signal does not guarantee service availability when no route
reaches a configured core. Routing is bounded, deterministic and supports
degraded links, offline nodes and link-disjoint backup paths when available.

## Public API

The API is server-side, framework-independent and safe to use without a phone
resource. All state tables returned by public exports are defensive copies.

```lua
local signal = exports['gnsh-telecom']:GetSignalStrength(source)
local canCall, serviceState = exports['gnsh-telecom']:CanCall(source)
```

### Exports

| Export | Purpose |
| --- | --- |
| HasSignal(source) | Whether the player has usable signal |
| GetSignalStrength(source) | Signal value from 0 to 100 |
| GetSignalLevel(source) | Signal level such as GOOD or NO_SERVICE |
| GetNetworkType(source) | Current technology or nil |
| GetConnectedTower(source) | Serving tower ID or nil |
| GetNetworkState(source) | Defensive connection snapshot |
| CanCall(source) | Core voice service policy |
| CanSendSMS(source) | Core SMS service policy |
| HasDataConnection(source) | Core data service policy |
| CanUseService(source, service) | Generic service policy query |
| CanStartCall(source) | Phone-provider call gate |
| CanSendPhoneSMS(source) | Phone-provider SMS gate |
| CanUsePhoneData(source) | Phone-provider data gate |
| GetPhoneNetworkState(source) | Phone-provider network snapshot |
| GetPhoneBridgeStatus() | Active phone provider and support level |
| GetTowerState(towerId) | Defensive tower runtime state |
| GetIncidentSnapshot() | Incident list and counts |
| GetBackhaulStatus(towerId) | ONLINE, DEGRADED or OFFLINE |
| GetStatistics() | Defensive aggregate telemetry snapshot |
| GetBridgeStatus(category) | Active provider status |
| GetBridgeCapabilities(category) | Active provider capability map |

Invalid or disconnected players receive documented safe fallback values rather
than internal state.

### Events

Subscribe server-side with AddEventHandler:

```lua
AddEventHandler('gnsh-telecom:towerChanged', function(source, current, previous)
    -- Update dependent resource state from the defensive snapshot.
end)
```

Available events:

```
gnsh-telecom:connectionChanged
gnsh-telecom:signalChanged
gnsh-telecom:signalLevelChanged
gnsh-telecom:towerChanged
gnsh-telecom:networkTypeChanged
gnsh-telecom:serviceChanged
gnsh-telecom:handover
gnsh-telecom:incidentChanged
```

Treat event payloads as snapshots and use exports for current queries.

## Integrations and compatibility

### Bridge platform

Bridge categories are framework, inventory, target, phone, dispatch, notify
and progress. Provider selection is deterministic by configured preference,
priority and provider name. Missing optional providers report a safe fallback
and do not stop Telecom Core.

Supported framework adapters are standalone, QBCore, Qbox, ESX and custom.
Inventory adapters include standalone, ox, QB, QS and custom. Target adapters
include native, ox, QB and custom.

Phone adapters include generic, LB Phone, NPWD, QS Smartphone and custom. A
phone provider reports FULL, FUNCTIONAL or DISPLAY support honestly; resource
detection or a pure-Lua contract test is not live compatibility certification.

### Custom bridge SDK

External resources can register providers without editing Telecom Core:

```lua
local ok, registration = exports['gnsh-telecom']:RegisterBridge('phone', {
    name = 'my-phone',
    resources = { 'my-phone-resource' },
    priority = 500,
    capabilities = { 'GetNetworkState' },
    Detect = function(self)
        return GetResourceState(self.resources[1]) == 'started'
    end,
    GetNetworkState = function(_, source)
        return MyPhone.GetNetworkState(source)
    end,
})
```

Registration requires a valid started invoking resource. Provider names,
capabilities and callbacks are validated; duplicate providers are rejected.
Only the registering resource can remove its provider:

```lua
local removed, errorMessage = exports['gnsh-telecom']:UnregisterBridge(
    'phone',
    'my-phone'
)
```

Use GetBridgeStatus, GetBridgeCapabilities, GetBridgeRegistration and
GetBridgeRegistrations for read-only status. Provider callbacks are isolated,
and registrations are cleaned up when the owning resource stops.

### Compatibility evidence

The current matrix is intentionally conservative:

| Runtime combination | Status |
| --- | --- |
| Standalone with no phone | EXPERIMENTAL |
| QBCore with phone, inventory and target | EXPERIMENTAL |
| Qbox with phone, inventory and target | EXPERIMENTAL |
| ESX with phone, inventory and target | EXPERIMENTAL |
| Phone, inventory, target, framework or notify restart lifecycle | EXPERIMENTAL |
| LB Phone, NPWD and QS provider contracts | EXPERIMENTAL |

Promotion requires a live FiveM run recording exact resource versions, startup
order, connected-client behavior, capabilities and restart behavior.

## Operations

### Failures and incidents

FailureEngine supports antenna, radio, sector, radio unit, cooling, fiber,
backhaul, controller, software and hardware degradation effects. Effects are
server-authoritative, aggregate deterministically and restore when cleared.

Incidents validate the lifecycle:

```
OPEN → ACKNOWLEDGED → ASSIGNED → ON_ROUTE → DIAGNOSING
→ REPAIRING → RESOLVED → CLOSED
```

Technician gameplay requires both incidents and technicians to be enabled. A
work order uses server-owned jobs, assignment, distance, inventory, tools,
parts, duration and post-repair verification. The repair is not resolved until
tower health, component state, backhaul and services pass verification.

### NOC

Enable Config.Features.NOC and grant the configured ACE. Open the dashboard
with:

```
/telecomnoc
```

The NOC sends one bounded snapshot followed by cursor-ordered deltas. It can
display tower, incident, backhaul, region and jammer state. Missing optional
modules produce valid bounded snapshots rather than errors.

### Admin and development commands

The commands below require the configured admin ACE, an accepted admin/god/
command ACE, txAdmin authorization or the server console:

```
/telecomdebug
/telecom tower <towerId>
/telecom towers
/telecom signal [playerId]
/telecom fail <towerId> <failureType>
/telecom repair <towerId>
/telecom technician <action> <incidentId|sessionId> [reason]
/telecomtech <action> <incidentId|sessionId> [reason]
/telecom load <towerId> <percent|clear>
/telecom noc
/telecomnoc
```

The load command is an in-memory development override. It is cleared by
resource restart or by using clear.

### Troubleshooting

| Symptom | Check |
| --- | --- |
| Resource refuses to start | Read the lines after CONFIG_INVALID; check numeric coordinates, unique IDs and supported technologies. |
| Strong signal but no data | Inspect services.data.reason and blockedBy; overloaded capacity, failures, offline towers and backhaul can block service. |
| Debug command is unauthorized | Grant gnsh-telecom.admin or an existing admin, god or command ACE. |
| Persistence is degraded | Check oxmysql state and migrations; gameplay remains authoritative in memory and queued writes retry. |
| NOC does not open | Confirm Config.Features.NOC = true, the configured ACE and /telecomnoc. |

## Security

The server is authoritative for tower state, failures, incidents, repairs,
backhaul, sabotage and jammers.

- Client payloads are type-checked, bounded and recomputed server-side.
- Protected tower actions validate distance against server entity coordinates.
- Technician actions validate job, assignment, item, tool, distance and state.
- Sabotage maps an action to a server-side failure; clients cannot choose the effect.
- Jammers validate position, radius, strength, duration, technology and limits.
- Sensitive commands and NOC snapshots require admin/ACE authorization.
- Rate limits, audit records, ownership checks and lifecycle cleanup protect mutations.
- Session IDs, transition ordering and source/resource ownership prevent replay.
- Custom bridge callbacks are isolated and cannot mutate Telecom Core directly.

Do not report vulnerabilities through public issues. Use GitHub's private
security advisory form:

<https://github.com/Gnesh97/gnsh-telecom/security/advisories/new>

Include the resource version, runtime/provider versions, reproduction steps,
impact and sanitized logs. Do not include secrets, tokens or player data.

## Validation and current limitations

Recorded release-candidate evidence covers:

- Version metadata and API schema consistency.
- MIT license presence.
- Lua unit/release suite execution.
- Recursive Lua syntax validation.
- Synthetic scale validation.
- Synthetic compatibility contracts with conservative EXPERIMENTAL labels.
- git diff --check hygiene.

The following gates remain uncertified for this release candidate:

- Real FiveM server startup and resource lifecycle.
- Connected-client and multiplayer behavior.
- Clean install, upgrade, restart and server restart scenarios.
- Exact live framework, phone, inventory, target and provider versions.
- Real runtime performance and load evidence.
- Release publication and version tagging.

Run the local pure-Lua suite with Lua 5.4:

```
lua5.4 tests/run.lua
```

The same checks run in [GitHub Actions](.github/workflows/validate.yml).
The current public API schema is defined by Constants.ApiVersion in
shared/constants.lua; the resource version is defined independently in
fxmanifest.lua and config/default.lua.

## Changelog and license

- [Changelog](CHANGELOG.md)
- [MIT License](LICENSE)

The main configuration entry points are
[config/default.lua](config/default.lua), [config/towers.lua](config/towers.lua)
and [fxmanifest.lua](fxmanifest.lua). The test runner is
[tests/run.lua](tests/run.lua), and a complete external bridge example is
[examples/custom_bridge.lua](examples/custom_bridge.lua).
