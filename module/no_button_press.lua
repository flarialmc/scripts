--[[
    (Yes, this was vibe coded)
  Anti Button Press - Flarial Client Lua Module
  ------------------------------------------------------------------------
  Prevents every vanilla button variant (all wood types, stone button,
  polished blackstone button, etc.) from activating on interact: no
  pressed state, no redstone pulse.
--]]

name = "No Button Press"
description = "Prevents all vanilla buttons from being activated on interact."
author = "Jonfi"
debug = false

-- ClickGUI settings ---------------------------------------------------
-- The module's own ClickGUI toggle already controls onEnable/onDisable.
-- This extra setting only controls whether a small notification is
-- shown each time a press is blocked.
local notifySetting = settings.addToggle(
    "Notify On Block",
    "Show a notification when a button press is prevented.",
    false
)

-- Internal state --------------------------------------------------------
-- No documented "unregister event" call exists (see limitation #4), so
-- this flag is the supported way to make the always-registered
-- MouseEvent handler act as a no-op while the module is disabled.
local moduleEnabled = false

-- Maximum raycast distance, in blocks. 6 comfortably covers vanilla
-- interaction range with a small margin.
local RAYCAST_DISTANCE = 6

-- MouseEvent constants, per api/game/events documentation.
local BUTTON_RIGHT_CLICK = 2
local ACTION_DOWN = 1

-- Returns true if blockName refers to any vanilla button variant.
-- Matching on the "button" substring (rather than an exact id list)
-- keeps this correct across every wood type, stone, and polished
-- blackstone without hardcoding every namespaced identifier, and
-- degrades safely if future button variants are added to the game.
local function isButtonBlock(blockName)
    if type(blockName) ~= "string" then
        return false
    end
    return blockName:find("button", 1, true) ~= nil
end

-- Module lifecycle --------------------------------------------------------

function onLoad()
    moduleEnabled = false
end

function onEnable()
    moduleEnabled = true
end

function onDisable()
    moduleEnabled = false
end

-- Core interaction blocker -------------------------------------------------
-- MouseEvent is the only documented, cancellable hook that fires for a
-- right-click/interact press (see limitation #2). Cheap checks run
-- first, so idle/other-input cost is effectively zero; the raycast and
-- block lookup only run on an actual right-click-down.
onEvent("MouseEvent", function(button, action)
    if not moduleEnabled then
        return
    end

    if button ~= BUTTON_RIGHT_CLICK or action ~= ACTION_DOWN then
        return
    end

    local hit = world.raycast(RAYCAST_DISTANCE)
    if hit == nil then
        return -- Nothing in range (e.g. no level/player) - let click through.
    end

    local ok, blockName = pcall(world.getBlock, hit.blockX, hit.blockY, hit.blockZ)
    if not ok or blockName == nil then
        return -- Block source unavailable - fail open, don't error, let click through.
    end

    if isButtonBlock(blockName) then
        if notifySetting ~= nil and notifySetting.value then
            client.notify("Button press blocked")
        end
        -- Cancelling the event stops Minecraft from ever receiving the
        -- interact action, so the button never depresses and never
        -- produces a redstone pulse.
        return true
    end
    -- Any other block: do nothing, allow normal interaction.
end)
