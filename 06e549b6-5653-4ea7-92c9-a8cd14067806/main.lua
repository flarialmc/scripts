
function onEnable()
    Notify("TPS enabled!")
end

function onDisable()
    Notify("TPS disabled!")
end

Ticks = {}

onEvent(EventType.onTickEvent, function()
    if (Ticks and type(Ticks) == "table") then
        local currentTime = os.clock()
        table.insert(Ticks, currentTime)
        while (Ticks[1] and Ticks[1] <= currentTime - 1) do
            table.remove(Ticks, 1)
        end
    end
end)

onEvent(EventType.onRenderEvent, function()
    if (Ticks and type(Ticks) == "table") then
        GUI.NormalRender(32, "TPS: " .. #Ticks)
    end
end)
