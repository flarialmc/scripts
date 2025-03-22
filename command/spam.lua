name = "Spammer"
description = "use .helpspam for more info"
author = "Streoids"
local spamactive=false  
local spammessage="bombardiro-crocodilo"
local spamdelay=1  
local spamcount=nil  
local spamcounter=0
local tickcounter=0  
local function parsetime(timestr)
    local num=tonumber(timestr:sub(1,-2)) 
    local unit=timestr:sub(-1)  
    if not num then return nil
    end
    if unit=="s" then
        return num * 20  
    elseif unit=="m" then
        return num * 1200  
    elseif unit=="h" then
        return num*72000  
    else
        return nil
    end
end
function onLoad()
    registerCommand("spam", function(args)
        if #args==0 then print("§4Usage: .spam <time?> <count?> <message>") return
        end 
        local delay=1 
        local count=nil
        local possibledelay=parsetime(args[1])
        if possibledelay then
            delay=possibledelay
            table.remove(args, 1)
        end
        if #args>1 then
            local possiblecount=tonumber(args[1])
            if possiblecount then
                count=possiblecount
                table.remove(args, 1)
            end
        end
        local message=table.concat(args, " ")
        if message=="" then return
        end  
        spammessage=message
        spamdelay=delay
        spamcount=count
        spamcounter=0
        tickcounter=0
        spamactive=true
    end)
    registerCommand("stop", function()
        spamactive=false
    end)
    registerCommand("helpspam", function()
        print("§6To use spammer")
        print("§c.spam <msg>§r §ospams <msg> until you type .stop")
        print("§c.spam <time> <msg>§r §ospams msg with <time> delay, h for hours,m for minutes, s for seconds.( 1s,5s,5m,1h)")
        print("§c.spam <count> <msg>§r §ospams msg <count> times (1,2,3,4........n)")
        print("§c.spam <time> <count> <msg>§r §ospams a specific amount of messages with <time> delay")
        print("§eDecimal numbers counts")
        print("     ")
        print("§4!!! I made this for fun, I will not be responsible if you get banned/muted/kicked by using it on public servers.!!!")
    end)
end
onEvent("TickEvent", function()
    if spamactive then
        tickcounter=tickcounter+1
        if tickcounter>=spamdelay then  
            player.say(spammessage)
            spamcounter=spamcounter+1
            tickcounter=0  
            if spamcount and spamcounter>=spamcount then
                spamactive=false  
            end
        end
    end
end)
