-- Optional development overlay. Load after config/examples/towers.lua only in development.
Config.Debug.enabled = true
Config.Debug.logLevel = 'debug'
Config.Features.Technician = true

if type(ConfigExampleTowers) == 'table' then
    Config.Towers = ConfigExampleTowers
end

if type(ConfigExampleBackhaul) == 'table' then
    Config.Backhaul = ConfigExampleBackhaul
end
