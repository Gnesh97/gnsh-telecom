# GNSH-TeleCOM Continuation Implementation Plan
## Revised Universal Productization & Advanced Telecom Roadmap

**Project:** `gnsh-telecom`
**Repository:** `https://github.com/Gnesh97/gnsh-telecom`
**Development branch:** `dev`
**Stable/release branch:** `main`
**License:** MIT
**Runtime:** FiveM / CfxLua / Lua 5.4
**Canonical plan path inside repository:**
`docs/superpowers/plans/2026-08-16-gnsh-telecom-continuation.md`

> The temporary `codex-file-preview-*` path is not a canonical source and must not be referenced by future agents after this plan is copied into the repository.

---

# 1. Objective

Complete `gnsh-telecom` from its current advanced core state into a production-ready, universal and extensible FiveM telecommunications infrastructure platform.

The project must remain:

- standalone-capable,
- server-authoritative,
- framework-agnostic,
- phone-agnostic,
- inventory-agnostic,
- target-agnostic,
- provider-extensible,
- feature-flag driven,
- testable without external resources,
- honest about runtime support levels.

The product must not become:

- an LB Phone addon,
- a QBCore-only script,
- an ox_target-only system,
- a provider-specific telecom wrapper,
- a simple signal bar resource.

Target architecture:

```text
                           ┌──────────────────────┐
                           │     gnsh-telecom     │
                           │                      │
                           │    TELECOM CORE      │
                           └──────────┬───────────┘
                                      │
                         Public Contracts / APIs
                                      │
          ┌───────────────────────────┼────────────────────────────┐
          │                           │                            │
          ▼                           ▼                            ▼

     BRIDGE PLATFORM           OPERATIONS LAYER            NETWORK SIMULATION

 Framework                    Incidents                    Towers
 Inventory                    Technician                   Cells
 Target                       Maintenance                  Sectors
 Phone                        Work Orders                  Backhaul
 Dispatch                     NOC                          Regional Network
 Notify                       Repair History               Technology Fallback
 Progress                                                  Carriers
                                                          Roaming
                                                          Service Sessions
                                                          QoS
                                                          Outage Propagation
```

---

# 2. Current Baseline

At the time this continuation plan begins:

- Current branch: `main`
- Last pushed commit: `ee25aed`
- Local working tree contains uncommitted technician client/docs work.
- Automated tests: `136 passed, 0 failed`
- Lua syntax: `97 files passed`
- Lua runtime:

```text
C:\Users\Gnesh\Documents\Codex\lua-5.4.8\lua.exe
```

- Lua compiler:

```text
C:\Users\Gnesh\Documents\Codex\lua-5.4.8\luac.exe
```

The working directory is expected to be:

```text
C:\Users\Gnesh\Desktop\txData\QBCore_70C731.base\resources\[standalone]\gnsh-telecom
```

All paths in this plan are repository-relative unless an absolute path is explicitly required.

---

# 3. User Decisions

The following decisions are binding unless explicitly changed later:

1. Phase 27–49 are executed in order.
2. No direct jump to v2.0 scope.
3. Development happens on `dev`.
4. `main` is reserved for release-ready code.
5. Every phase has its own validation gate.
6. Every completed phase must be committed.
7. Every completed phase commit must be pushed to `origin/dev`.
8. Multiplayer validation is deferred to late release validation.
9. Provider runtime tests happen with real resources during compatibility validation.
10. MIT license is used.
11. Provider support must be reported honestly.
12. Unsupported providers must never be marked fully supported from detection-only tests.
13. Future phase functionality must not be silently implemented early.
14. Dirty working tree state must be understood before proceeding.

---

# 4. Global Engineering Rules

## 4.1 Development branch policy

All implementation work occurs on:

```text
dev
```

Before every phase:

```powershell
git status --short
git branch --show-current
```

The agent must verify that the current branch is `dev`.

No ordinary development commit may be pushed directly to `main`.

---

## 4.2 Main branch policy

`main` represents stable/release-ready code.

Expected lifecycle:

```text
main
  │
  └── dev
       │
       ├── Phase 27
       ├── Phase 28
       ├── Phase 29
       └── ...
```

Release integration:

```text
dev
 ↓
milestone gate
 ↓
review / PR
 ↓
main
 ↓
tag
```

Release merges are not automatic.

---

## 4.3 Mandatory per-phase completion pipeline

Every phase must finish with:

```text
Implementation
      ↓
Unit tests
      ↓
Integration tests
      ↓
Core regression
      ↓
Security review
      ↓
Performance review
      ↓
Lua syntax validation
      ↓
git diff --check
      ↓
git status review
      ↓
Commit
      ↓
Push origin/dev
      ↓
Phase completion report
```

A phase is not complete until the push succeeds.

---

## 4.4 Common validation commands

Run from repository root.

### Unit / integration suite

```powershell
& 'C:\Users\Gnesh\Documents\Codex\lua-5.4.8\lua.exe' 'tests\run.lua'
```

### Lua syntax validation

```powershell
Get-ChildItem -Recurse -Filter *.lua | ForEach-Object {
    & 'C:\Users\Gnesh\Documents\Codex\lua-5.4.8\luac.exe' -p $_.FullName
    if ($LASTEXITCODE -ne 0) {
        throw "Lua syntax failed: $($_.FullName)"
    }
}
```

### Git validation

```powershell
git diff --check
git status --short
```

---

## 4.5 Conventional Commit policy

Use meaningful Conventional Commits.

Good examples:

```text
fix(core): harden v1.0 release boundaries
feat(bridges): add universal bridge platform v2
feat(phone): add real telecom provider enforcement
feat(technician): add advanced telecom maintenance gameplay
feat(backhaul): add regional telecom topology
feat(network): add sector-aware cellular architecture
fix(security): harden telecom gameplay trust boundaries
test(compat): validate universal provider matrix
```

Avoid:

```text
update
changes
fix stuff
phase done
```

---

## 4.6 Dirty working tree rule

Do not start the next phase if:

```text
git status --short
```

contains unexplained changes.

Never overwrite unrelated user work.

If existing local changes are intentionally carried across a phase boundary, the completion report must explicitly state why.

---

## 4.7 Telecom Core isolation

Telecom Core must not directly depend on:

```text
QBCore
Qbox
ESX
ox_inventory
qb-inventory
qs-inventory
ox_target
qb-target
LB Phone
NPWD
QS Smartphone
dispatch providers
notification providers
progress providers
```

Provider-specific logic belongs under:

```text
bridges/
```

---

## 4.8 Server authority

Server remains authoritative for:

```text
tower state
signal policy
cell selection
capacity
service availability
failure state
incident state
work orders
diagnostic sessions
repair sessions
repair completion
inventory-consuming outcomes
backhaul
regional topology
carrier state
roaming decisions
service sessions
QoS
outage propagation
sabotage
jammers
permissions
audit
```

Client code is limited to:

```text
UI
animations
progress display
target prompt
environment observations
visual debug
NUI rendering
```

Client UI must not determine final gameplay outcomes.

---

## 4.9 Universal operation

The following configurations must remain valid:

```text
gnsh-telecom without framework
gnsh-telecom without phone
gnsh-telecom without inventory
gnsh-telecom without target
gnsh-telecom without dispatch
gnsh-telecom without notify provider
gnsh-telecom without progress provider
gnsh-telecom without technician
gnsh-telecom without NOC
gnsh-telecom without carriers
gnsh-telecom without roaming
gnsh-telecom without sabotage
gnsh-telecom without jammers
gnsh-telecom without statistics
```

---

# 5. Milestone / Version Strategy

The original roadmap version mapping is preserved, but releases now happen at explicit gates.

```text
PHASE 27–34
      ↓
V1.0 RELEASE GATE
      ↓
v1.0.0-rc.1
      ↓
v1.0.0

PHASE 35–36
      ↓
V1.5 RELEASE GATE
      ↓
v1.5.0

PHASE 37–40
      ↓
V2.0 RELEASE GATE
      ↓
v2.0.0

PHASE 41–44
      ↓
V2.5 RELEASE GATE
      ↓
v2.5.0

PHASE 45–49
      ↓
SECURITY / SCALE / SDK / COMPATIBILITY / PACKAGING
      ↓
next release candidate based on actual completed milestone
```

