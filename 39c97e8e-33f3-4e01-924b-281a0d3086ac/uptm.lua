local startTime=os.time()
function onEnable()
end
function onDisable()
end
onCommand("uptm","@Streoids",function()--made by Streoids
    local elapsed=os.time()-startTime
    --'h' is hours 'm' is minutes 's' is seconds in case you are a newborn
    Notify(string.format("%dh %dm %ds",elapsed//3600,(elapsed%3600)//60,elapsed%60))
end)