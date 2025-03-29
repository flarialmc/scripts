name = "CubeCraft Utils"
description = "Automatically invites online friends, accepts party invites, rage quits to the lobby and tracks player kills with a UI."
author = "Zgoly"
version = "1.0.1"

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

-- SECTION: Kills UI
-- TODO: Uncomment when available
--[[
settings.addHeader("Kills UI")
settings.addElementText("Displays a UI showing player kills during the game.")
]]
killsUIToggle = settings.addToggle("Enable Kills UI", "Enables the kills tracking and display.", false)
killsUITextBox = settings.addTextBox("Kills Format", "Format for displaying kills (use {name} for player name and {value} for kill count).", "{name}: {value}", 128)
onlyMineToggle = settings.addToggle("Only Mine", "Only track kills made by you.", false)
clearAfterEndToggle = settings.addToggle("Clear After End", "Resets the kills counter after the game ends.", true)

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

-- Variable to store kills for Kills UI
local kills = {}

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
    -- Auto Invite logic
    if autoInviteToggle.value then
        -- Check for the command output header
        if string.find(message, "§r§9-------§r§r §r§eFriends") and isProcessingFriendsList then
            savedTick = tick
            isProcessingFriendsList = false
            isInviting = true

            print(PREFIX .. "§eSearching for friends online...")
        end

        -- Process friend list entries
        if isInviting and savedTick == tick then
            -- General pattern to match online player name
            local friendName = string.match(message, "§r§a(.-)§r§f %- §r")
        
            if friendName then
                table.insert(friendsList, friendName)
                print(PREFIX .. "§e" .. friendName .. " is currently online. Adding to invite queue...")
            end
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

    -- Kills UI logic
    if killsUIToggle.value then
        -- Define default death message patterns and their killer numbers

        -- Took from the https://github.com/Fesaa/Cubepanion/blob/main/core/src/main/java/art/ameliah/laby/addons/cubepanion/core/listener/internal/Stats.java
        -- Can be replaced later by kill event or something like that
        local patterns = {
            {pattern = "§r§6(.-)§r§e died in the void while escaping §r§6(.-)§r§e%.", killerNumber = 2},
            {pattern = "§r§6(.-)§r§e was slain by §r§6(.-)§r§e%.", killerNumber = 2},
            {pattern = "§r§6(.-)§r§e was blown up by §r§6(.-)§r§e%.", killerNumber = 2},
            {pattern = "§r§6(.-)§r§e thought they could survive in the void while escaping §r§6(.-)§r§e%.", killerNumber = 2},
            {pattern = "§r§6(.-)§r§e kicked §r§6(.-)§r§e into the void%.", killerNumber = 1},
            {pattern = "§r§6(.-)§r§e couldn't fly while escaping §r§6(.-)§r§e%.", killerNumber = 2},
            {pattern = "§r§6(.-)§r§e tried to escape §r§6(.-)§r§e by jumping into the void%.", killerNumber = 2},
            {pattern = "§r§6(.-)§r§e was turned into a snowman by §r§6(.-)§r§e%.", killerNumber = 2}
        }

        -- Try each pattern until a match is found
        local victim, killer
        for _, entry in ipairs(patterns) do
            victim, killer = string.match(message, entry.pattern)
            if victim and killer then
                -- Adjust killer based on the killerNumber
                if entry.killerNumber == 1 then
                    victim, killer = killer, victim -- Swap if killer is the first group
                end
                break
            end
        end

        -- If a valid killer and victim are found, update the kills counter
        if victim and killer then
            if not onlyMineToggle.value or (onlyMineToggle.value and killer == player.name()) then
                kills[killer] = (kills[killer] or 0) + 1
            end
        end

        -- Check for game length message (appears when player wins or dies) and clear kills if enabled
        if clearAfterEndToggle.value and string.find(message, "§r§8%-§r §r§7Game length:") then
            kills = {} -- Reset kills counter
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

-- Event: Render
onEvent("RenderEvent", function()
    if killsUIToggle.value then
        -- Check if the kills table is empty using next
        local uiText = next(kills) and "" or "Nothing to show"

        -- Build the kills UI text if the table is not empty
        if next(kills) then
            for name, value in pairs(kills) do
                local formattedLine = killsUITextBox.value:gsub("{name}", name):gsub("{value}", value)
                uiText = uiText .. formattedLine .. "\n"
            end
        end

        -- Render the kills UI
        gui.render(uiText, 69)
    end
end)