Important:

> Phase 49 must not hardcode `v1.0.0-rc.1` if v1.0, v1.5, v2.0 and v2.5 have already been released. The release candidate version must be derived from the actual milestone state.

---

# 6. Baseline Synchronization
## Pre-Phase Step — Not a Roadmap Phase

This step must be completed before Phase 27.

## 6.1 Inspect repository and remotes

Run:

```powershell
git fetch origin
git status --short
git branch --show-current
git rev-parse HEAD
git rev-parse origin/main
git branch --list dev
git branch -r --list origin/dev
```

## 6.2 Preserve local work

Inspect all current technician client/docs changes.

If unrelated user changes exist:

- do not overwrite them,
- do not silently include them,
- identify them before continuing.

## 6.3 Safe `dev` bootstrap

### Case A — local `dev` exists

```powershell
git switch dev
git pull --ff-only origin dev
```

### Case B — local `dev` absent, `origin/dev` exists

```powershell
git switch -c dev --track origin/dev
```

### Case C — neither local nor remote `dev` exists

After preserving current local changes safely:

```powershell
git switch main
git pull --ff-only origin main
git switch -c dev
git push -u origin dev
```

The agent must not create a second divergent `dev` branch when `origin/dev` already exists.

## 6.4 Baseline technician commit

Validate the existing technician client/docs changes.

Then:

```powershell
git add -A
git commit -m "feat(technician): add client maintenance workflow"
git push origin dev
```

Phase 27 may begin only after this baseline push succeeds and the working tree is clean.

---

<a id="step-1"></a>
# PHASE 27 — V1.0 Release Hardening

## Objective

Harden the existing telecom core without adding major new gameplay systems.

## Primary files

Modify:

```text
shared/config.lua
server/maintenance/diagnostics.lua
server/maintenance/repairs.lua
bridges/frameworks/standalone.lua
bridges/frameworks/qb.lua
bridges/frameworks/qbox.lua
bridges/frameworks/esx.lua
fxmanifest.lua
tests/unit/operations_spec.lua
tests/unit/framework_bridge_spec.lua
```

Create:

```text
server/maintenance/sessions.lua
config/default.lua
config/towers.lua
config/development.lua
config/examples/towers.lua
tests/unit/maintenance_sessions_spec.lua
```

## New / hardened interfaces

```lua
FrameworkBridge.GetStablePlayerId(source)
```

Diagnostic lifecycle:

```lua
MaintenanceDiagnostics.Begin(source, incidentId)
MaintenanceDiagnostics.Complete(source, sessionId)
MaintenanceDiagnostics.Cancel(source, sessionId)
```

Repair lifecycle:

```lua
MaintenanceRepairs.Begin(source, incidentId)
MaintenanceRepairs.Complete(source, sessionId)
MaintenanceRepairs.Cancel(source, sessionId, reason)
```

Session model:

```lua
{
    sessionId,
    source,
    actorId,
    incidentId,
    failureId,
    towerId,
    startedAt,
    earliestCompleteAt,
    state
}
```

## Implementation requirements

- Repair completion must not accept only `incidentId`.
- Server must create and own session IDs.
- Server revalidates:
  - session,
  - owner,
  - actor identity,
  - incident,
  - failure,
  - tower,
  - player distance,
  - job,
  - inventory requirements,
  - elapsed server time,
  - incident transition,
  - replay state.
- Diagnostic result cannot be returned before server minimum duration.
- Disconnect cleans sessions.
- Resource stop cleans sessions.
- Standalone stable identity uses license identifier.
- QBCore uses persistent citizen identity.
- Qbox uses persistent character identity.
- ESX uses persistent player identifier.
- Production config loads no test tower by default.
- Production debug defaults to disabled.
- Test topology moves to development/examples.

## Test gate

Must pass:

- early repair rejection,
- wrong source rejection,
- wrong session rejection,
- wrong incident rejection,
- replay rejection,
- diagnostic early-complete rejection,
- player drop cleanup,
- resource stop cleanup,
- stable identity tests,
- production config contains no test tower,
- production debug is `false`,
- resource restart smoke test.

### Deferred multiplayer gate

Multiplayer validation is intentionally deferred to Phase 47/48 late release validation.

Phase 27 must explicitly report:

```text
DEFERRED MULTIPLAYER GATE
```

Phase 27 may be implementation-complete, but must not be described as final release validation.

## Commit

```text
fix(core): harden v1.0 release boundaries
```

Push:

```powershell
git push origin dev
```

---

<a id="step-2"></a>
# PHASE 28 — Bridge Platform 2.0

## Objective

Replace category-specific wrapper logic with one central capability-aware integration platform.

## Create

```text
bridges/core/registry.lua
bridges/core/manager.lua
bridges/core/contracts.lua
bridges/core/capabilities.lua
bridges/core/lifecycle.lua
bridges/core/health.lua
tests/unit/bridge_platform_spec.lua
```

## Modify

Existing:

```text
framework bridges
inventory bridges
target bridges
dispatch bridges
phone bridges
server/api.lua
server/bootstrap.lua
```

## Bridge contract

```lua
{
    name,
    category,
    resources,
    priority,
    capabilities,
    Detect,
    Initialize,
    Shutdown,
    HealthCheck
}
```

## Required behavior

- central registry,
- category registration,
- provider priority,
- deterministic selection,
- fallback selection,
- lifecycle restart support,
- safe `pcall` around provider calls,
- health states,
- capability normalization,
- provider disappearance handling,
- bridge status API.

## Public API

```lua
GetBridgeStatus()
GetBridgeStatus(category)
GetBridgeCapabilities(category)
```

## Support / health states

Recommended:

```text
ACTIVE
PARTIAL
DEGRADED
UNAVAILABLE
FAILED
OPTIONAL
```

## Test gate

- priority selection,
- deterministic tie behavior,
- provider stop,
- provider start,
- provider exception,
- fallback activation,
- provider replacement,
- missing optional category,
- capability reporting,
- standalone with all optional providers absent.

## Commit

```text
feat(bridges): add universal bridge platform v2
```

---

<a id="step-3"></a>
# PHASE 29 — Universal Framework Bridges

## Objective

Normalize Standalone, QBCore, Qbox, ESX and Custom under one framework contract.

## Files

Modify:

```text
bridges/frameworks/standalone.lua
bridges/frameworks/qb.lua
bridges/frameworks/qbox.lua
bridges/frameworks/esx.lua
bridges/core/manager.lua
tests/unit/framework_bridge_spec.lua
```

Create:

```text
bridges/frameworks/custom.lua
tests/unit/framework_contract_spec.lua
```

## Contract

```lua
GetPlayer(source)
GetStablePlayerId(source)
GetJob(source)
HasJob(source, jobs)
IsAdmin(source)
GetCharacterName(source)
AddMoney(source, account, amount)
RemoveMoney(source, account, amount)
```

Money is optional.

Telecom Core must not require money capabilities.

## Test gate

- no-framework standalone mode,
- QBCore lifecycle,
- Qbox lifecycle,
- ESX lifecycle,
- stable identity consistency,
- missing export safety,
- nil player safety,
- job fallback,
- admin fallback,
- resource restart safety.

## Commit

```text
feat(frameworks): add universal framework bridge support
```

---

<a id="step-4"></a>
# PHASE 30 — Universal Inventory Bridges

## Objective

Make technician, repair and sabotage inventory-provider independent.

## Create

```text
bridges/inventory/ox.lua
bridges/inventory/qb.lua
bridges/inventory/qs.lua
bridges/inventory/standalone.lua
bridges/inventory/custom.lua
tests/unit/inventory_bridge_spec.lua
```

## Modify

```text
bridges/inventory/generic.lua
server/maintenance/repairs.lua
server/sabotage.lua
```

## Contract

```lua
HasItem(source, item, amount)
RemoveItem(source, item, amount)
AddItem(source, item, amount, metadata)
CanCarry(source, item, amount)
GetItemCount(source, item)
```

## Rules

