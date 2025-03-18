name="Uptime"
description="Tells the time since Minecraft has started use '.uptm' to see."
author="Streoids"
--@Streoids
local startTime=os.time()
function onEnable()
end
function onDisable()
end
function onLoad()
    registerCommand("uptm", function(args)
        local elapsed=os.time()-startTime
        client.notify(string.format("%dh %dm %ds", elapsed//3600,(elapsed%3600)//60,elapsed%60))
    end)
end
