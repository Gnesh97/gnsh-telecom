# Coverage debug tools

The coverage heatmap and signal inspector are development-only, ACE-protected
tools. They sample the existing server-authoritative coverage and selection
pipeline; they do not create towers, change connections, or mutate runtime
network state.

## Enable

Add the convar to the development server configuration and restart the
resource:

```text
setr gnsh_telecom_coverage_tools 1
restart gnsh-telecom
```

Keep the convar disabled on production servers. The normal default is off.

## Heatmap commands

```text
/telecom_heatmap current
/telecom_heatmap region downtown
/telecom_heatmap region sandy
/telecom_heatmap region paleto
/telecom_heatmap clear
```

`current` samples a bounded area around the executing player. The named
regions use fixed development bounds. Samples are spaced at 125 metres by
default, sent in chunks, and capped at 512 points. Each sample is rendered on
the pause map as a translucent radius blip:

| Colour | Signal |
| --- | --- |
| Green | 80–100 |
| Yellow | 55–79 |
| Orange | 30–54 |
| Red | 1–29 |
| Black | No service |

The visual circle is a sampling cell, not an additional gameplay coverage
radius. The production tower radius remains the value in `config/towers.lua`.

## Signal inspector

```text
/telecom_signal_inspect
/telecom_signal_inspect <playerId>
```

The result is printed to the executing admin's F8 console. It includes the
server position, connected and ranked towers, candidate scores, distance and
radius, environment multiplier, active failure effects, jammer interference,
capacity/congestion effects, and backhaul state.

## Golden coverage expectations

TP-05 adds deterministic service and intentional-weak anchors over the same
server-authoritative coverage pipeline:

```text
/telecom_coverage_expectations
/telecom_coverage_capture RATON_REMOTE WEAK_OR_NONE
```

`/telecom_coverage_expectations` evaluates every configured anchor and prints
`PASS`, `FAIL` or `PENDING_CAPTURE` in F8. Required urban, town and highway
anchors use verified production capture coordinates. Intentional weak anchors
are also stored only after a FiveM visit; the capture command prints a
copyable `vector3(...)` configuration entry for future anchor additions.

For each weak anchor, drive to the intended wilderness area and run:

```text
/telecom_coverage_capture <anchorId> WEAK_OR_NONE
```

Copy the printed `coverage config` entry into
`config/coverage_expectations.lua`, restart the resource, and rerun
`/telecom_coverage_expectations`. Do not turn a red/black heatmap cell into a
bug automatically: the plan deliberately expects weak or absent service in
remote wilderness, and every final coordinate must be visually verified in
FiveM.

## Limits and safety

- Commands require the configured admin ACE/txAdmin authorization.
- Sampling is server-authoritative and read-only.
- Grid requests are bounded and yielded between chunks to avoid one long
  server tick.
- Each player can have one active heatmap job and new heatmap starts are
  rate-limited by the configured cooldown (1.5 seconds by default).
- On FiveM servers, heatmap tools are disabled unless
  `gnsh_telecom_coverage_tools` is explicitly enabled. The feature flag is
  only a fallback for the framework-free unit harness where `GetConvar` is
  unavailable.
- Clear the current overlay with `/telecom_heatmap clear` or by restarting the
  resource.
- Coverage expectation commands are development-only and require the same
  admin authorization and `gnsh_telecom_coverage_tools` convar.