Inventory is permitted only in gameplay modules.

Network core must remain inventory-free.

When no inventory provider exists:

- item-free actions may continue,
- item-required actions fail safely,
- no fake success is returned.

## Test gate

- ox adapter mock,
- QB adapter mock,
- QS adapter mock/fallback,
- standalone/no-inventory,
- remove failure rollback,
- no item duplication,
- server-only item consumption,
- provider restart safety.

## Commit

```text
feat(inventory): add universal inventory adapters
```

---

<a id="step-5"></a>
# PHASE 31 — Universal Target / Interaction Layer

## Objective

Support target-based and native interactions without coupling gameplay to one target provider.

## Create

```text
bridges/target/ox.lua
bridges/target/qb.lua
bridges/target/native.lua
client/interactions.lua
tests/unit/target_bridge_spec.lua
```

## Modify

```text
bridges/target/generic.lua
client/technician.lua
```

## Contract

```lua
AddEntityInteraction(...)
AddModelInteraction(...)
AddZoneInteraction(...)
RemoveInteraction(...)
```

## Rules

Target callbacks provide only intent/context.

Server validates:

```text
source
tower ID
distance
permission
job
incident
session
action state
```

Native fallback:

```text
distance
prompt
key
```

## Test gate

- ox provider,
- qb provider,
- native fallback,
- provider stop/start,
- interaction reinstall,
- remote action rejection,
- spoofed tower rejection,
- no provider API in Telecom Core.

## Commit

```text
feat(target): add universal interaction bridge
```

---

<a id="step-6"></a>
# PHASE 32 — Real Phone Integration Platform

## Objective

Turn phone bridges from detection/display wrappers into real service integration providers where stable provider APIs allow it.

## Create / restructure

```text
bridges/phones/core/contract.lua
bridges/phones/core/manager.lua
bridges/phones/lbphone/client.lua
bridges/phones/lbphone/server.lua
bridges/phones/npwd/client.lua
bridges/phones/npwd/server.lua
bridges/phones/qs/client.lua
bridges/phones/qs/server.lua
tests/unit/phone_enforcement_spec.lua
```

Modify:

```text
bridges/phones/generic.lua
```

## Contract

```lua
CanStartCall(source)
CanSendSMS(source)
CanUseData(source)
GetNetworkState(source)
```

## Capability support levels

### FULL

```text
Signal UI
Call Gate
SMS Gate
Data Gate
Call Lifecycle
Network Change Hooks
```

### FUNCTIONAL

```text
Signal UI
Call Gate
SMS Gate
Data Gate
```

### DISPLAY

```text
Signal UI only
```

## Provider integrity rule

The coding agent must **not**:

- patch provider internals merely to obtain FULL support,
- monkey-patch undocumented runtime internals,
- modify third-party phone source automatically,
- directly rewrite provider database state unless explicitly required by a documented integration path.

If the provider does not expose a stable hook/API for a capability:

```text
downgrade capability
↓
report PARTIAL / FUNCTIONAL / DISPLAY
↓
document limitation
```

Honest partial integration is preferred over fragile full support.

## Test gate

- no-service call rejection where supported,
- SMS gate where supported,
- data gate where supported,
- backhaul offline behavior,
- signal/network event propagation,
- provider stop/start,
- capability downgrade,
- unsupported feature documentation.

Real-provider runtime evidence remains mandatory at Phase 48 compatibility validation.

## Commit

```text
feat(phone): add real telecom provider enforcement
```

---

<a id="step-7"></a>
# PHASE 33 — Universal Support Bridges

## Objective

Add optional notify, progress and dispatch abstraction.

## Create

```text
bridges/notify/native.lua
bridges/notify/ox.lua
bridges/notify/framework.lua

bridges/progress/native.lua
bridges/progress/ox.lua

bridges/dispatch/native.lua
bridges/dispatch/custom.lua

tests/unit/support_bridge_spec.lua
```

## Contract

```lua
Notify(source, kind, message, data)
StartProgress(source, action, duration, options)
CreateAlert(data)
```

## Rule

Progress UI is presentation-only.

Server remains authoritative for duration.

Dispatch remains optional.

## Test gate

- native notify,
- native progress,
- provider exception fallback,
- no dispatch provider,
- custom dispatch,
- server timer independence.

## Commit

```text
feat(bridges): add notify progress and dispatch adapters
```

---

<a id="step-8"></a>
# PHASE 34 — Bridge Configuration UX

## Objective

Expose deterministic bridge configuration and runtime health reporting to server owners.

## Modify

```text
shared/config.lua
config/default.lua
config/development.lua
bridges/core/manager.lua
server/bootstrap.lua
BRIDGES.md
```

Create:

```text
tests/unit/bridge_config_spec.lua
```

## Configuration model

```lua
Config.Bridges = {
    Framework = {
        provider = 'auto',
        fallback = 'standalone'
    },

    Inventory = {
        provider = 'auto',
        required = false
    },

    Target = {
        provider = 'auto',
        fallback = 'native'
    },

    Phone = {
        provider = 'auto',
        requireEnforcement = false
    },

    Dispatch = {
        provider = 'auto',
        required = false
    },

    Notify = {
        provider = 'auto',
        fallback = 'native'
    },

    Progress = {
        provider = 'auto',
        fallback = 'native'
    }
}
```

## Startup health summary

Example:

```text
[gnsh-telecom] Integration Summary

Framework : QBCore       ACTIVE
Inventory : ox_inventory ACTIVE
Target    : ox_target    ACTIVE
Phone     : LB Phone     FUNCTIONAL
Dispatch  : ps-dispatch  ACTIVE
Notify    : ox_lib       ACTIVE
Progress  : ox_lib       ACTIVE

Compatibility : OK
```

## Test gate

- auto detection,
- explicit selection,
- deterministic fallback,
- required provider missing,
- optional provider missing,
- health output,
- capability output,
- no provider crash.

## Commit

```text
feat(config): add bridge configuration and health reporting
```

---

# V1.0 RELEASE GATE
## Mandatory after Phase 34

This is a milestone gate, not a normal feature phase.

Do not start Phase 35 until v1.0 release readiness is reviewed.

## v1.0 scope

```text
Stable Telecom Core
Bridge Platform 2.0
Framework bridges
Inventory bridges
Target bridges
Phone integration platform
Notify / Progress / Dispatch
Bridge configuration
Persistence
Security baseline
Production defaults
```

## v1.0 release candidate

If this is the first stable release:

```text
v1.0.0-rc.1
```

During RC stabilization:

- no new major feature,
- only bugs,
- security fixes,
- compatibility fixes,
- documentation fixes.

After RC passes:

```text
v1.0.0
```

Merge to `main` only through explicit release approval/review.

---

<a id="step-9"></a>
# PHASE 35 — Technician System 2.0

## Objective

Turn maintenance into full telecom work-order gameplay.

## Create

```text
server/maintenance/work_orders.lua
server/maintenance/components.lua
tests/unit/technician_work_orders_spec.lua
```

## Modify

```text
server/maintenance/sessions.lua
server/maintenance/diagnostics.lua
server/maintenance/repairs.lua
server/maintenance/workflow.lua
client/technician.lua
client/interactions.lua
TECHNICIAN_CONFIGURATION.md
shared/enums.lua
```

## Work order model

```lua
{
    id,
    incidentId,
    towerId,
    assignedActorId,
    assignedSource,
    status,
    createdAt,
    acceptedAt,
    arrivedAt,
    diagnosisStartedAt,
    repairStartedAt,
    verificationStartedAt,
    completedAt
}
```

## Lifecycle

```text
Incident
   ↓
Accept Work Order
   ↓
Travel
   ↓
Access Site
   ↓
Diagnostic Session
   ↓
Fault Investigation
   ↓
Tool / Part Requirement
   ↓
Repair Session
   ↓
VERIFYING
   ↓
Post-Repair Verification
   ↓
Incident Resolved
```

## Required new verification state

Add an explicit operational state such as:

```text
VERIFYING
```

A physical repair must not instantly resolve an incident.

Post-repair verification checks:

