name = "Buried Treasure Finder"
description = "Scans the area around the player and lists buried treasure near"
author = "zebedelu"

local Radius = settings.addSlider("Radius (in chunks)", "Search radius (chunks)", 4, 40, 1, false)
local UseInterval = settings.addToggle(
    "Auto Scan",
    "If enabled, scans automatically on a timer instead of using the keybind",
    false
)
local Interval = settings.addSlider(
    "Interval",
    "Time between automatic scans (seconds)",
    1, 10, 1, false
)
local ScanButton = settings.addKeybind(
    "Scan",
    "Press to scan for the chest"
)

local LatestScanButtonKey = false
local IntervalLoop = 0
local chestsFind = {}
local chestsDistances = {}
local TICKS_PER_SECOND = 20
local CHEST_COLOR = {137, 109, 31, 200}

function EuclideDistance(x1, z1, x2, z2)
    return math.sqrt((x2 - x1)^2 + (z2 - z1)^2)
end

local function ScanChunksPerBuriedTreasure()
    local px, py, pz = player.position()
    local ChunkPx, ChunkPz, radius = math.floor(px/16), math.floor(pz/16), math.floor(tonumber(Radius.value))

    chestsFind = {}
    chestsDistances = {}

    for cx = ChunkPx - radius, ChunkPx + radius do
        for cz = ChunkPz - radius, ChunkPz + radius do
            local rx = (cx*16)+8
            local rz = (cz*16)+8

            for y = 40, 70 do

                local block = world.getBlock(rx, y, rz)

                if block and tostring(block):find("chest", 1, true) then
                    table.insert(chestsFind, { rx, y, rz })
                    table.insert(chestsDistances, math.floor(EuclideDistance(px, pz, rx, rz)))
                    break
                end
            end
        end
    end
end

onEvent("RenderEvent", function()
    if #chestsFind > 0 then
        for n, block in ipairs(chestsFind) do
            local _, blockX, blockY = world.worldToScreen(block[1]+0.5, block[2]+0.5, block[3]+0.5)
            local chest_size_pixels = math.min(-chestsDistances[n]*0.2+50, 30)
        	gui.button(blockX, blockY, CHEST_COLOR, {0,0,0,255}, tostring(chestsDistances[n]), chest_size_pixels, chest_size_pixels)
        end
    end
end)

onEvent("TickEvent", function()
    if UseInterval.value then
        IntervalLoop = IntervalLoop + 1

        if IntervalLoop >= Interval.value * TICKS_PER_SECOND then
            ScanChunksPerBuriedTreasure()
            IntervalLoop = 0
        end
    else
        if ScanButton.value and not LatestScanButtonKey then
            client.notify("Scaning...")
            ScanChunksPerBuriedTreasure()
            client.notify("Found "..#chestsFind.." near")
        end
    end

    LatestScanButtonKey = ScanButton.value
end)