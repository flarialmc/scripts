name = "StrongHold Finder"
description = "Find the StrongHold using only two ender pearls and a little math"
author = "zebedelu"

local CaptureKey = settings.addKeybind("Position capture key", "Capture Ender Pearl Position", "y")
local ClearLatestCapture = settings.addKeybind("Clear latest capture", "Clear Capture", "u")
local ShowResultKey = settings.addKeybind("Show the distance", "Show result", "i")
local CreateWaypointKey = settings.addKeybind("Create a waypoint to StrongHold", "Create waypoint", "o")

local WaypointCreated = true
local EstimatedCoordinates = {nil, nil}
local PlayerInfo = {}

local InseringKeyBug1 = true
local InseringKeyBug2 = true
local InseringKeyBug3 = true
local InseringKeyBug4 = true

local LatestCaptureKey = false
local LatestClearLatestCapture = false
local LatestShowResultKey = false
local LatestCreateWaypointKey = false

function EuclideDistance(x1, z1, x2, z2)
    return math.sqrt((x2 - x1)^2 + (z2 - z1)^2)
end

function YawToDirection(yawDeg)
    local yawRad = math.rad(yawDeg)
    local dx = -math.sin(yawRad)
    local dz = math.cos(yawRad)
    return dx, dz
end

function LineIntersection(x1, z1, dx1, dz1, x2, z2, dx2, dz2)
    local det = dx1 * dz2 - dz1 * dx2

    if math.abs(det) < 0.000001 then
        return nil
    end

    local t = ((x2 - x1) * dz2 - (z2 - z1) * dx2) / det
    local x = x1 + t * dx1
    local z = z1 + t * dz1

    return x, z
end

function EstimateStrongholdFromCaptures(captures)
    local sumX = 0
    local sumZ = 0
    local sumWeight = 0

    for i = 1, #captures - 1 do
        local a = captures[i]
        local dx1, dz1 = YawToDirection(a.yaw)

        for j = i + 1, #captures do
            local b = captures[j]
            local dx2, dz2 = YawToDirection(b.yaw)

            local det = dx1 * dz2 - dz1 * dx2
            if math.abs(det) > 0.000001 then
                local ix, iz = LineIntersection(a.x, a.z, dx1, dz1, b.x, b.z, dx2, dz2)

                if ix and iz then
                    local weight = math.abs(det)
                    sumX = sumX + (ix * weight)
                    sumZ = sumZ + (iz * weight)
                    sumWeight = sumWeight + weight
                end
            end
        end
    end

    if sumWeight == 0 then
        return nil, nil, 0
    end

    return sumX / sumWeight, sumZ / sumWeight
end

onEvent("TickEvent", function()
    if CaptureKey.value then
        if InseringKeyBug1 then
            LatestCaptureKey = true
            InseringKeyBug1 = false
        end
    end
    if ClearLatestCapture.value then
        if InseringKeyBug2 then
            LatestClearLatestCapture = true
            InseringKeyBug2 = false
        end
    end
    if ShowResultKey.value then
        if InseringKeyBug3 then
            LatestShowResultKey = true
            InseringKeyBug3 = false
        end
    end
    if CreateWaypointKey.value then
        if InseringKeyBug4 then
            LatestCreateWaypointKey = true
            InseringKeyBug4 = false
        end
    end
    
    if CaptureKey.value and not LatestCaptureKey then

        local x, _, z = player.position()
        local yaw = player.rotation().y

        table.insert(PlayerInfo, {
            x = x,
            z = z,
            yaw = yaw
        })

        client.displayLocalMessage(
            string.format("§l§f<SHFinder>§r one capture added: [%d]", #PlayerInfo)
        )
    end

    if ClearLatestCapture.value and not LatestClearLatestCapture then
        if #PlayerInfo > 0 then
            table.remove(PlayerInfo, #PlayerInfo)
            client.displayLocalMessage(
                string.format("§l§f<SHFinder>§r removed latest capture: [%d]", #PlayerInfo)
            )
        end
        InseringKeyBug2 = false
    end

    if ShowResultKey.value and not LatestShowResultKey then
        if #PlayerInfo < 2 then
            client.displayLocalMessage("§l§f<SHFinder>§r need at least 2 captures: [%d]", #PlayerInfo)
        else
            local sx, sz = EstimateStrongholdFromCaptures(PlayerInfo)

            if sx and sz then
                local px, _, pz = player.position()
                local distance = EuclideDistance(px, pz, sx, sz)

                client.displayLocalMessage(
                    string.format(
                        "§l§f<SHFinder>§r estimated Stronghold: X=%.2f Z=%.2f | Distance: %.2f",
                        sx, sz, distance
                    )
                )
                EstimatedCoordinates = {sx, sz}
            else
                client.displayLocalMessage("§l§f<SHFinder>§r could not calculate a stable result")
            end
        end
    end

    if CreateWaypointKey.value and not LatestCreateWaypointKey then
        local SomeError = true
        if EstimatedCoordinates[1] == nil then
            local sx, sz = EstimateStrongholdFromCaptures(PlayerInfo)
            EstimatedCoordinates = {sx, sz}
            if EstimatedCoordinates[1] == nil then
                client.displayLocalMessage("§l§f<SHFinder>§r no capture defined")
                SomeError = false
            end
        end
        if WaypointCreated then
            client.displayLocalMessage("§l§f<SHFinder>§r waypoint already created!")
            SomeError = false
        end
        if #PlayerInfo < 2 then
            client.displayLocalMessage("§l§f<SHFinder>§r need at least 2 captures: [%d]", #PlayerInfo)
            SomeError = false
        end
        if SomeError then
            player.say(
                string.format(".waypoint add %d 100 %d", math.floor(EstimatedCoordinates[1]), math.floor(EstimatedCoordinates[2]))
            )
            WaypointCreated = true
        end
    end

    LatestCaptureKey = CaptureKey.value
    LatestClearLatestCapture = ClearLatestCapture.value
    LatestShowResultKey = ShowResultKey.value
    LatestCreateWaypointKey = CreateWaypointKey.value
end)