```text
failure cleared?
component operational?
sector/radio operational?
backhaul reachable?
service policy restored?
tower health acceptable?
```

Only after successful verification may the incident become `RESOLVED`.

## Diagnostic gameplay

Do not immediately reveal exact failure.

Example:

```text
RF Output        NORMAL
Sector B         DEGRADED
Backhaul RX      FAILED
Controller       NORMAL
Temperature      HIGH
```

## Component model

```lua
{
    health,
    state,
    repairable,
    replaceable,
    requiredTool,
    requiredPart
}
```

Components:

```text
ANTENNA
SECTOR
RADIO UNIT
FIBER TRANSCEIVER
COOLING
CONTROLLER
BACKHAUL ROUTER
```

## Test gate

- full work-order lifecycle,
- diagnostics before exact fault,
- inventory adapter,
- target adapter,
- native fallback,
- disconnect,
- job change,
- distance loss,
- reassignment,
- restart handling,
- repair replay protection,
- VERIFYING state,
- failed verification does not resolve incident.

## Commit

```text
feat(technician): add advanced telecom maintenance gameplay
```

---

<a id="step-10"></a>
# PHASE 36 — NOC 2.0

## Objective

Replace the prototype snapshot UI with a live extensible Network Operations Center.

## Create

```text
noc/server_stream.lua
noc/client_stream.lua
tests/unit/noc_delta_spec.lua
```

## Modify

```text
noc/server.lua
noc/client.lua
noc/web/index.html
NOC_GUIDE.md
```

## Data flow

```text
Initial Full Snapshot
        ↓
Delta Events
        ↓
Periodic Reconciliation
```

Avoid full-world snapshots every refresh interval.

## Extensible entity schema

NOC must not hardcode itself only around tower rows because future phases add:

- regions,
- sectors,
- carriers,
- advanced backhaul entities.

Use an extensible schema similar to:

```lua
{
    entityType = "tower", -- tower | sector | region | backhaul | carrier | incident | jammer
    entityId = "LS-DT-04",
    state = {},
    metadata = {}
}
```

NOC Phase 36 renders currently-supported entity types.

Later phases extend entity registration without rewriting the NOC architecture.

## Dashboard

Display:

```text
Network health
Operational / degraded / offline
Connected devices
Active incidents
Backhaul health
Tower detail
Failure state
Jammer state
Outage state
```

## Public/server interfaces

```lua
NocServer.GetSnapshot(source)
NocServer.Subscribe(source)
NocServer.PublishDelta(delta)
NocServer.Reconcile(source)
```

## Test gate

- initial snapshot,
- delta event,
- reconciliation,
- authorization,
- optional modules off,
- entity schema extension,
- bounded message volume,
- stale subscription cleanup.

## Commit

```text
feat(noc): build live network operations center v2
```

---

# V1.5 RELEASE GATE
## Mandatory after Phase 36

v1.5 scope:

```text
Incident operations
Technician 2.0
Work orders
Diagnostics
Repair verification
NOC 2.0
```

Run milestone validation before moving into advanced network simulation.

Expected stable milestone:

```text
v1.5.0
```

---

<a id="step-11"></a>
# PHASE 37 — Regional Network

## Objective

Extend tower backhaul into tower → aggregation → regional POP → core topology.

## Create

```text
server/backhaul/regions.lua
tests/unit/regional_backhaul_spec.lua
BACKHAUL_GUIDE.md
```

## Modify

```text
server/backhaul/nodes.lua
server/backhaul/links.lua
server/backhaul/graph.lua
server/backhaul/routing.lua
shared/config.lua
noc/server_stream.lua
```

## Node types

```text
TOWER
AGGREGATION
REGIONAL_POP
CORE
```

## Interfaces

```lua
BackhaulRouting.FindRoute(towerId, options)
BackhaulRouting.GetTowerStatus(towerId)
BackhaulRouting.GetRegionalStatus(regionId)
BackhaulRouting.RecomputeAffected(rootNodeId)
```

## Requirements

- primary routes,
- backup routes,
- deterministic path preference,
- bounded route cache,
- route cache invalidation,
- regional outage scope,
- restoration.

## Test gate

- primary path,
- backup path,
- POP failure,
- core failover,
- restore,
- cycle protection,
- bounded recalculation.

## Commit

```text
feat(backhaul): add regional telecom topology
```

---

<a id="step-12"></a>
# PHASE 38 — Sector / Cell Architecture

## Objective

Add directional sector-based coverage while retaining omnidirectional compatibility.

## Create

```text
server/towers/sectors.lua
tests/unit/sectors_spec.lua
```

## Modify

```text
server/towers/validation.lua
server/towers/registry.lua
server/network/coverage.lua
server/network/signal.lua
server/network/capacity.lua
server/network/selection.lua
noc/server_stream.lua
```

## Sector model

```lua
{
    id,
    azimuth,
    beamWidth,
    coverageRadius,
    technologies,
    capacity,
    health,
    state
}
```

## Requirements

- azimuth comparison,
- beam-width logic,
- sector state,
- sector load,
- sector capacity,
- sector failures,
- omnidirectional fallback for legacy tower definitions.

## Test gate

- validation,
- directional math,
- beam boundary,
- sector-specific coverage,
- sector capacity,
- localized failure,
- old tower regression,
- bounded CPU work.

## Commit

```text
feat(network): add sector-aware cellular architecture
```

---

<a id="step-13"></a>
# PHASE 39 — Technology Fallback

## Objective

Make 5G / 4G / 3G / EDGE operational selection technologies instead of labels.

## Create

```text
server/network/technology_selection.lua
tests/unit/technology_fallback_spec.lua
```

## Modify

```text
shared/technologies.lua
server/network/selection.lua
server/network/services.lua
server/network/capacity.lua
phone bridges
noc/server_stream.lua
```

## Fallback order

```text
5G
 ↓
4G
 ↓
3G
 ↓
EDGE
 ↓
NO_SERVICE
```

## Interfaces

```lua
TechnologySelection.Resolve(tower, connection, constraints)
TechnologySelection.GetFallbackOrder()
```

## Test gate

- 5G selected when valid,
- 5G failure → 4G,
- congestion fallback,
- sector technology fallback,
- capacity impact,
- service impact,
- phone network-type event,
- no available technology.

## Commit

```text
feat(network): add dynamic technology fallback
```

---

<a id="step-14"></a>
# PHASE 40 — Advanced Outage Propagation

## Objective

Complete the v2.0 network simulation foundation by allowing bounded infrastructure outage propagation.

## Create

```text
server/backhaul/outage_propagation.lua
tests/unit/outage_propagation_spec.lua
```

## Modify

```text
server/backhaul/routing.lua
server/failures/engine.lua
server/network/connections.lua
server/network/capacity.lua
noc/server_stream.lua
```

## Interfaces

```lua
OutagePropagation.Propagate(rootFailure)
OutagePropagation.GetImpact(rootFailureId)
OutagePropagation.Recover(rootFailureId)
```

## Required behavior

Example:

```text
Fiber Failure
      ↓
Regional path unavailable
      ↓
Backup route receives load
      ↓
Dependent towers become degraded
      ↓
Players hand over
      ↓
Neighbor towers gain load
      ↓
Secondary congestion
```

Maintain:

- root cause,
- visited set,
- affected graph,
- affected towers,
- secondary effects,
- recovery state.

## Test gate

- fiber root failure,
- backup-route load,
- dependent tower degradation,
- handover consequence,
- secondary congestion,
- idempotent recovery,
- no cycle/infinite propagation.

## Commit

```text
feat(network): add cascading outage propagation
```

---

# V2.0 RELEASE GATE
## Mandatory after Phase 40

v2.0 scope:

```text
Regional topology
Redundant backhaul
Sector/cell architecture
Technology fallback
Bounded outage propagation
```

Expected stable milestone:

```text
v2.0.0
```

Do not move into optional carrier/subscriber simulation until v2.0 milestone review is complete.

---

<a id="step-15"></a>
# PHASE 41 — Multi-Carrier / Operator Layer

## Objective

Add optional multi-operator telecom simulation without changing single-carrier defaults.

## Create

