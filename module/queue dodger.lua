name = "Queue Dodger"
description = "Automatically queues a specified gamemode in The Hive when a specified player joins the game"
author = "s6iy"

targetPlayer = settings.addTextBox("Target Player", "Case Sensitive, No Underscores Ex: Flarial User", "", 16)
customCommand = settings.addTextBox("Custom Command", "Command to execute (with '/') Ex: /q bed-duos", "", 100)

onEvent("ChatReceiveEvent", function(message, name, type)
    local name = targetPlayer.value
    local command = customCommand.value
    if name ~= "" and command ~= "" then
      
        if message:find(name) and message:find("joined") then
            player.executeCommand(command)
        end

        if message:find("You are already connected to this server!") or
           message:find("You're issuing commands too quickly, try again later") then
            player.executeCommand(command)
        end
    end
end)