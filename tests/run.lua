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

dofile('config/default.lua')
dofile('config/towers.lua')
dofile('shared/config.lua')
dofile('shared/constants.lua')
dofile('shared/enums.lua')
dofile('shared/technologies.lua')
dofile('shared/feature_flags.lua')
dofile('shared/utils.lua')
dofile('locales/en.lua')
dofile('locales/tr.lua')
dofile('shared/service_policy.lua')
dofile('server/towers/validation.lua')
dofile('server/towers/state.lua')
dofile('server/towers/registry.lua')
dofile('server/towers/spatial_index.lua')
dofile('server/network/signal.lua')
dofile('server/network/coverage.lua')
dofile('server/network/selection.lua')
dofile('server/network/capacity.lua')
dofile('server/network/services.lua')
local eventHandlers = {}
registeredExports = {}
triggeredEvents = {}
AddEventHandler = function(name, handler)
    eventHandlers[name] = eventHandlers[name] or {}
    eventHandlers[name][#eventHandlers[name] + 1] = handler
end
function TriggerTestEvent(name, ...)
    local handlers = eventHandlers[name]
    if type(handlers) ~= 'table' then
        error(('test event handler is not registered: %s'):format(name), 2)
    end
    local result
    for _, handler in ipairs(handlers) do
        result = handler(...)
    end
    return result
end
TriggerEvent = function(name, ...) triggeredEvents[#triggeredEvents + 1] = { name, ... } end
exports = function(name, handler) registeredExports[name] = handler end
GetCurrentResourceName = function() return 'gnsh-telecom' end
GetResourceState = function() return 'stopped' end
StopResource = function() end
dofile('bridges/core/capabilities.lua')
dofile('bridges/core/contracts.lua')
dofile('bridges/core/lifecycle.lua')
dofile('bridges/core/health.lua')
dofile('bridges/core/registry.lua')
dofile('bridges/core/manager.lua')
dofile('tests/unit/bridge_platform_spec.lua')
dofile('server/security/validation.lua')
dofile('server/security/rate_limit.lua')
dofile('server/maintenance/sessions.lua')
dofile('bridges/frameworks/standalone.lua')
dofile('bridges/frameworks/qb.lua')
dofile('bridges/frameworks/qbox.lua')
dofile('bridges/frameworks/esx.lua')
dofile('bridges/frameworks/custom.lua')
dofile('server/jammers.lua')
dofile('server/network/connections.lua')
dofile('client/environment.lua')
dofile('client/state.lua')
dofile('client/debug.lua')
dofile('client/technician.lua')
dofile('server/api.lua')
dofile('server/failures/types.lua')
dofile('server/failures/engine.lua')
dofile('server/failures/scheduler.lua')
dofile('server/logging.lua')
dofile('server/persistence/serializers.lua')
dofile('server/persistence/adapters/memory.lua')
dofile('server/persistence/adapters/oxmysql.lua')
dofile('server/persistence/repository.lua')
dofile('server/persistence/migrations.lua')
dofile('server/persistence/facade.lua')
dofile('server/security/txadmin.lua')
dofile('server/security/permissions.lua')
dofile('server/security/audit.lua')
dofile('server/debug.lua')
dofile('bridges/phones/core/contract.lua')
dofile('bridges/phones/core/manager.lua')
dofile('bridges/phones/generic.lua')
dofile('bridges/phones/lbphone/server.lua')
dofile('bridges/phones/npwd/server.lua')
dofile('bridges/phones/qs/server.lua')
dofile('bridges/phones/custom.lua')
dofile('server/bootstrap.lua')

print('gnsh-telecom — pure Lua unit tests')
print('')

dofile('tests/unit/foundation_spec.lua')
dofile('tests/unit/tower_registry_spec.lua')
dofile('tests/unit/spatial_index_spec.lua')
dofile('tests/unit/coverage_spec.lua')
dofile('tests/unit/selection_spec.lua')
dofile('tests/unit/capacity_spec.lua')
dofile('tests/unit/environment_spec.lua')
dofile('tests/unit/api_spec.lua')
dofile('tests/unit/phone_bridge_spec.lua')
dofile('tests/unit/phone_enforcement_spec.lua')
dofile('tests/unit/phone_client_spec.lua')
dofile('tests/unit/framework_bridge_spec.lua')
dofile('tests/unit/framework_contract_spec.lua')
dofile('tests/unit/failure_spec.lua')
dofile('tests/unit/debug_spec.lua')
dofile('tests/unit/jammers_spec.lua')
dofile('tests/unit/services_spec.lua')
dofile('tests/unit/connections_spec.lua')
dofile('tests/unit/client_state_spec.lua')
dofile('tests/unit/technician_client_spec.lua')
dofile('tests/unit/bootstrap_spec.lua')
dofile('tests/unit/persistence_serializer_spec.lua')
dofile('tests/unit/persistence_migration_spec.lua')
dofile('tests/unit/persistence_repository_spec.lua')
dofile('tests/unit/persistence_oxmysql_spec.lua')
dofile('tests/unit/persistence_facade_spec.lua')
dofile('server/incidents/severity.lua')
dofile('server/incidents/tickets.lua')
dofile('server/incidents/manager.lua')
dofile('bridges/inventory/generic.lua')
dofile('bridges/inventory/ox.lua')
dofile('bridges/inventory/qb.lua')
dofile('bridges/inventory/qs.lua')
dofile('bridges/inventory/standalone.lua')
dofile('bridges/inventory/custom.lua')
dofile('tests/unit/inventory_bridge_spec.lua')
dofile('bridges/target/generic.lua')
dofile('bridges/target/ox.lua')
dofile('bridges/target/qb.lua')
dofile('bridges/target/native.lua')
dofile('bridges/target/custom.lua')
dofile('client/interactions.lua')
dofile('bridges/dispatch/generic.lua')
dofile('tests/unit/bridge_integration_spec.lua')
dofile('tests/unit/target_bridge_spec.lua')
dofile('bridges/notify/native.lua')
dofile('bridges/notify/ox.lua')
dofile('bridges/notify/framework.lua')
dofile('bridges/progress/native.lua')
dofile('bridges/progress/ox.lua')
dofile('bridges/dispatch/native.lua')
dofile('bridges/dispatch/custom.lua')
dofile('server/maintenance/diagnostics.lua')
dofile('server/maintenance/repairs.lua')
dofile('server/maintenance/workflow.lua')
dofile('noc/server.lua')
dofile('server/statistics.lua')
dofile('tests/unit/operations_spec.lua')
dofile('tests/unit/maintenance_sessions_spec.lua')
dofile('tests/unit/support_bridge_spec.lua')
dofile('tests/unit/bridge_config_spec.lua')

print('')
print(('%d passed, %d failed'):format(passed, failed))

if failed > 0 then os.exit(1) end
