# TP-05 progress: San Andreas coverage expectations

## Scope

TP-05 turns the deployment coverage plan into deterministic regression
anchors. Required urban, town and highway anchors are backed by coordinates
already captured for production towers. All intentional weak anchors are now
backed by coordinates visited and verified in FiveM.

## Implemented

- Added `Config.CoverageExpectations` with 13 required-service anchors and 7
  intentional-weak anchors.
- Added validation for uppercase IDs, categories, supported expectation bands,
  finite coordinates and explicit pending captures.
- Added read-only server evaluation through the existing coverage and selection
  pipeline.
- Added `/telecom_coverage_expectations` for a full PASS/FAIL/PENDING_CAPTURE
  summary.
- Added `/telecom_coverage_capture <anchorId> [expectation]` to capture the
  executing admin's server-side FiveM coordinates and print a copyable config
  entry.
- Added unit coverage for catalog validation, threshold boundaries, pending
  anchors, real pipeline evaluation and command registration.

## Final intentional-weak captures

All seven intentional-weak anchors are backed by in-game captures. The final
two captures are:

- `MOUNT_CHILIAD_WILDERNESS`: signal `0.00`, band `BLACK`, status `PASS`
- `BLAINE_REMOTE_DIRT_ROAD`: signal `11.82`, band `RED`, status `PASS`

The earlier Blaine candidate measured `50.08` (`ORANGE`) and was correctly
rejected; the final point was recaptured farther from service.

## Runtime handoff

```text
setr gnsh_telecom_coverage_tools 1
restart gnsh-telecom
/telecom_coverage_expectations
```

The seven intentional-weak capture lines, including the final Mount Chiliad
and Blaine points above, are now recorded in
`config/coverage_expectations.lua`. After a resource restart, rerun the
expectation summary to confirm the regression baseline.

## Verification status

- `/telecom_heatmap current` was confirmed working by the user.
- All 20 configured anchors now evaluate without pending captures; expected
  runtime summary is `pass=20 fail=0 pending=0`.
- Pure Lua test execution is still pending on this workstation because Lua
  5.4/`luac` is not installed.
- `git diff --check` and repository indexing remain part of the delivery gate.
