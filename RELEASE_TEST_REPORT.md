# Release Candidate Test Report

Release candidate: `0.1.0-rc.1`

Test date: 2026-08-17

## Decision

`0.1.0-rc.1` is packaged as a release candidate, but it is not declared a
production release. The release gate remains blocked until a real FiveM server
run records provider versions, connected-client behavior, restart behavior and
multiplayer/runtime evidence.

## Gate results

| Gate | Result | Evidence |
| --- | --- | --- |
| Version metadata | PASS | `Config.Version` and `fxmanifest.lua` are `0.1.0-rc.1`; API schema remains `1.0` by contract |
| MIT license | PASS | `LICENSE` present |
| Documentation packet | PASS | Installation, API, bridges, phone, carrier, NOC, backhaul, security, compatibility and performance docs present |
| Pure Lua release/unit suite | PASS | `lua tests/run.lua`: 331 passed, 0 failed |
| Lua syntax | PASS | Recursive `loadfile` check: `Lua syntax OK` |
| Diff hygiene | PASS | `git diff --check` produced no whitespace errors |
| Synthetic scale | PASS | `lua tests/performance/scale_harness.lua`: exit code 0; results in `PERFORMANCE.md` |
| Synthetic compatibility matrix | PASS | All matrix rows are `EXPERIMENTAL`; no unsupported live claim is promoted |
| Real FiveM runtime | BLOCKED | Not run in this workspace; connected clients: 0 |
| Clean install/upgrade/restart | BLOCKED | Requires a real FiveM server and deployed resource lifecycle |
| Real framework/phone/provider matrix | BLOCKED | Requires QBCore/Qbox/ESX and provider versions in a live server |
| Release publication/tag | BLOCKED | Requires explicit release approval after blocked gates are closed |

## Production-default review

- `Config.Debug.enabled` is `false` in `config/default.lua`.
- The default log level is `info`.
- Optional sabotage and statistics features remain disabled by default.
- Optional framework, inventory, target, phone and persistence providers remain
  fail-safe and do not become hard dependencies.
- `config/examples/` remains outside the production manifest.

## Required follow-up before production release

1. Run the real compatibility matrix with exact provider/resource versions.
2. Run connected-client, restart, clean-install and upgrade scenarios.
3. Attach the runtime logs and update `COMPATIBILITY.md` labels only where the
   evidence supports the promotion.
4. Re-run this report, obtain explicit release approval, then create the release
   tag.
