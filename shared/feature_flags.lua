function Config.IsFeatureEnabled(name)
    return Config.Features and Config.Features[name] == true
end
