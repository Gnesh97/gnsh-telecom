FailureScheduler = FailureScheduler or {}

local running = false
local tickHandler

local function interval()
    local value = Config and Config.FailureScheduler
        and Config.FailureScheduler.intervalMs
    if type(value) ~= 'number' or value <= 0 then return 60000 end
    return value
end

function FailureScheduler.SetTickHandler(handler)
    if handler ~= nil and type(handler) ~= 'function' then return false end
    tickHandler = handler
    return true
end

function FailureScheduler.Start()
    if running then return false, 'scheduler_already_running' end
    if not Config or not Config.FailureScheduler
        or Config.FailureScheduler.enabled ~= true then
        return false, 'automatic_failures_disabled'
    end
    if type(CreateThread) ~= 'function' or type(Wait) ~= 'function' then
        return false, 'scheduler_unavailable'
    end

    running = true
    CreateThread(function()
        while running do
            Wait(interval())
            if running and tickHandler then pcall(tickHandler) end
        end
    end)
    return true
end

function FailureScheduler.Stop()
    running = false
    return true
end

function FailureScheduler.IsRunning()
    return running
end
