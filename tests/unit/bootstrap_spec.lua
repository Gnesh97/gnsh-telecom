TEST('server bootstrap starts clean without framework or phone', function()
    ASSERT_FALSE(Bootstrap.IsStarted())
    ASSERT_TRUE(Bootstrap.Boot())
    ASSERT_TRUE(Bootstrap.IsStarted())
    ASSERT_EQ(TowerRegistry.Count(), #Config.Towers)
    Bootstrap.Shutdown()
    ASSERT_FALSE(Bootstrap.IsStarted())
end)

TEST('disabled carrier bootstrap ignores malformed optional definitions', function()
    local previousEnabled = Config.Features.Carriers
    local previousDefinitions = Config.Carriers
    Config.Features.Carriers = false
    Config.Carriers = { { id = 'invalid-disabled-definition' } }
    ASSERT_TRUE(Bootstrap.Boot())
    ASSERT_TRUE(Bootstrap.IsStarted())
    Bootstrap.Shutdown()
    Config.Carriers = previousDefinitions
    Config.Features.Carriers = previousEnabled
end)
