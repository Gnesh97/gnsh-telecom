-- Optional development overlay. Load after config/examples/towers.lua only in development.
Config.Debug.enabled = true
Config.Debug.logLevel = 'debug'
Config.Features.Technician = true
Config.Features.DeploymentTools = true

Config.Bridges = Config.Bridges or {}
Config.Bridges.Notify = Config.Bridges.Notify or {
    provider = 'auto',
    fallback = 'native',
}
Config.Bridges.Progress = Config.Bridges.Progress or {
    provider = 'auto',
    fallback = 'native',
}

if type(ConfigExampleTowers) == 'table' then
    Config.Towers = ConfigExampleTowers
end

if type(ConfigExampleBackhaul) == 'table' then
    Config.Backhaul = ConfigExampleBackhaul
end
