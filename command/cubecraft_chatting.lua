name = "c"
description = "Sends the message with !! prefix using /c command, useful in cubecraft"
author = "DxJar"

function execute(args)
    if #args == 0 then
        print("Please enter your message.")
    else
        local message = table.concat(args, " ")
        player.say("!!" .. message)
    end
end