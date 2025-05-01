name = "Chat Filter"
description = "Hides chat messages containing specified words."
author = "DxJar"

filteredWordsSetting = settings.addTextBox("Filtered Words", "Comma-separated words to filter from chat", "", 500)

local function splitString(inputstr, sep)
    if sep == nil then
        sep = "%s"
    end
    local t = {}
    for str in string.gmatch(inputstr, "([^"..sep.."]+)") do
        str = string.gsub(str, "^%s*", "")
        str = string.gsub(str, "%s*$", "")
        if #str > 0 then
            table.insert(t, str)
        end
    end
    return t
end

onEvent("ChatReceiveEvent", function(message, name, type)
    local filterListRaw = filteredWordsSetting.value
    
    if filterListRaw == "" then
        return false
    end
    
    local filterList = splitString(filterListRaw, ",")
    
    local lowerMessage = string.lower(message)
    
    for _, word in ipairs(filterList) do
        local lowerWord = string.lower(word)
        if string.find(lowerMessage, lowerWord, 1, true) then
            return true
        end
    end
    
    return false
end)
