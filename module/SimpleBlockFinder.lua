name = "Simple Block Finder"
description = "Scans the area around the player and lists matching blocks nearby"
author = "zebedelu"

local Radius = settings.addSlider("Radius", "Search radius", 4, 20, 1, false)
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
local BlockName = settings.addTextBox(
    "Block",
    "Name (or part of the name) of the block to search for",
    "chest",50
)
local ScanButton = settings.addKeybind(
    "Scan",
    "Press to scan for the block"
)
local ColorButton = settings.addSlider(
    "Color Showline",
    "Colors: 1 - White, 2 - Red, 3 - Green, 4 - Blue",
    1, 4, 1, false
)

function EuclidianeDistance3D(x1, y1, z1, x2, y2, z2)
  local dx, dy, dz = x2 - x1, y2 - y1, z2 - z1
  return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local LatestScanButtonKey = false
local IntervalLoop = 0
local blocksFound = {}
local blocksDistances = {}
local TICKS_PER_SECOND = 20
local COLORS = {
    {255,255,255,255},
    {255,0,0,255},
    {0,255,0,255},
    {0,0,255,255}
}

local function ScanBlocks()
    local px, py, pz = player.position()
    px, py, pz = math.floor(px), math.floor(py), math.floor(pz)

    local radius = math.floor(tonumber(Radius.value))

    blocksFound = {}
    blocksDistances = {}

    if BlockName.value == "" then
        return
    end

    for x = px - radius, px + radius do
        for y = py - radius, py + radius do
            for z = pz - radius, pz + radius do

                local block = world.getBlock(x, y, z)

                if tostring(block):find(BlockName.value, 1, true) then

                    table.insert(blocksFound, {x,y,z})
                    table.insert(blocksDistances, math.floor(EuclidianeDistance3D(x,y,z,px,py,pz)))
                end
            end
        end
    end
end

onEvent("RenderEvent", function()
    if #blocksFound > 0 then
        for n, block in ipairs(blocksFound) do
            local _, blockX, blockY = world.worldToScreen(block[1]+0.5, block[2]+0.5, block[3]+0.5)
            local block_size_pixels = math.min(-blocksDistances[n]*0.2+50, 30)
            local color_id = COLORS[math.floor(tonumber(ColorButton.value))]
        	gui.button(blockX, blockY, color_id, color_id, tostring(blocksDistances[n]), block_size_pixels, block_size_pixels)
        end
    end
end)

onEvent("TickEvent", function()
    if UseInterval.value then
        IntervalLoop = IntervalLoop + 1

        if IntervalLoop >= Interval.value * TICKS_PER_SECOND then
            ScanBlocks()
            IntervalLoop = 0
        end
    else
        if ScanButton.value and not LatestScanButtonKey then
            ScanBlocks()
        end
    end

    LatestScanButtonKey = ScanButton.value
end)