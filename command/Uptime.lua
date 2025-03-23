name = "uptime"
description = "Tells the time since Minecraft has started."
author = "Streoids"
--@Streoids

local startTime=os.time()

function execute(args)
    local elapsed=os.time()-startTime
    client.notify(string.format("%dh %dm %ds", elapsed//3600,(elapsed%3600)//60,elapsed%60))
end