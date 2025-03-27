name = "CubeCraft Utils"
description = "Automatically invites online friends to a party, accepts incoming invites, and provides a rage quit feature."
author = "Zgoly"

-- SECTION: Auto Invite
-- TODO: Uncomment when available
--[[
settings.addHeader("Auto Invite")
settings.addElementText("Automatically invites all online friends to your party.")
]]
autoInviteToggle = settings.addToggle("Enable Auto Invite", "Turns the auto-invite feature on or off.", false)
autoInviteSlider = settings.addSlider("Invite Delay", "Delay between sending invites (in ticks).", 20, 1200, 1, false)
autoInviteKeybind = settings.addKeybind("Start Inviting", "Keybind to start inviting friends.")

-- SECTION: Auto Accept
-- TODO: Uncomment when available
--[[
settings.addHeader("Auto Accept")
settings.addElementText("Automatically accepts party invites from other players.")
]]
autoAcceptToggle = settings.addToggle("Enable Auto Accept", "Turns the auto-accept feature on or off.", false)
manualAcceptToggle = settings.addToggle("Manual Accept Mode", "Enables manual acceptance of party invites using a keybind.", false)
manualAcceptKeybind = settings.addKeybind("Accept Invite Key", "Keybind to manually accept a pending party invite.")

-- SECTION: Rage Quit
-- TODO: Uncomment when available
--[[
settings.addHeader("Rage Quit")
settings.addElementText("Quickly leaves the current party and game to return to the lobby.")
]]
rageQuitToggle = settings.addToggle("Enable Rage Quit", "Turns the rage quit feature on or off.", false)
rageQuitKeybind = settings.addKeybind("Rage Quit Key", "Keybind to activate rage quit.")
rageQuitSlider = settings.addSlider("Rage Quit Delay", "Delay between leaving the party and teleporting to the lobby (in ticks).", 10, 1200, 1, false)

-- Variables used in the script
local PREFIX = "§r§b[" .. name .. "] §r"

local isProcessingFriendsList = false
local isInviting = false
local friendsList = {}

local tick = 0
local savedTick = 0

local inviteTickCounter = 0
local rageQuitTickCounter = 0

local isRageQuitting = false

-- Variable to store the nickname of the player who sent the invite
local pendingInviteNickname = nil

-- Event: Key Press
onEvent("KeyEvent", function(key, action)
    -- Start inviting friends if the keybind is pressed and auto-invite is enabled
    if autoInviteToggle.value and autoInviteKeybind.value then
        isProcessingFriendsList = true
        friendsList = {}

        -- Fetch the friends list
        player.executeCommand("/friends list")
    end

    -- Manual accept keybind logic
    if autoAcceptToggle.value and manualAcceptToggle.value and manualAcceptKeybind.value and pendingInviteNickname ~= nil then
        player.executeCommand("/party accept " .. pendingInviteNickname)
        print(PREFIX .. "§aManually accepted invite from §b" .. pendingInviteNickname .. "§a!")

        -- Reset pendingInviteNickname after accepting the invite
        pendingInviteNickname = nil
    end

    -- Rage Quit Logic
    if rageQuitToggle.value and rageQuitKeybind.value then
        isRageQuitting = true
        rageQuitTickCounter = 0

        print(PREFIX .. "§cLeaving the party...")
        player.executeCommand("/party leave")
    end
end)

-- Event: Chat Message Received
onEvent("ChatReceiveEvent", function(message, name, type)
    -- Check if the Auto Party Invite toggle is enabled
    if not autoInviteToggle.value then return end

    -- Cancel the event if the message matches certain criteria (in our case it's command output header)
    if string.find(message, "§r§9-------§r§r §r§eFriends") and isProcessingFriendsList then
        savedTick = tick
        isProcessingFriendsList = false
        isInviting = true

        print(PREFIX .. "§eSearching for friends online...")
    end

    -- Process friend list entries
    if isInviting and savedTick == tick then
        -- General pattern to match player name
        local friendName = string.match(message, "§r§a(.-)§r§f %- §r")
    
        if friendName then
            table.insert(friendsList, friendName)
            print(PREFIX .. "§e" .. friendName .. " is currently online. Adding to invite queue...")
        end
    end

    -- Auto Accept Logic
    if autoAcceptToggle.value then
        -- Only update pendingInviteNickname if it is currently nil
        if pendingInviteNickname == nil then
            pendingInviteNickname = string.match(message, "§r§aYou have received a party invite from §r§b(.-)§r§a!")
            
            -- Print a message if a party invitation is found
            if pendingInviteNickname ~= nil then
                print(PREFIX .. "§bFound party invitation from §b" .. pendingInviteNickname .. "§a!")
            end
        end
    
        -- Check if pendingInviteNickname has a valid value and manual accept is disabled
        if pendingInviteNickname ~= nil and not manualAcceptToggle.value then
            player.executeCommand("/party accept " .. pendingInviteNickname)
            print(PREFIX .. "§aAutomatically accepted invite from §b" .. pendingInviteNickname .. "§a!")
            
            -- Reset pendingInviteNickname after accepting the invite
            pendingInviteNickname = nil
        end
    end
end)

-- Event: Game Tick
onEvent("TickEvent", function()
    tick = tick + 1

    inviteTickCounter = inviteTickCounter + 1

    -- Auto Invite Logic in TickEvent
    if #friendsList > 0 and inviteTickCounter >= math.floor(autoInviteSlider.value) then
        player.executeCommand("/party invite " .. friendsList[1])
        table.remove(friendsList, 1)
        inviteTickCounter = 0
    elseif #friendsList == 0 then
        isInviting = false
    end

    -- Rage Quit Logic in TickEvent
    if isRageQuitting then
        rageQuitTickCounter = rageQuitTickCounter + 1

        -- Check if the delay has passed
        if rageQuitTickCounter >= math.floor(rageQuitSlider.value) then
            print(PREFIX .. "§cTeleporting to the lobby...")
            player.executeCommand("/lobby")
            isRageQuitting = false -- Reset the flag after completing the sequence
        end
    end
end)
