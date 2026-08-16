local function resetJammerState()
    Jammers.Reset()
    TelecomRateLimit.Clear(41)
    TelecomRateLimit.Clear(42)
    Config.Features.Jammers = true
end

TEST('jammer reduces signal for matching technologies inside its radius', function()
    resetJammerState()
    local position = vector3(0, 0, 0)
    local ok, record = Jammers.Create(41, position, {
        radius = 100,
        strength = 0.75,
        durationMs = 600000,
        technologies = { '4G' },
    })

    ASSERT_TRUE(ok)
    ASSERT_TRUE(record.id ~= nil)

    local affected = Jammers.GetEffect(vector3(50, 0, 0), { '4G' })
    ASSERT_TRUE(affected.active)
    ASSERT_EQ(affected.multiplier, 0.25)

    local unaffected = Jammers.GetEffect(vector3(50, 0, 0), { '3G' })
    ASSERT_FALSE(unaffected.active)
    ASSERT_EQ(unaffected.multiplier, 1.0)

    local outside = Jammers.GetEffect(vector3(101, 0, 0), { '4G' })
    ASSERT_FALSE(outside.active)
    ASSERT_EQ(outside.multiplier, 1.0)
end)

TEST('jammer validates limits and restores neutral effects when removed', function()
    resetJammerState()
    local position = vector3(0, 0, 0)

    local invalidRadius, radiusError = Jammers.Create(41, position, { radius = 0 })
    ASSERT_FALSE(invalidRadius)
    ASSERT_EQ(radiusError, 'invalid_jammer_radius')

    local invalidStrength, strengthError = Jammers.Create(41, position, { strength = 1.1 })
    ASSERT_FALSE(invalidStrength)
    ASSERT_EQ(strengthError, 'invalid_jammer_strength')

    local ok, record = Jammers.Create(42, position, { radius = 100, strength = 0.5 })
    ASSERT_TRUE(ok)
    ASSERT_TRUE(Jammers.Remove(record.id, 42, false))

    local restored = Jammers.GetEffect(position, { '4G' })
    ASSERT_FALSE(restored.active)
    ASSERT_EQ(restored.multiplier, 1.0)
end)

TEST('disabled jammer feature fails closed and returns neutral effect', function()
    resetJammerState()
    Config.Features.Jammers = false

    local ok, errorCode = Jammers.Create(41, vector3(0, 0, 0), {})
    ASSERT_FALSE(ok)
    ASSERT_EQ(errorCode, 'jammers_disabled')

    local effect = Jammers.GetEffect(vector3(0, 0, 0), { '4G' })
    ASSERT_FALSE(effect.active)
    ASSERT_EQ(effect.multiplier, 1.0)

    Config.Features.Jammers = true
end)

TEST('jammer network event rejects malformed payloads before state mutation', function()
    resetJammerState()
    local previousSource = rawget(_G, 'source')
    rawset(_G, 'source', 41)

    TriggerTestEvent(Constants.Events.JAMMER_REQUEST, {
        action = 'create',
        coords = vector3(0, 0, 0),
        radius = math.huge,
    })
    TriggerTestEvent(Constants.Events.JAMMER_REQUEST, {
        action = 'create',
        coords = vector3(0, 0, 0),
        technologies = { string.rep('x', 9) },
    })
    TriggerTestEvent(Constants.Events.JAMMER_REQUEST, {
        action = 'remove',
        id = string.rep('x', 65),
    })

    rawset(_G, 'source', previousSource)
    ASSERT_EQ(#Jammers.GetAll(), 0)
end)

resetJammerState()
