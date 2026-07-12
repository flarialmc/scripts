name = "Notification when called"
description = "Shows a notification when you are mentioned in chat"
author = "zebedelu"

local function levenshtein(str1, str2)
    local len1 = #str1
    local len2 = #str2

    local matrix = {}

    for i = 0, len1 do
        matrix[i] = {}
        matrix[i][0] = i
    end

    for j = 0, len2 do
        matrix[0][j] = j
    end

    for i = 1, len1 do
        for j = 1, len2 do
            local cost = (str1:sub(i, i) == str2:sub(j, j)) and 0 or 1

            matrix[i][j] = math.min(
                matrix[i - 1][j] + 1,
                matrix[i][j - 1] + 1,
                matrix[i - 1][j - 1] + cost
            )
        end
    end

    return matrix[len1][len2]
end

local function similarity(str1, str2)
    local maxLen = math.max(#str1, #str2)

    if maxLen == 0 then
        return 100
    end

    local distance = levenshtein(str1, str2)
    return (1 - distance / maxLen) * 100
end

local function findBestMatch(word, text)
    word = word:lower()

    local bestScore = 0

    for textWord in text:lower():gmatch("%S+") do
        local score = similarity(word, textWord)

        if score > bestScore then
            bestScore = score
        end
    end

    return bestScore
end

local PlayerName

settings.addHeader("Configure Mention Sound")
local Tolerance = settings.addSlider("Tolerance", "How accurate must the name be? (default: 90%)", 90, 100, 20, false)
local FilePath = settings.addTextBox("File path", "default: 'Scripts/Data/MentionedSound.mp3'", "Scripts\\Data\\MentionedSound.mp3", 150)

function onEnable()
    PlayerName = player.name()
    client.notify("Mention Sound enabled!")
end

onEvent("ChatReceiveEvent", function(message, AuthorName, type)
    local percentageScore = findBestMatch(PlayerName, message)

    if ((Tolerance.value == 0 and percentageScore >= 90) or
        (Tolerance.value ~= 0) and percentageScore >= tonumber(Tolerance.value))
        and AuthorName ~= PlayerName then
        
        if FilePath.value ~= "" then
            audio.play(FilePath.value)
        else
            audio.play("Scripts\\Data\\MentionedSound.mp3")
        end

        client.notify(AuthorName.." has mentioned you!")
    end
end)