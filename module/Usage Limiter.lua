name = "Usage Limiter"
description = "Limit your Minecraft usage time. to use this type .limit <time> (s for seconds, m for minutes, h for hours) "
author = "Streoids"
function onLoad()
    registerCommand("limit", function(args)
        local tval, unit=args[1]:match("(%d+)([smh])")
        if not tval or not unit then
            print("to use this type .limit <time> (s for seconds, m for minutes, h for hours)")
            return
        end
        local multiplier=(unit=="s" and 1 or (unit=="m" and 60 or 3600))
        crash=os.time()+tonumber(tval) * multiplier
        msg={false, false, false}
        print("§cMinecraft will close in " .. args[1])
    end)
end
onEvent("TickEvent", function()
    if crash then
        local tmleft=crash-os.time()
        if tmleft==3 and not msg[1] then
            print("§cUsage Limiter§r : Times up!! closing in 3")
            msg[1]=true
        elseif tmleft==2 and not msg[2] then
            print("§cUsage Limiter§r : 2")
            msg[2]=true
        elseif tmleft==1 and not msg[3] then
            print("§cUsage Limiter§r : 1")
            msg[3]=true
        end
        if tmleft<=0 then
            client.crash()
            crash=nil
        end
    end
end)

