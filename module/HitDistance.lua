name = "Hit Distance"
description = "Shows the distance you were last hit from."
author = "ZayTheGamer1000"
debug = false

--[[ DEFAULT VALUES
As of Flarial 3.0.3.6, the default values for settings do not seem to work.
If you are here to change the default values, they are provided below.
]]

-- These are the default X & Y values for the GUI's text.
guiX = 0
guiY = 30

-- This is the default font size
fontSize = 200

-- This is the default duration in seconds
duration = 3

-- This is the default search range in blocks
searchRange = 10


lastHealth = player.health()
lastHitDistance = 0.0

showDistance = false
ticks = 0
showDistSecs = 0

guiXSlider = settings.addSlider("GUI X", "The X value that the distance GUI will appear at.", 0,
 100, -- Maximum value
 0, -- Minimum value
 false) -- Allow 0 inclusive (for some reason false means true)

guiYSlider = settings.addSlider("GUI Y", "The Y value that the distance GUI will appear at.", 30,
 100,
 0,
 false)

--Initial constraints (static unless the location of GUIX/GUIY is changed in settings.)
guiXConstraint = Constraints.PercentageConstraint(guiX / 100, "left", true)
guiXAdjusted = false
guiYConstraint = Constraints.PercentageConstraint(guiY / 100, "top", true)
guiYAdjusted = false

fontSizeSlider = settings.addTextBox("Font Size", "The size of the gui's text. (Default 200)", "200", 5)
fontSizeAdjusted = false

showDuration = settings.addTextBox("Duration", "The duration in seconds that the distance will be shown for. (default 3)", "3", 12)
durationAdjusted = false

searchRangeInput = settings.addTextBox("Search range", "The range in which the attacker is searched for. (default 10)", "10", 5)
searchRangeAdjusted = false

includeEntities = settings.addToggle("Include entities", "Whether to include all player entities in detection, rather than just players.", false)
--No need for a default boolean, as the (real) default and what we want are the same: false.

function onEnable()
	client.notify("Hit Distance Enabled")
end

function onDisable()
	client.notify("Hit Distance Disabled")
end


onEvent("TickEvent", function()
	local health = player.health()
	
	if health < lastHealth then
		lastHealth = health
		playerHit()
	else
		lastHealth = health
	end
	
	if showDistance then
		if ticks == 20 then
			showDistSecs = showDistSecs + 1
		end
		
		
		if showDistSecs == duration then
			showDistance = false
			showDistSecs = 0
			ticks = 0
		end

		if ticks == 20 then -- 20 ticks = 1 second (Handles ticks)
			ticks = 0
		end
		ticks = ticks + 1
	end
	
	if guiXAdjusted or guiXSlider.value ~= 0.0 then -- X slider has been adjusted for the first time
		guiXAdjusted = true
		guiX = guiXSlider.value
		guiXConstraint = Constraints.PercentageConstraint(guiX / 100, "left", true)
	end
	if guiYAdjusted or guiYSlider.value ~= 0.0 then -- Y slider has been adjusted for the first time
		guiYAdjusted = true
		guiY = guiYSlider.value
		guiYConstraint = Constraints.PercentageConstraint(guiY / 100, "top", true)
	end
	
	if durationAdjusted or showDuration.value ~= "" then
		durationAdjusted = true
		
		if tonumber(showDuration.value) == nil then
			duration = 0
		else
			duration = math.floor(tonumber(showDuration.value))
		end
	end
	
	if fontSizeAdjusted or fontSizeSlider.value ~= "" then 
		fontSizeAdjusted = true
		
		if tonumber(fontSizeSlider.value) == nil then
			fontSize = 0
		else
			fontSize = math.floor(tonumber(fontSizeSlider.value))
		end
	end
	
	if searchRangeAdjusted or searchRangeInput.value ~= "" then 
		searchRangeAdjusted = true
		
		if tonumber(searchRangeInput.value) == nil then
			searchRange = 0
		else
			searchRange = math.floor(tonumber(searchRangeInput.value))
		end
	end

end)


function playerHit()
	local entities = world.getEntities(searchRange)
	local entity = nil
	local closestDistance = nil
	
	for index, value in ipairs(entities) do
		
		if includeEntities.value then -- If all entities included in search
			if value:isValid() then
				if closestDistance == nil or value:distanceToPlayer() < closestDistance then -- If first or closest entity iterated
					closestDistance = value:distanceToPlayer()
					entity = value
				end
			end
		else
			if value:isValid() and value:getTypeId() == "minecraft:player" then
				if closestDistance == nil or value:distanceToPlayer() < closestDistance then -- If first or closest player iterated
					closestDistance = value:distanceToPlayer()
					entity = value
				end
			end
		end		
	end
	
	if entity == nil then -- Failed to find a valid player or entity
		return
	end
	
	
	lastHitDistance = entity:distanceToPlayer()
	showDistance = true
	ticks = 0
	showDistSecs = 0
	
end

onEvent("RenderEvent", function()
	
	if showDistance then
		gui.text({guiXConstraint, guiYConstraint}, -- X and Y slider / 100 (gets decimal location value
		string.format("%.2f", lastHitDistance),
		100,
		60,
		fontSize)
	end
end)