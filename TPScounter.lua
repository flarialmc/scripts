
name = "TPS Counter"
description = "Displays the servers ticks per second"
author = "prath"


function onEnable()
    print("TPS enabled!")
end

function onDisable()
    print("TPS disabled!")
end

Ticks = {}

onEvent("TickEvent", function()
    if (Ticks and type(Ticks) == "table") then
        table.insert(Ticks, os.clock())
        while (Ticks[1] and Ticks[1] < os.clock() - 0.99) do
            table.remove(Ticks, 1)
        end
    end
end)

onEvent("RenderEvent", function()
    if (Ticks and type(Ticks) == "table") then
        FlarialGUI.NormalRender(32, "TPS: " .. #Ticks)
    end
end)
