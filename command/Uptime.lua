name = "uptime"
description = "Tells the time since Minecraft has started."
author = "Streoids"
aliases = {"uptm"}

local start=os.time()
function execute(args)
    if #args==0 then
        local elapsed=os.time()-start
        client.notify(string.format("%dh %dm %ds", elapsed//3600, (elapsed%3600)//60, elapsed%60))
    end
end
