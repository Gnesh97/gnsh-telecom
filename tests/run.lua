-- Framework-free unit test runner for pure Lua modules.

local passed, failed = 0, 0

function TEST(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
        print(('  [PASS] %s'):format(name))
    else
        failed = failed + 1
        print(('  [FAIL] %s -- %s'):format(name, tostring(err)))
    end
end

function ASSERT_EQ(actual, expected, message)
    if actual ~= expected then
        error(('%s (expected %s, got %s)'):format(
            message or 'values differ', tostring(expected), tostring(actual)
        ), 2)
    end
end

function ASSERT_TRUE(value, message)
    if not value then error(message or 'expected truthy value', 2) end
end

function ASSERT_FALSE(value, message)
    if value then error(message or 'expected falsy value', 2) end
end

function ASSERT_ERROR(fn, message)
    local ok = pcall(fn)
    if ok then error(message or 'expected function to fail', 2) end
end

function vector3(x, y, z)
    return { x = x, y = y, z = z }
end

dofile('shared/config.lua')
dofile('shared/constants.lua')
dofile('shared/enums.lua')
dofile('shared/technologies.lua')
dofile('shared/feature_flags.lua')
dofile('shared/utils.lua')
dofile('locales/en.lua')
dofile('locales/tr.lua')
dofile('server/towers/validation.lua')
dofile('server/towers/state.lua')
dofile('server/towers/registry.lua')
dofile('server/towers/spatial_index.lua')
dofile('server/network/signal.lua')
dofile('server/network/coverage.lua')
dofile('server/network/selection.lua')

local eventHandlers = {}
AddEventHandler = function(name, handler) eventHandlers[name] = handler end
GetCurrentResourceName = function() return 'gnsh-telecom' end
GetResourceState = function() return 'stopped' end
StopResource = function() end
dofile('server/network/connections.lua')
dofile('client/state.lua')
dofile('server/logging.lua')
dofile('server/bootstrap.lua')

print('gnsh-telecom — pure Lua unit tests')
print('')

dofile('tests/unit/foundation_spec.lua')
dofile('tests/unit/tower_registry_spec.lua')
dofile('tests/unit/spatial_index_spec.lua')
dofile('tests/unit/coverage_spec.lua')
dofile('tests/unit/selection_spec.lua')
dofile('tests/unit/connections_spec.lua')
dofile('tests/unit/client_state_spec.lua')
dofile('tests/unit/bootstrap_spec.lua')

print('')
print(('%d passed, %d failed'):format(passed, failed))

if failed > 0 then os.exit(1) end
