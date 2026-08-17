PerformanceMetrics = PerformanceMetrics or {}

local function round(value, places)
    local factor = 10 ^ (places or 3)
    return math.floor(value * factor + 0.5) / factor
end

local function memoryKb()
    return collectgarbage('count')
end

function PerformanceMetrics.NewRun(name, dimensions)
    return {
        name = name,
        dimensions = dimensions or {},
        samples = {},
    }
end

function PerformanceMetrics.Measure(run, label, operations, callback)
    collectgarbage('collect')
    local beforeMemory = memoryKb()
    local startedAt = os.clock()
    local ok, result = pcall(callback)
    local elapsed = math.max(os.clock() - startedAt, 0.000001)
    local afterMemory = memoryKb()
    if not ok then
        error(('performance sample %s failed: %s'):format(label, tostring(result)), 0)
    end

    local sample = {
        label = label,
        operations = operations or 1,
        seconds = elapsed,
        operationsPerSecond = (operations or 1) / elapsed,
        memoryDeltaKb = afterMemory - beforeMemory,
        details = type(result) == 'table' and result or {},
    }
    run.samples[#run.samples + 1] = sample
    return result, sample
end

function PerformanceMetrics.Round(value, places)
    return round(value, places)
end

function PerformanceMetrics.Render(runs)
    print('SYNTHETIC SCALE TEST')
    print('label | operations | seconds | operations/sec | memory delta KiB | details')
    for _, run in ipairs(runs or {}) do
        for _, sample in ipairs(run.samples or {}) do
            local details = {}
            for key, value in pairs(sample.details or {}) do
                details[#details + 1] = ('%s=%s'):format(key, tostring(value))
            end
            table.sort(details)
            print(('%s | %d | %.6f | %.2f | %.2f | %s'):format(
                run.name .. ' / ' .. sample.label,
                sample.operations,
                sample.seconds,
                sample.operationsPerSecond,
                sample.memoryDeltaKb,
                table.concat(details, ', ')
            ))
        end
    end
end
