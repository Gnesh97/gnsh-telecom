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
