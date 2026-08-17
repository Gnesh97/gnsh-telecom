# Performance and Scale Validation

Date: 2026-08-17

## Scope

This report covers the Phase 47 framework-free synthetic scale harness:

```text
lua tests/performance/scale_harness.lua
```

The harness loads the production Lua modules and exercises spatial indexing,
movement and handover selection, event congestion, backhaul outage recovery,
incident creation, NOC entity projection, jammer evaluation, and service
session creation. Timings use Lua 5.4.8 `os.clock()` on the local Windows
development machine and are directional rather than production capacity
guarantees.

## SYNTHETIC SCALE TEST

The run completed with exit code 0.

| Scenario | Operations | Seconds | Operations/sec | Memory delta KiB | Details |
| --- | ---: | ---: | ---: | ---: | --- |
| Spatial index / 20 towers | 20 | 0.001000 | 20,000.00 | 65.46 | 4 cells, 42 tower-cell links |
| Spatial index / 50 towers | 50 | 0.001000 | 50,000.00 | 156.01 | 8 cells, 104 tower-cell links |
| Spatial index / 100 towers | 100 | 0.002000 | 50,000.00 | 311.60 | 9 cells, 225 tower-cell links |
| Spatial index / 200 towers | 200 | 0.005000 | 40,000.00 | 619.91 | 14 cells, 410 tower-cell links |
| Normal movement / 2 players, 20 towers | 2 | 0.004000 | 500.00 | 444.61 | Average candidates 5.0 |
| Normal movement / 16 players, 50 towers | 16 | 0.070000 | 228.57 | 423.16 | Average candidates 6.625 |
| Normal movement / 32 players, 50 towers | 32 | 0.188000 | 170.21 | 556.01 | Average candidates 7.1875 |
| Normal movement / 64 players, 100 towers | 64 | 0.549000 | 116.58 | 577.83 | Average candidates 7.578125 |
| Normal movement / 128 players, 200 towers | 128 | 1.875000 | 68.27 | 2,490.91 | Average candidates 7.859375 |
| Normal movement / 200 players, 200 towers | 200 | 4.118000 | 48.57 | 1,187.66 | Average candidates 7.73 |
| Mass handover / 32 players, 50 towers | 32 | 0.174000 | 183.91 | 530.74 | Average candidates 7.28125 |
| Mass handover / 128 players, 200 towers | 128 | 1.802000 | 71.03 | 842.11 | Average candidates 7.859375 |
| Mass handover / 200 players, 200 towers | 200 | 4.014000 | 49.83 | 3,711.85 | Average candidates 7.73 |
| Event congestion / 200 players, 200 towers, 10 rounds | 2,000 | 40.875000 | 48.93 | 3,825.78 | Average candidates 7.73 |
| Regional outage / link outage and recovery | 2 | 0.058000 | 34.48 | 1,794.78 | 2 regional snapshots |
| Incident storm / 100 incidents | 100 | 0.002000 | 50,000.00 | 138.98 | 100 incidents created |
| NOC open / 200 towers, 200 players | 5 | 0.065000 | 76.92 | 2,053.60 | 409 entities projected |
| Multiple jammers / 50 jammers, 100 players | 100 | 0.008000 | 12,500.00 | 46.94 | Average active effects 2.35 |
| Phone sessions / 0 sessions | 0 | 0.000001 | 0.00 | 0.38 | 0 active |
| Phone sessions / 50 sessions | 50 | 0.161000 | 310.56 | 859.18 | 50 active |
| Phone sessions / 200 sessions | 200 | 1.417000 | 141.14 | 3,574.27 | 200 active |
| Phone sessions / 500 sessions | 500 | 6.047000 | 82.69 | 4,741.29 | 500 active |

The session-count scenario uses known strong synthetic connections distributed
across the tower set so it measures session bookkeeping and tower capacity
refresh independently from the movement-selection scenario.

## REAL FIVEM RUNTIME TEST

Not run in this environment; connected clients: 0.

No production-client capacity, server tick, network transport, or OneSync
claim is made from the synthetic run.

## Findings

- The current Phase 47 run completed without a harness error.
- Candidate counts remain bounded by the spatial index in the tested 200-tower
  scenarios.
- The 200-player, 2,000-position-event case is the dominant synthetic workload
  and should be the first target for profiling in a real FiveM server.
- No production hot path was changed based only on synthetic timings. A real
  runtime profile is required before optimizing or changing behavior.
