name = "TPS Counter"
description = "Displays the servers ticks per second"
author = "prath"
version = "1.0.0"

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
        gui.render("TPS: " .. #Ticks, 32)
    end
end)
