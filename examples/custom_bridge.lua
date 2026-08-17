-- Load this template from the external resource that owns the provider.
-- It deliberately contains no Telecom Core changes.

local providerName = 'my-phone'
local dependency = 'my-phone-resource'

local ok, registrationOrError = exports['gnsh-telecom']:RegisterBridge('phone', {
    name = providerName,
    resources = { dependency },
    priority = 500,
    capabilities = { 'GetNetworkState' },

    Detect = function(self)
        return GetResourceState(self.resources[1]) == 'started'
    end,

    Initialize = function()
        return true
    end,

    Shutdown = function()
        return true
    end,

    HealthCheck = function()
        return 'ACTIVE'
    end,

    GetNetworkState = function(_, source)
        -- Replace this call with the external phone resource's server export.
        return exports[dependency]:GetNetworkState(source)
    end,
})

if not ok then
    print(('[my-resource] Telecom bridge registration failed: %s')
        :format(tostring(registrationOrError)))
end
