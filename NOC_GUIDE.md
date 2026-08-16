# NOC guide

Enable `Config.Features.NOC` and grant either the configured `Config.NOC.ace` or the resource's admin permission. The player command `/telecomnoc` requests a server-built snapshot and opens the NUI. The UI is presentation-only; tower state, incidents, backhaul and statistics are calculated server-side.

The snapshot includes tower counts, average load, critical congestion count, tower runtime/failure data, incidents, backhaul route status, active jammers and optional statistics. The server caps the number of tower rows with `Config.NOC.maxTowers`.

Closing the NUI clears focus. If NOC is disabled or permission is missing, no operational snapshot is sent to the client.
