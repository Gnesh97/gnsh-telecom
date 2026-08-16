# Installation

1. Copy `gnsh-telecom` into the server's resources directory.
2. Add `ensure gnsh-telecom` after optional `oxmysql` and before resources that consume the API.
3. Edit `config/towers.lua` and add the server's tower definitions under `Config.Towers`.
4. Restart the resource and confirm `CONFIG_OK`, `RESOURCE_STARTED` and the spatial-index log.

The core does not require QBCore, Qbox, ESX, a phone resource or oxmysql. `oxmysql` is optional; when present, the persistence migration is applied automatically. Production starts with no towers and no test backhaul topology. Review [TOWER_CONFIGURATION.md](TOWER_CONFIGURATION.md) before adding the server's topology.

The files under `config/examples/` are development fixtures only. They are not loaded by the production manifest. To run the local example topology, load `config/examples/towers.lua` and then `config/development.lua` in a development-only manifest or test harness.

For admin debug commands, grant the resource ACE if the server's existing admin group does not already have one:

```text
add_ace group.admin gnsh-telecom.admin allow
```

Do not copy identifiers from another server. Keep principal mappings in the server's private `server.cfg`.
