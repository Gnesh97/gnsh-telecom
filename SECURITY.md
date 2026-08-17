# Security model

The server is authoritative for tower state, failures, incidents, repairs, backhaul, sabotage and jammers.

- Client payloads are type-checked and server state is recomputed.
- Tower interactions validate player position against server entity coordinates.
- Technician actions validate job, assignment, required item and incident state.
- Sabotage maps an action ID to a server-side configured failure type; a client cannot choose the effect.
- Jammer placement validates position, radius, strength, duration, technology list, owner and active-count limits.
- Sensitive commands and NOC snapshots require admin/ACE authorization.
- Action history is written to the bounded audit store when persistence is enabled.
- Rate limits are applied to sabotage and jammer creation, and dropped players have their transient state cleared.

When adding a new network event, document its accepted payload, server-side recomputation, distance check, permission check, rate limit and audit behavior before enabling it.

## v1.0 trust-boundary audit

| Boundary | Caller and accepted input | Server-side controls | Mutation / audit |
| --- | --- | --- | --- |
| Position update | Connected client; finite `x`, `y`, `z` and optional bounded environment context | Exact payload fields, finite coordinates, 4 calls per second per source; server entity coordinates take precedence when available | Recomputes connection only; telemetry is not audited |
| Jammer request | Player; `create` with point and bounded numeric options, or `remove` with an ID | Payload schema, placement distance, owner/admin removal check, active limit and creation cooldown | Creates/removes only the requested jammer; create/remove are audited |
| Sabotage request | Player; bounded tower and action strings | Server action mapping, feature flag, tower proximity, item check, cooldown and existing-failure check | Server chooses failure type; action is audited; disabled by default |
| Maintenance request | Player; bounded action, incident ID and optional reason | Rate limit plus technician/job, assignment, proximity, item and incident-state checks | Workflow transitions are validated by the incident engine |
| Incident request | Admin; bounded transition or assignment payload | Admin permission, rate limit and `IncidentTickets` state-transition validation | Transition and assignment are audited |
| NOC request | Any client, no payload | Rate limit, admin/ACE authorization and defensive snapshot copies | Read-only snapshot |
| Debug commands | Server console or authorized admin | ACE/txAdmin/framework permission middleware and command-specific validation | Read-only inspection or controlled test mutation; admin actions are audited |
| Public exports | Trusted server resources | Public API returns defensive copies and rejects invalid/disconnected sources | No client-triggered mutation path |
| NUI callbacks | Local NUI; close-only callback | Callback has no server mutation authority | Closes UI only |

Invalid payloads are rejected before state mutation. Network-facing actions that change world state do not accept a client-selected outcome, tower failure type, or final interference multiplier.

## v2.0 adversarial hardening (Phase 46)

The Phase 46 review treats every network event, server export and external adapter callback as an untrusted boundary. Critical mutations fail closed when validation, authorization, rate limiting, distance resolution or integration callbacks are unavailable.

| Threat | Control | Expected result |
| --- | --- | --- |
| Remote invocation or invalid source | Normalize positive integer player sources at every mutation boundary | Request is rejected before lookup or mutation |
| Tower, incident or assignee spoofing | Resolve tower and incident state from server registries; bound IDs; validate assignees as server source IDs | Client cannot select an arbitrary target or non-player assignee |
| Distance spoofing or native failure | Validate finite coordinates; prefer server entity coordinates; protect native calls with `pcall`; reject unavailable position data for protected actions | A forged point cannot satisfy proximity; native errors fail closed |
| Oversized, deep, cyclic or metatable payloads | Shared safe-table validator with field/depth/string bounds and cycle/metatable rejection | Payload is discarded without traversing attacker-controlled structures |
| Session replay, stale completion or cross-resource hijack | Server-generated session IDs, active/ended tracking, source ownership and creating-resource binding | Completion/update is one-shot and only the owning player/resource can use it |
| Double completion or item duplication | Server session validation and transition ordering; inventory removal is checked and rollback paths remain authoritative | Replayed or partially completed work cannot grant a second reward |
| Restart/reconnect abuse | Clear transient sessions, rate buckets, sabotage guards, NOC subscriptions and player bindings on lifecycle events | Old runtime authority is not carried across a resource/player lifecycle |
| Race or malicious adapter re-entry | Sabotage per-source in-flight guard; bridge lifecycle and capability calls are protected | Re-entrant callbacks cannot duplicate a mutation or crash the boundary |
| Custom bridge injection | Category/contract validation, duplicate rejection, started-resource and owner checks, owner-only unregister and stop cleanup | An external resource cannot replace or remove another resource’s provider |
| NOC privilege bypass | Admin/ACE checks on snapshot and reconcile paths; bounded provider output; provider normalization is protected | Unauthorized callers receive no operational snapshot or mutation path |

The adversarial suite is `tests/unit/security_adversarial_spec.lua` and is loaded by `tests/run.lua`. The Phase 46 gate is zero failed tests and no unresolved critical finding. New mutation events and exports must add a corresponding abuse case before release.
