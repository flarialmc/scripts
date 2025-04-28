
name = "Better Coordinates"
description = "Displays player coordinates"
author = "prath"


showXYZ = settings.addToggle("Show XYZ", "show xyz", true)
showDecimalPlaces = settings.addToggle("Show decimal places", "show decimal places", false)
showNetherCoords = settings.addToggle("Show nether coords", "show nether coords", false)
xOffset = settings.addSlider("X offset", "x offset (10x multiplier)", 1, 150, 1, true)
yOffset = settings.addSlider("Y offset", "y offset (10x multiplier)", 1, 150, 1, true)


function getPlayerPos(showDecimals, nether)
    if (nether == false) then
        x, y, z = player.position()
    else
        x, y, z = player.position()
        x = x / 8
        z = z / 8
    end
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


onEvent("RenderEvent", function()
    local posOv = getPlayerPos(showDecimalPlaces.value, false)
    local posN = getPlayerPos(showDecimalPlaces.value, true)
    local textOv = ""
    local textN = ""
    if (showXYZ.value) then
        textOv = "X: " .. posOv.x .. ", Y: ".. posOv.y .. ", Z: ".. posOv.z
        textN = "X: " .. posN.x .. ", Y: ".. posN.y .. ", Z: ".. posN.z
    else
        textOv = posOv.x .. ", " .. posOv.y .. ", " .. posOv.z
        textN = posN.x .. ", " .. posN.y .. ", " .. posN.z
    end
    local text = ""
    if (showNetherCoords.value) then
        text = "Overworld: " .. textOv .. "\nNether: " .. textN
    else
        text = textOv
    end
    gui.text({10 * xOffset.value, 10 * yOffset.value}, text, 10, 10, 150)
end)
