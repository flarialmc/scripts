name = "Armor blocker"
description = "Blocks weaker armor if you're wearing a stronger one."
author = "Streoids"
local power = 
{
    leather_helmet = 1, leather_chestplate = 1, leather_leggings = 1, leather_boots = 1,
    golden_helmet = 2, golden_chestplate = 2, golden_leggings = 2, golden_boots = 2,
    chainmail_helmet = 3, chainmail_chestplate = 3, chainmail_leggings = 3, chainmail_boots = 3,
    iron_helmet = 4, iron_chestplate = 4, iron_leggings = 4, iron_boots = 4,
    diamond_helmet = 5, diamond_chestplate = 5, diamond_leggings = 5, diamond_boots = 5,
    netherite_helmet = 6, netherite_chestplate = 6, netherite_leggings = 6, netherite_boots = 6
}
local function prefix(name)
    if not name then return name 
    end
    local s = tostring(name)
    local i = s:find(":")
    if i then return s:sub(i+1) 
    end
    return s
end
local function getPower(name)
    if not name then return 0 
    end
    return power[ prefix(name) ] or 0
end
local function realarmor(piece)
    if not piece then return false 
    end
    local n = piece.name
    if not n or n == "" or n == "empty" then return false 
    end
    if piece.maxDurability == -1 then return false 
    end
    return true
end
local function slotname(name)
    if not name then return nil 
    end
    local s = prefix(name)
    if s:find("helmet") then return "helmet"
    end
    if s:find("chestplate") then return "chestplate"
    end
    if s:find("leggings") then return "leggings"
    end
    if s:find("boots") then return "boots" 
    end
    return nil
end
function onLoad()
    print("§aLoaded Armor blocker by Streoids.")
end
onEvent("MouseEvent", function(button, action)
    if button ~= 2 or action ~= 1 then return 
    end
    local hand = player.mainhand()
    if not hand or not hand.name or hand.name == "" or hand.name == "empty" then 
        return 
    end
    local slot = slotname(hand.name)
    if not slot then 
        return 
    end
    local armor = player.armor()
    if not armor then 
        return 
    end
    local current = armor[slot]
    if not realarmor(current) then 
        return 
    end
    local currentPower = getPower(current.name)
    local heldPower = getPower(hand.name)
    if heldPower > 0 and heldPower < currentPower then
        print("§7§oArmor is weaker than what you're wearing now.")
        return true
    end
end) -- john pork cool.