```text
shared/carriers.lua
server/carriers/registry.lua
server/carriers/selection.lua
tests/unit/carriers_spec.lua
```

## Modify

```text
server/network/selection.lua
server/towers/registry.lua
shared/config.lua
noc/server_stream.lua
```

## Carrier model

```lua
{
    id,
    name,
    technologies,
    roamingPartners,
    priority,
    branding
}
```

## Feature flag

```lua
Config.Features.Carriers = false
```

## Test gate

- disabled regression,
- single carrier,
- multiple carriers,
- unavailable carrier,
- priority tie-break,
- invalid carrier fallback.

## Commit

```text
feat(carriers): add optional multi-operator support
```

---

<a id="step-16"></a>
# PHASE 42 — SIM / Subscriber & Roaming

## Objective

Add optional subscriber identity and home/partner roaming.

## Create

```text
server/carriers/subscribers.lua
CARRIER_GUIDE.md
tests/unit/roaming_spec.lua
```

## Modify

```text
server/carriers/selection.lua
framework bridges as needed
server/persistence/facade.lua if persistence is enabled
noc/server_stream.lua
```

## Subscriber model

```lua
{
    playerId,
    simId,
    carrierId,
    roamingAllowed,
    serviceClass
}
```

## Interfaces

```lua
SubscriberRegistry.Get(source)
SubscriberRegistry.Set(source, subscriber)
CarrierSelection.ResolveSubscriberNetwork(source)
```

## Test gate

- home network,
- partner roaming,
- roaming disabled,
- no partner,
- cleanup,
- persistence behavior,
- carrier-disabled regression.

## Commit

```text
feat(carriers): add subscriber and roaming simulation
```

---

<a id="step-17"></a>
# PHASE 43 — Service Session Engine

## Objective

Make network demand depend on active service usage rather than connected-player count alone.

## Create

```text
server/network/service_sessions.lua
tests/unit/service_sessions_spec.lua
```

## Modify

```text
server/network/capacity.lua
server/network/services.lua
phone bridges
server/security/rate_limit.lua
noc/server_stream.lua
```

## Public API

```lua
BeginServiceSession(source, service, metadata)
UpdateServiceSession(sessionId, metadata)
EndServiceSession(sessionId)
```

## Session classes

```text
VOICE
SMS
DATA
GPS
EMERGENCY
BACKGROUND_DATA
```

## Requirements

Sessions are:

- server-created,
- owner-bound,
- bounded,
- rate-limited,
- cleaned on disconnect,
- cleaned on resource stop,
- protected from replay,
- reflected in tower load.

## Test gate

- voice demand,
- data demand,
- idle-vs-active,
- owner validation,
- replay,
- cleanup,
- rate limiting,
- phone bridge integration.

## Commit

```text
feat(network): add telecom service session engine
```

---

<a id="step-18"></a>
# PHASE 44 — QoS / Priority Engine

## Objective

Prioritize network traffic under congestion.

## Create

```text
server/network/qos.lua
tests/unit/qos_spec.lua
```

## Modify

```text
server/network/capacity.lua
server/network/services.lua
server/network/service_sessions.lua
shared/config.lua
noc/server_stream.lua
```

## Priority classes

```text
EMERGENCY
VOICE
SMS
DATA_HIGH
DATA_NORMAL
BACKGROUND
```

## Interfaces

```lua
QosEngine.GetPriority(service, metadata)
QosEngine.Allocate(towerId, sessions, capacity)
QosEngine.GetServiceResult(sessionId)
```

## Test gate

- configurable priorities,
- background degrades first,
- normal data before emergency,
- voice preservation,
- emergency highest priority,
- capacity/session integration.

## Commit

```text
feat(network): add configurable qos prioritization
```

---

# V2.5 RELEASE GATE
## Mandatory after Phase 44

v2.5 scope:

```text
Multi-carrier
Subscriber / SIM
Roaming
Service sessions
QoS
```

Expected stable milestone:

```text
v2.5.0
```

---

<a id="step-19"></a>
# PHASE 45 — Custom Integration SDK

## Objective

Allow unsupported resources to integrate without modifying Telecom Core.

This phase intentionally occurs **before Security 2.0** so the public extension surface is included in the adversarial audit.

## Create

```text
bridges/core/sdk.lua
examples/custom_bridge.lua
tests/unit/custom_bridge_sdk_spec.lua
```

## Modify

```text
bridges/core/registry.lua
bridges/core/contracts.lua
CUSTOM_INTEGRATION.md
fxmanifest.lua
```

## Public API

```lua
exports['gnsh-telecom']:RegisterBridge(category, definition)
```

Supported categories:

```text
framework
inventory
target
phone
dispatch
notify
progress
```

## Requirements

- category validation,
- name validation,
- contract validation,
- capability normalization,
- duplicate policy,
- safe registration,
- safe deregistration,
- resource-stop cleanup,
- no core edit required for external adapter.

## Security preparation

The SDK must provide explicit boundaries for:

```text
who can register
when registration is accepted
what callbacks may do
provider ownership
resource lifecycle
duplicate provider behavior
untrusted return values
```

## Test gate

- valid registration,
- invalid definition,
- duplicate registration,
- capability reporting,
- lifecycle,
- deregistration,
- external provider example,
- no provider-specific code inside core.

## Commit

```text
feat(sdk): add custom bridge registration api
```

---

<a id="step-20"></a>
# PHASE 46 — Security 2.0

## Objective

Audit the complete runtime attack surface, including the new Custom Integration SDK.

## Modify

```text
server/security/validation.lua
server/security/rate_limit.lua
server/security/audit.lua
maintenance session modules
bridge registry / SDK
jammer
sabotage
backhaul
carrier
service session modules
NOC privileged actions
phone server integration
```

Create:

```text
tests/unit/security_adversarial_spec.lua
```

Modify:

```text
SECURITY.md
```

## Attack matrix

```text
remote invocation
invalid source
tower spoof
incident spoof
session spoof
distance spoof
oversized payload
deep payload
invalid coordinates
double completion
session replay
stale session
item duplication
resource restart abuse
reconnect abuse
permission bypass
race conditions
custom bridge abuse
duplicate bridge injection
malicious adapter callback
NOC privilege bypass
```

## Rules

- critical mutation is never client-authoritative,
- server coordinates override client claims where possible,
- sensitive sessions use server-generated IDs,
- external bridge callbacks are treated as integration boundaries,
- failures fail closed where security-sensitive.

## Test gate

No critical unresolved finding.

## Commit

```text
fix(security): harden telecom gameplay trust boundaries
```

---

<a id="step-21"></a>
# PHASE 47 — Performance & Scale Validation

## Objective

Benchmark the complete architecture using both synthetic and real FiveM runtime evidence.

## Create

```text
tests/performance/scale_harness.lua
tests/performance/metrics.lua
PERFORMANCE.md
```

Modify hot paths only if profiling proves need.

Potential files:

```text
server/network/connections.lua
server/towers/spatial_index.lua
server/backhaul/routing.lua
server/network/service_sessions.lua
noc/server_stream.lua
```

## Critical distinction

### Synthetic scale test

Pure Lua / harness simulation.

Examples:

```text
2
16
32
64
128
200 simulated players
```

This validates algorithms and data structures.

It must be reported as:

```text
SYNTHETIC SCALE TEST
```

It must **not** be reported as:

```text
200-player FiveM runtime PASS
```

unless real clients were involved.

### Real FiveM runtime test

Actual FiveM runtime validation.

Report separately as:

```text
REAL FIVEM RUNTIME TEST
```

The number of actual connected clients must be stated explicitly.

## Test matrix

Synthetic players:

```text
2, 16, 32, 64, 128, 200
```

Towers:

```text
20, 50, 100, 200
```

Service sessions:

```text
0, 50, 200, 500
```

Scenarios:

```text
normal movement
mass handover
event congestion
regional outage
100 incidents
NOC open
multiple jammers
large phone session count
```

## Metrics

```text
server tick time
client resource time
event rate
NUI payload/message volume
DB writes
memory growth
candidate tower count
route recalculation count
bridge lifecycle overhead
service session count
```

## Acceptance Criteria

