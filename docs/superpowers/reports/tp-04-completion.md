# Tower Deployment Track TP-04 Completion Report

## Scope

TP-04 adds development-only coverage sampling, pause-map heatmap rendering and
server-side signal inspection for the 37-tower production topology.

## Delivered

- Added bounded `current`, `downtown`, `sandy` and `paleto` grid sampling.
- Added 125 metre default spacing, 512 sample cap, 24-sample chunking and a
  per-player active-job/cooldown guard.
- Reused `Coverage.GetCandidates` and `Selection.Rank`; sampling never calls
  `Connections.Reevaluate` and does not change player connection state.
- Added Green/Yellow/Orange/Red/Black signal bands and client-side
  `AddBlipForRadius` pause-map cells.
- Added `/telecom_signal_inspect [playerId]` with candidate scores and
  distance, environment, failure, jammer, capacity and backhaul breakdowns.
- Kept commands ACE/txAdmin protected and disabled by default. FiveM runtime
  activation requires `setr gnsh_telecom_coverage_tools 1`.
- Added unit coverage for band thresholds, bounded grids, read-only sampling,
  capacity projection, command registration and client chunk/blip lifecycle.

## Files

- `config/default.lua`
- `shared/constants.lua`
- `server/coverage_debug.lua`
- `client/coverage_debug.lua`
- `tests/unit/coverage_debug_spec.lua`
- `COVERAGE_DEBUG.md`

## Verification

- Codebase-memory Lua parser indexed the modified source and exposed all new
  server/client symbols.
- `git diff --check` passed.
- Local Lua 5.4/LuaJIT executable is not installed in the workspace, so
  `lua5.4 tests/run.lua` and recursive `luac5.4 -p` require the repository CI
  runner or a machine with Lua 5.4.

## Usage

See [COVERAGE_DEBUG.md](../../../COVERAGE_DEBUG.md) for enablement, commands,
colour bands and limits.

## Next

Run the CI Lua suite. After it passes, TP-05 can begin with the heatmap output
as the baseline for coverage-gap review and placement tuning.
