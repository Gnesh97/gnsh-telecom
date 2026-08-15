ServicePolicy = {
    Names = { 'voice', 'sms', 'data', 'gps', 'emergency' },
}

function ServicePolicy.GetMinimumSignal(service)
    local policy = Config.Services and Config.Services[service]
    return policy and policy.minimumSignal or nil
end