- no unbounded player×tower hot loop,
- no server-wide per-frame calculation,
- bounded candidates,
- change-driven replication,
- bounded NOC deltas,
- stable memory trend,
- controlled DB writes,
- no mass-handover event storm.

## Commit

```text
perf(core): validate and optimize telecom scale
```

---

<a id="step-22"></a>
# PHASE 48 — Universal Compatibility Matrix

## Objective

Validate claimed provider support with real runtime evidence.

## Create

```text
COMPATIBILITY.md
tests/compat/standalone_spec.lua
tests/compat/qbcore_spec.lua
tests/compat/qbox_spec.lua
tests/compat/esx_spec.lua
tests/compat/phone_spec.lua
tests/compat/provider_lifecycle_spec.lua
```

## Modify

```text
BRIDGES.md
PHONE_BRIDGE_GUIDE.md
```

## Required combinations

```text
Standalone + no phone

QBCore + phone + inventory + target
Qbox + phone + inventory + target
ESX + phone + inventory + target

Phone starts after telecom
Phone stops while telecom runs
Inventory restart
Target restart
Framework restart
Notify restart
Progress restart
```

## Support labels

Only:

```text
FULLY SUPPORTED
SUPPORTED
PARTIAL
EXPERIMENTAL
UNSUPPORTED
```

## Evidence rule

Detection alone is never runtime support evidence.

For each provider record:

```text
provider version
resource name
test date
capabilities verified
capabilities unavailable
runtime combination
result
known limitations
```

## Test gate

- every support label has evidence,
- unsupported combinations fail gracefully,
- docs match actual behavior,
- no provider marked FULL without full capability runtime evidence.

## Commit

```text
test(compat): validate universal provider matrix
```

---

<a id="step-23"></a>
# PHASE 49 — Final Packaging & Release Preparation

## Objective

Prepare a production release candidate based on the actual highest completed/released milestone.

## Create / verify

```text
LICENSE
CHANGELOG.md
CARRIER_GUIDE.md
COMPATIBILITY.md
PERFORMANCE.md
release test report
```

Modify as required:

```text
README.md
INSTALLATION.md
CONFIGURATION.md
API.md
BRIDGES.md
PHONE_BRIDGE_GUIDE.md
CUSTOM_INTEGRATION.md
TOWER_CONFIGURATION.md
TECHNICIAN_CONFIGURATION.md
NOC_GUIDE.md
BACKHAUL_GUIDE.md
SECURITY.md
TROUBLESHOOTING.md
fxmanifest.lua
production configs
```

Create:

```text
tests/release/release_gate_spec.lua
```

## Version rule

Do not blindly set:

```text
1.0.0-rc.1
```

Determine the release candidate from actual milestone history.

Examples:

```text
If v1.0 has not yet been released:
1.0.0-rc.1

If v1.0, v1.5, v2.0 and v2.5 are already stable:
use the next intended release version
```

Version metadata must be consistent across:

```text
Config.Version
fxmanifest.lua
Constants.ApiVersion where relevant
CHANGELOG
README
release notes
```

## Production defaults

Verify:

```text
Debug = false
production log level
no test towers
test/debug actions protected
Sabotage = false unless intentionally enabled
Jammers = false unless intentionally enabled
Statistics optional
safe provider fallbacks
optional dependency absence does not crash
```

## Final release gate

1. clean install,
2. upgrade install,
3. resource start,
4. resource stop,
5. resource restart,
6. server restart,
7. single-player regression,
8. real multiplayer validation,
9. synthetic scale validation,
10. real FiveM runtime performance evidence,
11. compatibility matrix,
12. adversarial security suite,
13. documentation review,
14. `git diff --check`,
15. clean working tree,
16. push `origin/dev`,
17. explicit release approval,
18. reviewed merge to `main`,
19. version tag.

`main` merge is not automatic.

## Commit

```text
chore(release): prepare gnsh-telecom release candidate
```

---

# 7. Mandatory Phase Completion Report

Every phase must end with:

```markdown
## Phase XX Completion Report

### Branch
dev

### Implemented
- ...

### Files Created
- ...

### Files Modified
- ...

### Public API Changes
- ...

### Bridge Changes
- ...

### Security Review
- ...

### Performance Review
- ...

### Tests Executed
- PASS: ...

### Runtime Tests
- PASS / DEFERRED: ...

### Deferred Gates
- ...

### Known Limitations
- ...

### Git Validation
- git diff --check: PASS
- working tree before commit: REVIEWED
- working tree after push: CLEAN

### Commit
- Commit: <SHA>
- Message: <message>

### Push
- origin/dev: SUCCESS

### Milestone Status
- ...

### Ready for Next Phase
YES / NO
```

---

# 8. Failure Rule

Do not proceed if:

```text
mandatory tests fail
critical security finding remains
Lua syntax fails
git diff --check fails
wrong branch is active
commit fails
push fails
unexplained dirty tree remains
```

If implementation is complete but push fails:

```text
IMPLEMENTED BUT NOT COMPLETE
```

must be reported.

---

# 9. Regression Requirement

After every phase verify:

```text
Player
 ↓
Coverage
 ↓
Signal
 ↓
Tower Selection
 ↓
Connection
 ↓
Capacity
 ↓
Services
 ↓
Public API
```

Advanced features must not break base telecom behavior.

---

# 10. Universality Acceptance Criteria

The project is universal only when:

- Core runs standalone.
- Framework can change without Core edits.
- Inventory can change without Core edits.
- Target can change without Core edits.
- Phone can change without Core edits.
- Dispatch can change without Core edits.
- Notify/Progress provider can change without Core edits.
- Unsupported providers can register external bridges.
- Missing optional providers never crash Telecom Core.
- Runtime provider restart is handled.
- Provider-specific business logic stays outside network core.
- Provider capability reporting is honest.

---

# 11. Final Product Acceptance Criteria

## Core

- [ ] Coverage works.
- [ ] Signal works.
- [ ] Selection works.
- [ ] Handover works.
- [ ] Congestion works.
- [ ] Service policy works.
- [ ] Public API is stable.

## Universal integration

- [ ] Framework bridge platform works.
- [ ] Inventory bridge platform works.
- [ ] Target bridge platform works.
- [ ] Phone bridge platform works.
- [ ] Notify bridge works.
- [ ] Progress bridge works.
- [ ] Dispatch bridge works.
- [ ] Custom SDK works.

## Operations

- [ ] Incident lifecycle works.
- [ ] Technician work orders work.
- [ ] Diagnostics work.
- [ ] Repair sessions are secure.
- [ ] VERIFYING state works.
- [ ] NOC provides live operational visibility.

## Advanced network

- [ ] Regional topology works.
- [ ] Backup routes work.
- [ ] Sector coverage works.
- [ ] Technology fallback works.
- [ ] Outage propagation works.
- [ ] Carriers work when enabled.
- [ ] Roaming works when enabled.
- [ ] Service sessions work.
- [ ] QoS works.

## Security

- [ ] No critical client-authoritative mutation.
- [ ] Repair replay blocked.
- [ ] Diagnostic replay blocked.
- [ ] SDK registration validated.
- [ ] Sabotage validated.
- [ ] Rate limiting works.
- [ ] Distance checks work.
- [ ] Permission checks work.
- [ ] Audit logging works.

## Performance

- [ ] No unbounded hot loop.
- [ ] Spatial indexing remains effective.
- [ ] Route recalculation bounded.
- [ ] NOC deltas bounded.
- [ ] Service session state bounded.
- [ ] Long-running memory stable.
- [ ] Synthetic and real runtime results reported separately.

## Release

- [ ] Development happened on `dev`.
- [ ] Every phase has a commit.
- [ ] Every phase commit reached `origin/dev`.
- [ ] Milestone release gates were respected.
- [ ] `main` contains release-ready code only.
- [ ] Version tag matches actual milestone.
- [ ] MIT license exists.

---

# 12. Orchestrate Chain

All commands reference the canonical in-repository plan path.

Canonical path:

```text
C:\Users\Gnesh\Desktop\txData\QBCore_70C731.base\resources\[standalone]\gnsh-telecom\docs\superpowers\plans\2026-08-16-gnsh-telecom-continuation.md
```

