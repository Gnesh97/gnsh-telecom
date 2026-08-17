TelecomDeploymentEditor = TelecomDeploymentEditor or {}

local function configTable(config)
    return type(config) == 'table' and config or Config or {}
end

local function copy(value)
    if Utils and Utils.DeepCopy then return Utils.DeepCopy(value) end
    if type(value) ~= 'table' then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end

local function isFiniteNumber(value)
    if Utils and Utils.IsFiniteNumber then return Utils.IsFiniteNumber(value) end
    return type(value) == 'number' and value == value
        and value ~= math.huge and value ~= -math.huge
end

local function isPoint(value)
    local valueType = type(value)
    local supportsCoordinates = valueType == 'table'
        or valueType == 'userdata'
        or valueType == 'vector3'
    return supportsCoordinates
        and isFiniteNumber(value.x)
        and isFiniteNumber(value.y)
        and isFiniteNumber(value.z)
end

local function normalizeAngle(value)
    if not isFiniteNumber(value) then return nil end
    return ((value % 360) + 360) % 360
end

local function addError(errors, message)
    errors[#errors + 1] = message
end

local function knownArchetype(name, config)
    return TelecomDeployment
        and TelecomDeployment.IsKnownArchetype
        and TelecomDeployment.IsKnownArchetype(name, config) == true
end

local function knownCoverageZone(name, config)
    return TelecomDeployment
        and TelecomDeployment.IsKnownCoverageZone
        and TelecomDeployment.IsKnownCoverageZone(name, config) == true
end

local function sortedCopies(values)
    local result = {}
    for _, value in ipairs(values or {}) do
        result[#result + 1] = copy(value)
    end
    table.sort(result, function(left, right)
        return tostring(left.id) < tostring(right.id)
    end)
    return result
end

local function quote(value)
    local text = tostring(value or '')
    text = text:gsub('\\', '\\\\')
    text = text:gsub("'", "\\'")
    text = text:gsub('\r', '\\r')
    text = text:gsub('\n', '\\n')
    return "'" .. text .. "'"
end

local function formatNumber(value)
    return ('%.2f'):format(tonumber(value) or 0)
end

local function formatTechnologies(technologies)
    local values = {}
    for _, technology in ipairs(technologies or {}) do
        values[#values + 1] = quote(technology)
    end
    if #values == 0 then values[1] = quote('4G') end
    return '{ ' .. table.concat(values, ', ') .. ' }'
end

local function validateTechnologyList(technologies, prefix, errors)
    if type(technologies) ~= 'table' or #technologies == 0 then
        addError(errors, prefix .. ' must not be empty')
        return
    end

    local seen = {}
    for index, technology in ipairs(technologies) do
        if type(technology) ~= 'string' then
            addError(errors, ('%s[%d] must be a string'):format(prefix, index))
        elseif seen[technology] then
            addError(errors, ('%s[%d] duplicates %s')
                :format(prefix, index, technology))
        else
            seen[technology] = true
            local supported = Technologies
                and Technologies.IsSupported
                and Technologies.IsSupported(technology)
            if not supported then
                addError(errors, ('%s[%d] is unsupported'):format(prefix, index))
            end
        end
    end
end

function TelecomDeploymentEditor.IsEnabled(config)
    local current = configTable(config)
    return current.Features
        and current.Features.DeploymentTools == true
        or false
end

function TelecomDeploymentEditor.FindSite(siteId, config)
    if type(siteId) ~= 'string' or siteId == '' then return nil end
    local current = configTable(config)
    for _, site in ipairs(current.DeploymentSites or {}) do
        if type(site) == 'table' and site.id == siteId then
            return copy(site)
        end
    end
    return nil
end

function TelecomDeploymentEditor.ValidateCatalog(config)
    local current = configTable(config)
    local errors = {}
    local sites = current.DeploymentSites

    if sites == nil then return true, errors end
    if type(sites) ~= 'table' then
        return false, { 'DeploymentSites must be a table' }
    end
    if TelecomDeploymentEditor.IsEnabled(current) and #sites == 0 then
        addError(errors, 'DeploymentSites must not be empty when deployment tools are enabled')
    end

    local seen = {}
    local highestIndex = 0
    for key in pairs(sites) do
        if type(key) ~= 'number' or key ~= math.floor(key) or key < 1 then
            addError(errors, 'DeploymentSites must be a contiguous array')
        elseif key > highestIndex then
            highestIndex = key
        end
    end

    for index = 1, highestIndex do
        local site = sites[index]
        local prefix = ('DeploymentSites[%d]'):format(index)
        if type(site) ~= 'table' then
            addError(errors, prefix .. ' must be a table')
        else
            if type(site.id) ~= 'string' or site.id == '' then
                addError(errors, prefix .. '.id must be a non-empty string')
            elseif #site.id > 64 then
                addError(errors, prefix .. '.id must not exceed 64 characters')
            elseif seen[site.id] then
                addError(errors, ('duplicate deployment site id: %s'):format(site.id))
            else
                seen[site.id] = true
            end

            if site.coords ~= nil then
                addError(errors, prefix .. '.coords must be omitted from the coordinate-free catalog')
            end
            if not knownArchetype(site.class, current) then
                addError(errors, prefix .. '.class is not a known tower archetype')
            end
            if not knownCoverageZone(site.coverageZone, current) then
                addError(errors, prefix .. '.coverageZone is not a known coverage zone')
            end
            if type(site.purpose) ~= 'string' or site.purpose == '' then
                addError(errors, prefix .. '.purpose must be a non-empty string')
            elseif #site.purpose > 160 then
                addError(errors, prefix .. '.purpose must not exceed 160 characters')
            end

            validateTechnologyList(site.technologies, prefix .. '.technologies', errors)
        end
    end

    return #errors == 0, errors
end

function TelecomDeploymentEditor.SelectArchetype(site, class, config)
    if type(site) ~= 'table' or type(site.id) ~= 'string' then
        return nil, 'unknown_site'
    end
    if not knownArchetype(class, configTable(config)) then
        return nil, 'unknown_archetype'
    end
    local selected = copy(site)
    selected.class = class
    return selected
end

function TelecomDeploymentEditor.BuildCapture(site, coords, heading, config)
    if type(site) ~= 'table' or type(site.id) ~= 'string' then
        return nil, 'unknown_site'
    end
    if not isPoint(coords) then return nil, 'invalid_coordinates' end
    if heading ~= nil and not isFiniteNumber(heading) then
        return nil, 'invalid_heading'
    end
    if not knownArchetype(site.class, configTable(config)) then
        return nil, 'unknown_archetype'
    end
    if not knownCoverageZone(site.coverageZone, configTable(config)) then
        return nil, 'unknown_coverage_zone'
    end

    local normalizedHeading = heading and normalizeAngle(heading) or nil
    return {
        id = site.id,
        class = site.class,
        coverageZone = site.coverageZone,
        purpose = site.purpose,
        technologies = copy(site.technologies or { '4G' }),
        coords = {
            x = coords.x,
            y = coords.y,
            z = coords.z,
        },
        heading = normalizedHeading,
    }
end

function TelecomDeploymentEditor.ValidateCapture(capture, config)
    local current = configTable(config)
    local errors = {}
    if type(capture) ~= 'table' then
        return false, { 'capture must be a table' }
    end
    if type(capture.id) ~= 'string' or capture.id == '' then
        addError(errors, 'capture.id must be a non-empty string')
    end

    local site = TelecomDeploymentEditor.FindSite(capture.id, current)
    if not site then
        addError(errors, 'capture.id is not present in DeploymentSites')
    elseif capture.coverageZone ~= site.coverageZone then
        addError(errors, 'capture.coverageZone does not match its deployment site')
    end
    if not isPoint(capture.coords) then
        addError(errors, 'capture.coords must contain finite x, y and z')
    end
    if not knownArchetype(capture.class, current) then
        addError(errors, 'capture.class is not a known tower archetype')
    end
    if not knownCoverageZone(capture.coverageZone, current) then
        addError(errors, 'capture.coverageZone is not a known coverage zone')
    end
    if type(capture.purpose) ~= 'string' or capture.purpose == '' then
        addError(errors, 'capture.purpose must be a non-empty string')
    end
    validateTechnologyList(capture.technologies, 'capture.technologies', errors)

    local archetype = current.TowerArchetypes
        and current.TowerArchetypes[capture.class]
    if type(archetype) ~= 'table'
        or not isFiniteNumber(archetype.coverageRadius)
        or archetype.coverageRadius <= 0
        or not isFiniteNumber(archetype.capacity)
        or archetype.capacity <= 0 then
        addError(errors, 'capture archetype defaults are invalid')
    end

    local deployment = current.Deployment
    if type(deployment) ~= 'table'
        or not isFiniteNumber(deployment.defaultCoverageMinimum)
        or deployment.defaultCoverageMinimum < 0
        or deployment.defaultCoverageMinimum > 100 then
        addError(errors, 'capture deployment minimum is invalid')
    end
    if capture.heading ~= nil and not isFiniteNumber(capture.heading) then
        addError(errors, 'capture.heading must be finite when provided')
    end

    return #errors == 0, errors
end

function TelecomDeploymentEditor.ListCaptures(captures)
    local values = {}
    if type(captures) ~= 'table' then return values end

    if #captures > 0 then
        for _, capture in ipairs(captures) do
            if type(capture) == 'table' then values[#values + 1] = copy(capture) end
        end
    else
        for _, capture in pairs(captures) do
            if type(capture) == 'table' then values[#values + 1] = copy(capture) end
        end
    end

    table.sort(values, function(left, right)
        return tostring(left.id) < tostring(right.id)
    end)
    return values
end

function TelecomDeploymentEditor.NearestCapture(captures, coords)
    if not isPoint(coords) then return nil end
    local nearest
    local nearestDistance

    for _, capture in ipairs(TelecomDeploymentEditor.ListCaptures(captures)) do
        if isPoint(capture.coords) then
            local deltaX = capture.coords.x - coords.x
            local deltaY = capture.coords.y - coords.y
            local deltaZ = capture.coords.z - coords.z
            local distance = math.sqrt(deltaX * deltaX + deltaY * deltaY + deltaZ * deltaZ)
            if nearestDistance == nil
                or distance < nearestDistance
                or (distance == nearestDistance and capture.id < nearest.id) then
                nearest = capture
                nearestDistance = distance
            end
        end
    end

    if not nearest then return nil end
    nearest.distance = nearestDistance
    return nearest
end

function TelecomDeploymentEditor.FormatSiteList(config)
    local lines = {}
    for _, site in ipairs(sortedCopies(configTable(config).DeploymentSites or {})) do
        lines[#lines + 1] = ('%s | %s | %s | %s')
            :format(site.id, site.class, site.coverageZone, site.purpose)
    end
    return lines
end

function TelecomDeploymentEditor.FormatExport(captures, config)
    local current = configTable(config)
    local lines = {
        '-- Generated by /telecom_tower_export.',
        '-- Paste these entries inside the existing Config.Towers table.',
        '-- This output never replaces existing towers or backhaul configuration.',
    }

    local ordered = TelecomDeploymentEditor.ListCaptures(captures)
    local seen = {}
    for _, capture in ipairs(ordered) do
        local valid, errors = TelecomDeploymentEditor.ValidateCapture(capture, current)
        if not valid then return nil, errors end
        if seen[capture.id] then
            return nil, { ('duplicate capture id: %s'):format(capture.id) }
        end
        seen[capture.id] = true

        local archetype = current.TowerArchetypes
            and current.TowerArchetypes[capture.class] or {}
        local deployment = current.Deployment or {}
        local radius = archetype.coverageRadius or 1
        local capacity = archetype.capacity or 1
        local minimum = deployment.defaultCoverageMinimum or 0
        local coordinates = capture.coords or {}

        lines[#lines + 1] = '    {'
        lines[#lines + 1] = ('        id = %s,'):format(quote(capture.id))
        lines[#lines + 1] = ('        class = %s,'):format(quote(capture.class))
        lines[#lines + 1] = ('        coverageZone = %s,'):format(quote(capture.coverageZone))
        lines[#lines + 1] = ('        purpose = %s,'):format(quote(capture.purpose))
        lines[#lines + 1] = ('        coords = vector3(%s, %s, %s),')
            :format(
                formatNumber(coordinates.x),
                formatNumber(coordinates.y),
                formatNumber(coordinates.z)
            )
        lines[#lines + 1] = '        coverage = {'
        lines[#lines + 1] = ('            radius = %s,'):format(formatNumber(radius))
        lines[#lines + 1] = ('            minimum = %s,'):format(formatNumber(minimum))
        lines[#lines + 1] = '        },'
        lines[#lines + 1] = ('        technologies = %s,'):format(
            formatTechnologies(capture.technologies)
        )
        lines[#lines + 1] = '        capacity = {'
        lines[#lines + 1] = ('            maximum = %s,'):format(formatNumber(capacity))
        lines[#lines + 1] = '        },'
        if capture.heading ~= nil then
            lines[#lines + 1] = ('        -- capturedHeading = %s; validate before using as sector azimuth')
                :format(formatNumber(capture.heading))
        end
        lines[#lines + 1] = '    },'
    end

    return lines
end
