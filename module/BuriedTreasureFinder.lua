name = "Buried Treasure Finder"
description = "Scans the area around the player and lists buried treasure near"
author = "zebedelu"

local Radius = settings.addSlider("Radius (in chunks)", "Search radius (Chunks)", 4, 10, 1, false)
local ScanButton = settings.addKeybind(
    "Scan Button",
    "Press to scan for the buried treasure"
)

local LatestScanButtonKey = false
local chestsFind = {}
local chestsDistances = {}

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
    client.notify("Found "..#chestsFind.." near")
end

onEvent("RenderEvent", function()
	ImGui.SetNextWindowSize({350, 300}, 4)
	ImGui.SetNextWindowBgAlpha(0.6)
    ImGui.Begin("BuriedTreasureFinder")
    ImGui.Text("Chests found nearby:")

    if #chestsFind > 0 then
        for n, block in ipairs(chestsFind) do
            ImGui.BulletText(string.format("X: %d Y: %d Z: %d - %d blocks", block[1], block[2]+1, block[3], chestsDistances[n]))
        end
    else
        ImGui.Text("No chests found yet.")
    end
    
    ImGui.End()
end)

onEvent("TickEvent", function()
    if ScanButton.value and not LatestScanButtonKey then
        client.notify("Scaning...")
        ScanChunksPerBuriedTreasure()
    end

    LatestScanButtonKey = ScanButton.value
end)