The explicit `step-X` anchors in this file make the references deterministic.

## Phase 27

```bash
/ecc:orchestrate custom "ecc:tdd-guide,ecc:code-reviewer,ecc:security-reviewer" "[Plan: C:\\Users\\Gnesh\\Desktop\\txData\\QBCore_70C731.base\\resources\\[standalone]\\gnsh-telecom\\docs\\superpowers\\plans\\2026-08-16-gnsh-telecom-continuation.md#step-1] Harden v1.0 boundaries with server-authoritative repair and diagnostic sessions, stable player identity, production config separation, and replay-safe maintenance state; Acceptance: early/replayed completion is rejected; production config has no test towers and debug is false; tests, syntax and git validation pass."
```

## Phase 28

```bash
/ecc:orchestrate custom "ecc:architect,ecc:tdd-guide,ecc:code-reviewer" "[Plan: C:\\Users\\Gnesh\\Desktop\\txData\\QBCore_70C731.base\\resources\\[standalone]\\gnsh-telecom\\docs\\superpowers\\plans\\2026-08-16-gnsh-telecom-continuation.md#step-2] Build the central bridge registry, lifecycle manager, contracts, capabilities, health reporting, and bridge status API; Acceptance: providers can be selected and replaced safely; provider stop does not crash core; status and capability tests pass."
```

## Phase 29

```bash
/ecc:orchestrate custom "ecc:tdd-guide,ecc:code-reviewer,ecc:security-reviewer" "[Plan: C:\\Users\\Gnesh\\Desktop\\txData\\QBCore_70C731.base\\resources\\[standalone]\\gnsh-telecom\\docs\\superpowers\\plans\\2026-08-16-gnsh-telecom-continuation.md#step-3] Complete standalone, QBCore, Qbox, ESX, and custom framework contracts including stable identity, job, admin, character, and optional money capabilities; Acceptance: missing frameworks fail safely; lifecycle tests pass; core remains framework agnostic."
```

## Phase 30

```bash
/ecc:orchestrate custom "ecc:tdd-guide,ecc:code-reviewer,ecc:security-reviewer" "[Plan: C:\\Users\\Gnesh\\Desktop\\txData\\QBCore_70C731.base\\resources\\[standalone]\\gnsh-telecom\\docs\\superpowers\\plans\\2026-08-16-gnsh-telecom-continuation.md#step-4] Add ox, QB, QS, standalone, and custom inventory adapters with server-authoritative item operations; Acceptance: inventory contracts are covered; no-inventory fallback is safe; repair item consumption cannot be duplicated."
```

## Phase 31

```bash
/ecc:orchestrate custom "ecc:tdd-guide,ecc:code-reviewer,ecc:security-reviewer" "[Plan: C:\\Users\\Gnesh\\Desktop\\txData\\QBCore_70C731.base\\resources\\[standalone]\\gnsh-telecom\\docs\\superpowers\\plans\\2026-08-16-gnsh-telecom-continuation.md#step-5] Add ox_target, qb-target, and native interaction adapters with server-validated tower and technician actions; Acceptance: provider restart is safe; native fallback works; remote or spoofed interaction cannot mutate gameplay."
```

## Phase 32

```bash
/ecc:orchestrate custom "ecc:tdd-guide,ecc:code-reviewer,ecc:security-reviewer" "[Plan: C:\\Users\\Gnesh\\Desktop\\txData\\QBCore_70C731.base\\resources\\[standalone]\\gnsh-telecom\\docs\\superpowers\\plans\\2026-08-16-gnsh-telecom-continuation.md#step-6] Implement stable provider-supported LB Phone, NPWD, QS, and generic telecom integrations with FULL/FUNCTIONAL/DISPLAY capability reporting; never patch or monkey-patch provider internals merely to achieve FULL support; Acceptance: supported service gates work, provider lifecycle is safe, and unsupported capabilities are downgraded and documented honestly."
```

## Phase 33

```bash
/ecc:orchestrate custom "ecc:tdd-guide,ecc:doc-updater,ecc:code-reviewer" "[Plan: C:\\Users\\Gnesh\\Desktop\\txData\\QBCore_70C731.base\\resources\\[standalone]\\gnsh-telecom\\docs\\superpowers\\plans\\2026-08-16-gnsh-telecom-continuation.md#step-7] Add native and optional notify, progress, and dispatch bridges; Acceptance: absent providers use safe fallbacks; progress is presentation-only; server timers remain authoritative."
```

## Phase 34

```bash
/ecc:orchestrate custom "ecc:tdd-guide,ecc:doc-updater,ecc:code-reviewer" "[Plan: C:\\Users\\Gnesh\\Desktop\\txData\\QBCore_70C731.base\\resources\\[standalone]\\gnsh-telecom\\docs\\superpowers\\plans\\2026-08-16-gnsh-telecom-continuation.md#step-8] Add Config.Bridges provider selection, fallback, required-provider diagnostics, and startup integration summary; Acceptance: auto and explicit providers work; fallback is deterministic; startup health output matches runtime state."
```

## Phase 35

```bash
/ecc:orchestrate custom "ecc:tdd-guide,ecc:code-reviewer,ecc:security-reviewer" "[Plan: C:\\Users\\Gnesh\\Desktop\\txData\\QBCore_70C731.base\\resources\\[standalone]\\gnsh-telecom\\docs\\superpowers\\plans\\2026-08-16-gnsh-telecom-continuation.md#step-9] Expand technician gameplay into work orders, travel, diagnostics, components, tools, parts, secure repair, VERIFYING state, post-repair verification, and resolution; Acceptance: full lifecycle works; inventory/target/native fallback are covered; repair does not resolve until verification succeeds."
```

## Phase 36

```bash
/ecc:orchestrate custom "ecc:tdd-guide,ecc:e2e-runner,ecc:code-reviewer" "[Plan: C:\\Users\\Gnesh\\Desktop\\txData\\QBCore_70C731.base\\resources\\[standalone]\\gnsh-telecom\\docs\\superpowers\\plans\\2026-08-16-gnsh-telecom-continuation.md#step-10] Build NOC 2.0 with snapshot, delta events, reconciliation, extensible entity schema, map, tower details, incident and backhaul visibility; Acceptance: permission protection works; deltas update the UI; future entity types can be added without re-architecting NOC."
```

## Phase 37

```bash
/ecc:orchestrate custom "ecc:architect,ecc:tdd-guide,ecc:code-reviewer" "[Plan: C:\\Users\\Gnesh\\Desktop\\txData\\QBCore_70C731.base\\resources\\[standalone]\\gnsh-telecom\\docs\\superpowers\\plans\\2026-08-16-gnsh-telecom-continuation.md#step-11] Extend backhaul into tower, aggregation, regional POP, and core topology with primary and backup routes; Acceptance: regional failures affect dependent towers; backup routing and restoration work; route recalculation remains bounded."
```

## Phase 38

```bash
/ecc:orchestrate custom "ecc:architect,ecc:tdd-guide,ecc:code-reviewer" "[Plan: C:\\Users\\Gnesh\\Desktop\\txData\\QBCore_70C731.base\\resources\\[standalone]\\gnsh-telecom\\docs\\superpowers\\plans\\2026-08-16-gnsh-telecom-continuation.md#step-12] Add sector-aware tower coverage, azimuth, beam width, sector state, technology, load, and capacity behavior while preserving omnidirectional towers; Acceptance: sector validation and directional coverage pass; sector failure is localized; performance remains bounded."
```

## Phase 39

```bash
/ecc:orchestrate custom "ecc:tdd-guide,ecc:code-reviewer" "[Plan: C:\\Users\\Gnesh\\Desktop\\txData\\QBCore_70C731.base\\resources\\[standalone]\\gnsh-telecom\\docs\\superpowers\\plans\\2026-08-16-gnsh-telecom-continuation.md#step-13] Implement dynamic 5G-to-EDGE technology fallback across selection, capacity, services, and phone state; Acceptance: unavailable technologies fall back deterministically; technology affects capacity and services; NO_SERVICE is returned when none qualify."
```

