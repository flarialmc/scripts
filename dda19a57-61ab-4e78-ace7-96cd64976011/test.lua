function onEnable()
    
end
function onDisable()
    
end


-- a bunch of directions for rendering
local directions = {
    "N", "NNE", "NE", "ENE", "E",
    "ESE", "SE", "SSE", "S",
    "SSW", "SW", "WSW", "W",
    "WNW", "NW", "NNW"
}

-- function for geting direction
function getDirection(yaw)
    yaw = yaw % 360

    local index = math.floor((yaw + 11.25) / 22.5) % 16 + 1
    
    return directions[index]
end

-- on render event calles every frame and gets used for renderin stuff
onEvent(EventType.onRenderEvent, function()
    -- normalrender draws a ect that can be moved aroung in hud editor value 84 is id of it shoud be unique if not can bug out but not crash second value is text 
    GUI.NormalRender(84, getDirection(Player.getYaw()))
end)