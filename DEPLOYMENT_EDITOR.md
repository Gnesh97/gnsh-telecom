# Deployment editor

The deployment editor is a development-only authoring tool. The catalog in
`config/deployment_sites.lua` contains site IDs, archetypes, coverage intent and
purpose, but deliberately contains no coordinates. Captures live in server
memory and do not mutate `Config.Towers` or the authoritative `TowerRegistry`.

`config/deployment_drafts.lua` contains first-pass map anchors for the same
site IDs. They are explicitly draft-only waypoints. The editor draws a map
blip and a visible blue radius blip for each draft; a captured site is shown
in green. The point blip and the 3D world marker are only location anchors: the
3D marker is intentionally small and is not the coverage area. The actual
coverage radius is the translucent circle on the pause map and is also printed
in the preview label. Draft anchors are never loaded into `Config.Towers` and
must be replaced by a real FiveM capture before export. When the feature flag
and development convar are off, the runtime leaves `Config.DeploymentDrafts`
empty and no draft payload is sent to clients.

## Enable it in a development server

Enable it with the server convar before starting the resource:

```text
setr gnsh_telecom_deployment_tools 1
ensure gnsh-telecom
```

The resource feature flag remains `false` in production defaults. A
development-only config overlay may instead set
`Config.Features.DeploymentTools = true` before the server scripts load. The
tool is always ACE/admin protected through `Config.Debug.adminAce`, `admin`,
`god`, `command` or txAdmin admin state.

## Capture workflow

1. Run `/telecom_tower_help` or `/telecom_tower_list`.
2. Run `/telecom_tower_drafts`. Open the pause map to see the draft blips and
   blue radius circles for all planned sites. If circles overlap or are outside
   the current map viewport, run `/telecom_tower_preview <siteId>` and zoom to
   that one site; its map circle is the coverage visualization.
3. Drive to the draft marker and inspect the actual ground, rooftop or road
   location. The draft marker is fixed; it does not follow the player.
4. Optionally preview one site with `/telecom_tower_preview LS-DOWNTOWN-01`.
   A draft-backed preview is fixed at its draft coordinate; a site without a
   draft falls back to following the player.
5. If needed, choose another profile with
   `/telecom_tower_archetype LS-DOWNTOWN-01 TOWN_MACRO`.
6. Move to the final, visually validated point, face the intended antenna
   direction, then capture the server-authoritative player position with
   `/telecom_tower_capture LS-DOWNTOWN-01`.
7. The captured marker/radius is updated to the new position. Use
   `/telecom_tower_nearest` to inspect the nearest captured site while
   moving between locations. Use `/telecom_tower_remove_preview` to clear the
   marker, `/telecom_tower_clear_drafts` to hide all draft markers, or
   `/telecom_tower_remove_capture <siteId>` to discard a capture.
8. Run `/telecom_tower_export` from the server console or as an admin. Copy
   the deterministic entries inside the existing `Config.Towers = { ... }`
   table in `config/towers.lua` only after checking every position, altitude,
   ground/rooftop placement and intended coverage. The export is append-safe
   and does not replace existing towers or backhaul configuration.
9. Turn the convar off and restart the resource before production use:

```text
setr gnsh_telecom_deployment_tools 0
restart gnsh-telecom
```

Captures are intentionally lost on resource restart. This prevents an
unreviewed development capture from silently becoming production topology.

## Commands

| Command | Purpose |
| --- | --- |
| `/telecom_tower_editor` | Toggle the local preview editor |
| `/telecom_tower_list` | List the coordinate-free site catalog |
| `/telecom_tower_drafts` | Show all development draft blips and radius circles |
| `/telecom_tower_clear_drafts` | Hide all development draft blips |
| `/telecom_tower_preview <siteId>` | Preview a catalog site and its radius |
| `/telecom_tower_archetype <siteId> <class>` | Select a reusable archetype for the preview |
| `/telecom_tower_capture <siteId>` | Capture the server-authoritative player position |
| `/telecom_tower_nearest` | Inspect the nearest capture, or production tower if no capture exists |
| `/telecom_tower_export` | Print deterministic `Config.Towers` definitions |
| `/telecom_tower_remove_preview` | Remove the local preview marker |
| `/telecom_tower_remove_capture <siteId>` | Remove a captured site from the current session |

The tool does not decide final topology coverage by itself. It is an authoring
aid for collecting real coordinates; heatmap and golden-anchor validation come
after the verified positions are placed in the production topology.
