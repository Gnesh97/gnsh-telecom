# TP-05 progress: San Andreas coverage expectations

## Scope

TP-05 turns the deployment coverage plan into deterministic regression
anchors. Required urban, town and highway anchors are backed by coordinates
already captured for production towers. Intentional weak anchors remain
coordinate-free until they are visited and verified in FiveM.

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

## Intentional pending work

Five intentional-weak anchors are now backed by in-game captures. The
following two anchors still need a point whose measured signal is below 30:

- `MOUNT_CHILIAD_WILDERNESS`
- `BLAINE_REMOTE_DIRT_ROAD`

The submitted `BLAINE_REMOTE_DIRT_ROAD` capture measured signal `50.08`
(`ORANGE`) and was correctly rejected as `FAIL`; it must be recaptured farther
from service.

This is deliberate. A red/black heatmap sample alone is not a final anchor;
the exact point must be chosen and visually verified in FiveM.

## Runtime handoff

```text
setr gnsh_telecom_coverage_tools 1
restart gnsh-telecom
/telecom_coverage_expectations
/telecom_coverage_capture RATON_REMOTE WEAK_OR_NONE
```

Copy each F8 `coverage config` line into
`config/coverage_expectations.lua`, restart, and rerun the expectation summary.

## Verification status

- `/telecom_heatmap current` was confirmed working by the user.
- Pure Lua test execution is still pending on this workstation because Lua
  5.4/`luac` is not installed.
- `git diff --check` and repository indexing remain part of the delivery gate.
