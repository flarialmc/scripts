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
    1, 10, 1, false)
local BlockName = settings.addTextBox(
    "Block",
    "Name (or part of the name) of the block to search for",
    "chest",50)
local ScanButton = settings.addKeybind(
    "Scan",
    "Press to scan for the block"
)

local LatestScanButtonKey = false
local IntervalLoop = 0
local blocksFound = {}
local TICKS_PER_SECOND = 20

local function ScanBlocks()
    local px, py, pz = player.position()
    px, py, pz = math.floor(px), math.floor(py), math.floor(pz)

    local radius = math.floor(tonumber(Radius.value))

    blocksFound = {}

    if BlockName.value == "" then
        return
    end

    for x = px - radius, px + radius do
        for y = py - radius, py + radius do
            for z = pz - radius, pz + radius do

                local block = world.getBlock(x, y, z)

                if tostring(block):find(BlockName.value, 1, true) then

                    table.insert(blocksFound, {x,y,z})
                end
            end
        end
    end
end

onEvent("RenderEvent", function()
	ImGui.SetNextWindowSize({350, 300}, 4)
	ImGui.SetNextWindowBgAlpha(0.6)
    ImGui.Begin("SimpleBlockFinder")
    ImGui.Text("Blocks found nearby:")
    ImGui.Text(string.format("Radius: %d | Block: %s", math.floor(tonumber(Radius.value)), BlockName.value))

    if #blocksFound > 0 then
        for n, block in ipairs(blocksFound) do
            ImGui.BulletText(string.format("X: %d Y: %d Z: %d", block[1], block[2]+1, block[3]))
        end
    else
        ImGui.Text("No blocks found yet.")
    end
    
    ImGui.End()
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