## Phase 40

```bash
/ecc:orchestrate custom "ecc:architect,ecc:tdd-guide,ecc:code-reviewer" "[Plan: C:\\Users\\Gnesh\\Desktop\\txData\\QBCore_70C731.base\\resources\\[standalone]\\gnsh-telecom\\docs\\superpowers\\plans\\2026-08-16-gnsh-telecom-continuation.md#step-14] Implement bounded cascading outage propagation from root infrastructure failures through routes, towers, capacity, handover and secondary congestion; Acceptance: root cause and impact are inspectable; recovery is idempotent; cycles and infinite propagation are impossible."
```

## Phase 41

```bash
/ecc:orchestrate custom "ecc:architect,ecc:tdd-guide,ecc:code-reviewer" "[Plan: C:\\Users\\Gnesh\\Desktop\\txData\\QBCore_70C731.base\\resources\\[standalone]\\gnsh-telecom\\docs\\superpowers\\plans\\2026-08-16-gnsh-telecom-continuation.md#step-15] Add optional multi-carrier selection with carrier registry, tower availability, priority, branding, and feature isolation; Acceptance: single-carrier behavior is unchanged; multiple carriers influence selection; disabling carriers does not affect core telecom."
```

## Phase 42

```bash
/ecc:orchestrate custom "ecc:architect,ecc:tdd-guide,ecc:code-reviewer" "[Plan: C:\\Users\\Gnesh\\Desktop\\txData\\QBCore_70C731.base\\resources\\[standalone]\\gnsh-telecom\\docs\\superpowers\\plans\\2026-08-16-gnsh-telecom-continuation.md#step-16] Add optional subscriber/SIM identity and home/partner carrier roaming; Acceptance: home carrier, allowed roaming, denied roaming, and no-partner states are deterministic; subscriber cleanup works; carrier-disabled servers remain unaffected."
```

## Phase 43

```bash
/ecc:orchestrate custom "ecc:tdd-guide,ecc:code-reviewer,ecc:security-reviewer" "[Plan: C:\\Users\\Gnesh\\Desktop\\txData\\QBCore_70C731.base\\resources\\[standalone]\\gnsh-telecom\\docs\\superpowers\\plans\\2026-08-16-gnsh-telecom-continuation.md#step-17] Add server-created voice, SMS, data, GPS, emergency, and background service sessions and integrate them with demand and phone bridges; Acceptance: active sessions affect load; cleanup and replay protection work; session APIs are rate-limited and server authoritative."
```

## Phase 44

```bash
/ecc:orchestrate custom "ecc:tdd-guide,ecc:code-reviewer" "[Plan: C:\\Users\\Gnesh\\Desktop\\txData\\QBCore_70C731.base\\resources\\[standalone]\\gnsh-telecom\\docs\\superpowers\\plans\\2026-08-16-gnsh-telecom-continuation.md#step-18] Implement configurable QoS allocation for emergency, voice, SMS, high-priority data, normal data, and background sessions; Acceptance: lower priority services degrade first; emergency remains highest priority; QoS integrates with sessions and capacity."
```

## Phase 45

```bash
/ecc:orchestrate custom "ecc:architect,ecc:tdd-guide,ecc:code-reviewer,ecc:security-reviewer" "[Plan: C:\\Users\\Gnesh\\Desktop\\txData\\QBCore_70C731.base\\resources\\[standalone]\\gnsh-telecom\\docs\\superpowers\\plans\\2026-08-16-gnsh-telecom-continuation.md#step-19] Add the external custom bridge registration SDK with contract validation, capabilities, lifecycle ownership, duplicate policy, cleanup, examples, and exports; Acceptance: an external resource registers without core edits; invalid definitions are rejected; lifecycle and security-boundary tests pass."
```

## Phase 46

```bash
/ecc:orchestrate custom "ecc:tdd-guide,ecc:code-reviewer,ecc:security-reviewer" "[Plan: C:\\Users\\Gnesh\\Desktop\\txData\\QBCore_70C731.base\\resources\\[standalone]\\gnsh-telecom\\docs\\superpowers\\plans\\2026-08-16-gnsh-telecom-continuation.md#step-20] Perform Security 2.0 audit across maintenance, custom SDK, bridges, NOC, phone, jammer, sabotage, backhaul, carriers, sessions and admin paths; Acceptance: replay, spoofing, flooding, distance, permission, lifecycle and race attack tests are rejected; audit and security docs are updated."
```

## Phase 47

```bash
/ecc:orchestrate custom "ecc:tdd-guide,ecc:e2e-runner" "[Plan: C:\\Users\\Gnesh\\Desktop\\txData\\QBCore_70C731.base\\resources\\[standalone]\\gnsh-telecom\\docs\\superpowers\\plans\\2026-08-16-gnsh-telecom-continuation.md#step-21] Execute synthetic scale validation and separately record real FiveM runtime performance evidence across players, towers, sessions, handover, outage, incidents, NOC, jammers and phone usage; Acceptance: synthetic results are never mislabeled as real-client tests; metrics are recorded; no unbounded hot loop or event storm exists."
```

## Phase 48

```bash
/ecc:orchestrate custom "ecc:tdd-guide,ecc:e2e-runner,ecc:doc-updater" "[Plan: C:\\Users\\Gnesh\\Desktop\\txData\\QBCore_70C731.base\\resources\\[standalone]\\gnsh-telecom\\docs\\superpowers\\plans\\2026-08-16-gnsh-telecom-continuation.md#step-22] Run the universal runtime compatibility matrix for standalone, QBCore, Qbox, ESX, phone, inventory, target and provider lifecycle combinations; Acceptance: every support label has runtime evidence; unsupported combinations fail gracefully; docs match observed behavior."
```

## Phase 49

```bash
/ecc:orchestrate custom "ecc:doc-updater,ecc:code-reviewer,ecc:security-reviewer" "[Plan: C:\\Users\\Gnesh\\Desktop\\txData\\QBCore_70C731.base\\resources\\[standalone]\\gnsh-telecom\\docs\\superpowers\\plans\\2026-08-16-gnsh-telecom-continuation.md#step-23] Prepare the MIT-licensed release candidate using the actual current milestone version, production defaults, complete docs, compatibility evidence, changelog and package validation; Acceptance: clean install, upgrade, restart, security, synthetic scale, real multiplayer/runtime evidence and compatibility gates pass; main changes only after explicit release approval."
```

---

# 13. Final Execution Order

```text
Baseline synchronization
        ↓
Phase 27 — v1.0 hardening
        ↓
Phase 28 — bridge platform
        ↓
Phase 29–34 — universal provider platform
        ↓
V1.0 RELEASE GATE
        ↓
Phase 35 — Technician 2.0
        ↓
Phase 36 — NOC 2.0
        ↓
V1.5 RELEASE GATE
        ↓
Phase 37 — Regional Network
        ↓
Phase 38 — Sectors
        ↓
Phase 39 — Technology Fallback
        ↓
Phase 40 — Outage Propagation
        ↓
V2.0 RELEASE GATE
        ↓
Phase 41 — Carriers
        ↓
Phase 42 — SIM / Roaming
        ↓
Phase 43 — Service Sessions
        ↓
Phase 44 — QoS
        ↓
V2.5 RELEASE GATE
        ↓
Phase 45 — Custom Integration SDK
        ↓
Phase 46 — Security 2.0
        ↓
Phase 47 — Performance & Scale
        ↓
Phase 48 — Compatibility Matrix
        ↓
Phase 49 — Final Packaging / Release Candidate
```

---

# 14. Immediate Next Action

The coding agent must begin with:

```text
1. Read this canonical repository plan.
2. Inspect Git state.
3. Perform Baseline Synchronization.
4. Ensure dev branch exists and tracks origin/dev.
5. Commit/push existing technician baseline work.
6. Confirm clean working tree.
7. Execute Phase 27 only.
8. Run all required validation.
9. Commit Phase 27.
10. Push origin/dev.
11. Produce Phase 27 Completion Report.
12. Do not begin Phase 28 unless Phase 27 is complete.
```

---

# END OF PLAN
