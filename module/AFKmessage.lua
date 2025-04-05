name = "AFK message sender"
description = "Sends a message in Hive chat when you are afk kicked, useful for party chat"

customResponse = settings.addTextBox("Custom Response", "Message to send when AFK-kicked, default is 'AFK, will be back!'", "AFK, will be back!", 100)

onEvent("ChatReceiveEvent", function(message, name, type)
    if message:find("You were removed from the game due to inactivity!") then
        local response = customResponse.value ~= "" and customResponse.value or "AFK, will be back!"
        player.say(response)
    end
end)
