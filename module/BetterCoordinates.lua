name = "Better Coordinates"
description = "Displays player coordinates"
author = "prath"


settings.addHeader("Main Coordinates Settings")

showXYZ = settings.addToggle("Show XYZ", "show xyz", true)
showDecimalPlaces = settings.addToggle("Show decimal places", "show decimal places", false)
showOtherDimCoords = settings.addToggle("Show other dimension's coords", "nether if you're in the overworld and vice versa", false)
xOffset = settings.addSlider("X offset", "x offset (10x multiplier)", 1, 150, 1, true)
yOffset = settings.addSlider("Y offset", "y offset (10x multiplier)", 1, 150, 1, true)

settings.extraPadding()

settings.addHeader("Death Coordinates Settings")

renderDeathCoords = settings.addToggle("Render death coords", "render death coords", true)
showDimension = settings.addToggle("Show dimension", "show dimension", true)
showTime = settings.addToggle("Show time", "time in dd/mm/yy H:m", false)
showIndex = settings.addToggle("Show index", "show index", true)
noOfDeaths = settings.addSlider("Number of deaths to render", "greatest integer less than or equal to selected value is taken", 1, 10, 1, true)
xOffsetD = settings.addSlider("X offset 2", "x offset 2 (10x multiplier)", 1, 150, 1, true)
yOffsetD = settings.addSlider("Y offset 2", "y offset 2 (10x multiplier)", 1, 150, 10, true)



local function getPlayerPos(showDecimals, mul)
    x, y, z = player.position()
    y = y - 1.6
    x = x * mul
    z = z * mul
    if (x == nil or y == nil or z == nil) then
        return "N/a", "N/a", "N/a"
    end
    if (showDecimals) then
        return {
            x = math.floor(x * 100) / 100,
            y = math.floor(y * 100) / 100,
            z = math.floor(z * 100) / 100
        }
    else
        return {
            x = math.floor(x),
            y = math.floor(y),
            z = math.floor(z)
        }
    end
end

local function split(input, sep)
    local t = {}
    for str in string.gmatch(input, "([^"..sep.."]+)") do
        str = string.gsub(str, "^%s*", "")
        str = string.gsub(str, "%s*$", "")
        if #str > 0 then
            table.insert(t, str)
        end
    end
    return t
end

local dir = "scripts/Data/Better Coordinates/"
local fp = dir .. "deathcoords.txt"

local function checkDir()
    if (not fs.exists(dir)) then
        fs.create(dir)
    end
end

local function writeDeathCoords(pos, dimension)
    checkDir()
    fs.writeFile(
        fp,
        os.date("%d/%m/%y %H:%M") .. "  ->  "
        .. "X: " .. pos.x .. ", Y: " .. pos.y .. ", Z: " .. pos.z .. "  ->  "
        .. dimension .. "\n"
    )
end

local function readDeathCoords()
    checkDir()

    local fileData = fs.readFile(fp)
    local deathObjs = split(fileData, "\n")

    local deaths ={}
    for i= 1, #deathObjs do
        deaths[i] = split(deathObjs[i], "->")
    end

    return deaths
end


local death = false
onEvent("TickEvent", function()
    local screen = client.getScreenName()
    local health = player.health()
    if (death and health > 0) then
        death = false
    end
    if (screen == "/hbui/gameplay.html" or health == 0) then
        if (not death) then
            death = true
            writeDeathCoords(getPlayerPos(showDecimalPlaces.value, 1), player.dimension())
        end
    end
end)


onEvent("RenderEvent", function()
    local screen = client.getScreenName()
    if (screen == "hud_screen" or screen == "chat_screen" or screen == "pause_screen") then

        local dimension = player.dimension()
        local text = ""

        if (dimension == "TheEnd") then
            local pos = getPlayerPos(showDecimalPlaces.value, 1)
            if (showXYZ.value) then
                text = "X: " .. pos.x .. ", Y: ".. pos.y .. ", Z: ".. pos.z
            else
                text = pos.x .. ", " .. pos.y .. ", " .. pos.z
            end
        else
            local OvMult = 0
            local NMult = 0

            if (dimension == "Overworld") then
                OvMult = 1
                NMult = 1/8
            elseif (dimension == "Nether") then
                OvMult = 8
                NMult = 1
            end

            local posOv = getPlayerPos(showDecimalPlaces.value, OvMult)
            local posN = getPlayerPos(showDecimalPlaces.value, NMult)
            local textOv = ""
            local textN = ""
            if (showXYZ.value) then
                textOv = "X: " .. posOv.x .. ", Y: ".. posOv.y .. ", Z: ".. posOv.z
                textN = "X: " .. posN.x .. ", Y: ".. posN.y .. ", Z: ".. posN.z
            else
                textOv = posOv.x .. ", " .. posOv.y .. ", " .. posOv.z
                textN = posN.x .. ", " .. posN.y .. ", " .. posN.z
            end
            if (showOtherDimCoords.value) then
                text = "Overworld: " .. textOv .. "\nNether: " .. textN
            else
                text = textOv
            end
        end

        gui.text({10 * xOffset.value, 10 * yOffset.value}, text, 10, 10, 150)

        if (renderDeathCoords.value) then

            local deaths = readDeathCoords()
            local maxDeathsRenderable = math.min(math.floor(noOfDeaths.value), #deaths)

            local text = "Deaths: (" .. #deaths .. ")\n"

            for i = 0, maxDeathsRenderable - 1 do
                local death = deaths[#deaths - i]
                if (showIndex.value) then
                    text = text .. i + 1 .. ".  "
                end
                text = text .. death[2]
                if (showDimension.value) then
                    text = text .. "  (" .. death[3] .. ")"
                end
                if (showTime.value) then
                    text = text .. "  (" .. death[1] .. ")"
                end
                text = text .. "\n"
            end

            gui.text({10 * xOffsetD.value, 10 * yOffsetD.value + 15 * maxDeathsRenderable}, text, 10, 10, 150)

        end

    end
end)
