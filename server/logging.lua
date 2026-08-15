Log = {}

local levels = { debug = 1, info = 2, warn = 3, error = 4 }
local prefix = '[gnsh-telecom]'

local function currentLevel()
    local configured = Config.Debug and Config.Debug.logLevel or 'info'
    return levels[configured] or levels.info
end

local function serialize(value)
    if value == nil then return '' end
    if type(value) ~= 'table' then return tostring(value) end

    local parts = {}
    for key, item in pairs(value) do
        parts[#parts + 1] = ('%s=%s'):format(tostring(key), tostring(item))
    end
    table.sort(parts)
    return table.concat(parts, ' ')
end

local function write(level, message, data)
    if levels[level] < currentLevel() then return end
    local suffix = serialize(data)
    if suffix ~= '' then message = ('%s [%s]'):format(message, suffix) end
    print(('%s %s'):format(prefix, message))
end

function Log.debug(message, data) write('debug', tostring(message), data) end
function Log.info(message, data) write('info', tostring(message), data) end
function Log.warn(message, data) write('warn', tostring(message), data) end
function Log.error(message, data) write('error', tostring(message), data) end

function Log.event(code, data)
    write('info', ('event=%s'):format(tostring(code)), data)
end
