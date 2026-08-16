# Troubleshooting

## Resource refuses to start

Read the lines immediately after `CONFIG_INVALID`. Coordinate errors must use numeric `x`, `y`, `z`; a string such as `vector3(...)` pasted inside quotes is not a coordinate. Duplicate tower IDs and unsupported technologies also stop startup.

## Strong signal but no data

Inspect the connection state and check `services.data.reason`/`blockedBy`. `OVERLOADED`, an active service failure, an offline tower or an offline backhaul route can block data while radio signal remains visible.

## Debug command is unauthorized

Server admin status and the resource ACE are separate permission providers. Use `add_ace group.admin gnsh-telecom.admin allow`, or ensure the existing `admin`, `god` or `command` ACE is granted. The server console is trusted automatically.

## Persistence is degraded

The core stays authoritative in memory. Check oxmysql state, migration output and the configured adapter. Once the database returns, queued failure/audit writes are retried; current player connections are intentionally not restored from the database.

## NOC does not open

Confirm `Config.Features.NOC = true`, the configured ACE, and that the client command is `/telecomnoc`. A disabled NOC or unauthorized request intentionally returns no protected snapshot.
