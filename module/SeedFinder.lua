-- ============================================================================
-- SeedFinder — Minecraft Bedrock Structure Finder (HTTP Bridge Edition)
-- Uses network.get() to call the local SeedFinder Flask API
-- ============================================================================

name = "SeedFinder"
description = "See structure of the map with the seed, without chunkbase"
author = "zebedelu"

-- ============================================================================
-- Section 1: HTTP Bridge Integration
-- ============================================================================

local SERVER_URL = "http://127.0.0.1:7890"
local serverOnline = false
local serverWarned = false
local lastServerCheck = 0

local function checkServer()
	local now = os.clock()
	if now - lastServerCheck < 5 then return serverOnline end
	lastServerCheck = now

	local ok, response = pcall(network.get, SERVER_URL .. "/status")
	if ok and response and type(response) == "string" and response ~= "" and response ~= "null" then
		if response:find('"ok"') or response:find('"status"') then
			serverOnline = true
			serverWarned = false
		else
			serverOnline = false
		end
	else
		serverOnline = false
	end
	return serverOnline
end

-- ============================================================================
-- Section 2: Utility Functions
-- ============================================================================

local STRUCTURE_TYPES = {
	Desert_Pyramid = 1,
	Jungle_Temple = 2,
	Swamp_Hut = 3,
	Igloo = 4,
	Village = 5,
	Ocean_Ruin = 6,
	Shipwreck = 7,
	Monument = 8,
	Mansion = 9,
	Outpost = 10,
	Ruined_Portal = 11,
	Ruined_Portal_N = 12,
	Ancient_City = 13,
	Treasure = 14,
	Mineshaft = 15,
	Desert_Well = 16,
	Geode = 17,
	Trail_Ruins = 23,
	Trial_Chambers = 24,
}

local STRUCTURE_ICONS = {
	desert_pyramid = "[D]",
	jungle_pyramid = "[J]",
	swamp_hut = "[S]",
	igloo = "[I]",
	village = "[V]",
	ocean_ruin = "[R]",
	shipwreck = "[W]",
	monument = "[O]",
	mansion = "[M]",
	pillager_outpost = "[P]",
	ruinedportal = "[RP]",
	ruined_portal_nether = "[NRP]",
	ancient_city = "[A]",
	buried_treasure = "[B]",
	mineshaft = "[MS]",
	desert_well = "[DW]",
	amethyst_geode = "[G]",
	trail_ruins = "[T]",
	trial_chambers = "[TC]",
	unknown = "[?]",
}

local STRUCTURE_DISPLAY_NAMES = {
	desert_pyramid = "Desert Pyramid",
	jungle_pyramid = "Jungle Temple",
	swamp_hut = "Swamp Hut",
	igloo = "Igloo",
	village = "Village",
	ocean_ruin = "Ocean Ruin",
	shipwreck = "Shipwreck",
	monument = "Ocean Monument",
	mansion = "Woodland Mansion",
	pillager_outpost = "Pillager Outpost",
	ruinedportal = "Ruined Portal",
	ruined_portal_nether = "Ruined Portal (Nether)",
	ancient_city = "Ancient City",
	buried_treasure = "Buried Treasure",
	mineshaft = "Mineshaft",
	desert_well = "Desert Well",
	amethyst_geode = "Amethyst Geode",
	trail_ruins = "Trail Ruins",
	trial_chambers = "Trial Chambers",
	unknown = "Unknown Structure",
}

local function getStructureIcon(name)
	return STRUCTURE_ICONS[name] or STRUCTURE_ICONS.unknown
end

local function getStructureDisplayName(name)
	return STRUCTURE_DISPLAY_NAMES[name] or name
end

local function parseSeed(input)
	if not input or input == "" then return nil end
	local seed = tonumber(input)
	if seed then return seed end
	-- Hash string to seed (Java's String.hashCode equivalent)
	local hash = 0
	for i = 1, #input do
		hash = (hash * 31 + string.byte(input, i)) % 2 ^ 32
	end
	if hash >= 2 ^ 31 then hash = hash - 2 ^ 32 end
	return hash
end

-- Safe setting value readers (Flarial may return unexpected types after persistence)
local function getNum(setting, default)
	local v = setting and setting.value
	if type(v) == "number" then return v end
	if type(v) == "string" then return tonumber(v) or default end
	return default
end

local function getStr(setting, default)
	local v = setting and setting.value
	if type(v) == "string" then return v end
	if type(v) == "number" then return tostring(v) end
	return default
end

local function getBool(setting, default)
	local v = setting and setting.value
	if type(v) == "boolean" then return v end
	if type(v) == "number" then return v ~= 0 end
	if type(v) == "string" then return v == "true" end
	return default
end

local function formatDistance(dist)
	if dist < 1 then return "<1" end
	return string.format("%.0f", dist)
end

-- Parse JSON response from the server (no json.decode in sandbox)
-- Flask returns fields in order: distance, name, x, z
-- But we match both orderings to be safe
local function parseScanResponse(jsonStr)
	local results = {}

	if not jsonStr or jsonStr == "" then return results end

	local seen = {}

	-- Pattern A: "distance", "name", "x", "z" (Flask actual order)
	for dist, name, x, z in jsonStr:gmatch(
		'"distance"%s*:%s*([%d%.]+)%s*,%s*"name"%s*:%s*"([^"]+)"%s*,%s*"x"%s*:%s*(-?%d+)%s*,%s*"z"%s*:%s*(-?%d+)'
	) do
		local key = name .. "_" .. x .. "_" .. z
		if not seen[key] then
			seen[key] = true
			table.insert(results, {
				name = name,
				x = tonumber(x),
				z = tonumber(z),
				distance = tonumber(dist),
				displayName = getStructureDisplayName(name),
				icon = getStructureIcon(name),
			})
		end
	end

	-- Pattern B: "name", "x", "z", "distance" (alternative order)
	for name, x, z, dist in jsonStr:gmatch(
		'"name"%s*:%s*"([^"]+)"%s*,%s*"x"%s*:%s*(-?%d+)%s*,%s*"z"%s*:%s*(-?%d+)%s*,%s*"distance"%s*:%s*([%d%.]+)'
	) do
		local key = name .. "_" .. x .. "_" .. z
		if not seen[key] then
			seen[key] = true
			table.insert(results, {
				name = name,
				x = tonumber(x),
				z = tonumber(z),
				distance = tonumber(dist),
				displayName = getStructureDisplayName(name),
				icon = getStructureIcon(name),
			})
		end
	end

	return results
end

-- ============================================================================
-- Section 3: Settings
-- ============================================================================

local seedTextBox = settings.addTextBox("Seed", "Enter your world seed (numbers only)", "1", 30)
local radiusSlider = settings.addSlider("Radius", "How far to search (chunks)", 10, 200, 1)
local maxResultsSlider = settings.addSlider("Max Results", "Maximum structures to display", 15, 50, 1)
local serverUrlTextBox = settings.addTextBox("Server URL", "SeedFinder API server", "http://127.0.0.1:7890", 40)
local rescanKey = settings.addKeybind("Rescan", "Press to clear and rescan structures")
local notifyToggle = settings.addToggle("Scan Notification", "Show a notification when scan completes", true)

local toggleVillage = settings.addToggle("Village", "Search for villages", true)
local toggleDesertPyramid = settings.addToggle("Desert Pyramid", "Search for desert pyramids", true)
local toggleJungleTemple = settings.addToggle("Jungle Temple", "Search for jungle temples", true)
local toggleSwampHut = settings.addToggle("Swamp Hut", "Search for swamp huts", true)
local toggleOutpost = settings.addToggle("Pillager Outpost", "Search for pillager outposts", true)
local toggleIgloo = settings.addToggle("Igloo", "Search for igloos", true)
local toggleOceanMonument = settings.addToggle("Ocean Monument", "Search for ocean monuments", true)
local toggleOceanRuin = settings.addToggle("Ocean Ruin", "Search for ocean ruins", true)
local toggleMansion = settings.addToggle("Woodland Mansion", "Search for woodland mansions", true)
local toggleAncientCity = settings.addToggle("Ancient City", "Search for ancient cities", true)
local toggleTrailRuins = settings.addToggle("Trail Ruins", "Search for trail ruins", true)
local toggleRuinedPortal = settings.addToggle("Ruined Portal", "Search for ruined portals", true)
local toggleBuriedTreasure = settings.addToggle("Buried Treasure", "Search for buried treasure", true)
local toggleGeode = settings.addToggle("Amethyst Geode", "Search for amethyst geodes", true)

-- Toggle -> structure type ID mapping
local TOGGLE_TYPE_MAP = {
	{toggle = toggleVillage, id = STRUCTURE_TYPES.Village},
	{toggle = toggleDesertPyramid, id = STRUCTURE_TYPES.Desert_Pyramid},
	{toggle = toggleJungleTemple, id = STRUCTURE_TYPES.Jungle_Temple},
	{toggle = toggleSwampHut, id = STRUCTURE_TYPES.Swamp_Hut},
	{toggle = toggleOutpost, id = STRUCTURE_TYPES.Outpost},
	{toggle = toggleIgloo, id = STRUCTURE_TYPES.Igloo},
	{toggle = toggleOceanMonument, id = STRUCTURE_TYPES.Monument},
	{toggle = toggleOceanRuin, id = STRUCTURE_TYPES.Ocean_Ruin},
	{toggle = toggleMansion, id = STRUCTURE_TYPES.Mansion},
	{toggle = toggleAncientCity, id = STRUCTURE_TYPES.Ancient_City},
	{toggle = toggleTrailRuins, id = STRUCTURE_TYPES.Trail_Ruins},
	{toggle = toggleRuinedPortal, id = STRUCTURE_TYPES.Ruined_Portal},
	{toggle = toggleBuriedTreasure, id = STRUCTURE_TYPES.Treasure},
	{toggle = toggleGeode, id = STRUCTURE_TYPES.Geode},
}

-- ============================================================================
-- Section 4: Manual Settings Persistence (fs-based)
-- Flarial's settings API for Lua scripts does NOT persist custom setting values
-- (sliders, textboxes, toggles, keybinds). Only visual properties are saved.
-- We use fs.writeFile/readFile to persist our settings manually.
-- ============================================================================

local SAVE_PATH = "Scripts/Configs/SeedFinder_settings.txt"
local lastSaveTime = 0
local saveThrottle = 3 -- seconds between saves

local function saveSettings()
	local lines = {
		"seed=" .. tostring(getStr(seedTextBox, "1")),
		"radius=" .. tostring(math.floor(getNum(radiusSlider, 10))),
		"maxResults=" .. tostring(math.floor(getNum(maxResultsSlider, 15))),
		"serverUrl=" .. tostring(getStr(serverUrlTextBox, "http://127.0.0.1:7890")),
		"notify=" .. tostring(getBool(notifyToggle, true)),
		"village=" .. tostring(getBool(toggleVillage, true)),
		"desertPyramid=" .. tostring(getBool(toggleDesertPyramid, true)),
		"jungleTemple=" .. tostring(getBool(toggleJungleTemple, true)),
		"swampHut=" .. tostring(getBool(toggleSwampHut, true)),
		"outpost=" .. tostring(getBool(toggleOutpost, true)),
		"igloo=" .. tostring(getBool(toggleIgloo, true)),
		"oceanMonument=" .. tostring(getBool(toggleOceanMonument, true)),
		"oceanRuin=" .. tostring(getBool(toggleOceanRuin, true)),
		"mansion=" .. tostring(getBool(toggleMansion, true)),
		"ancientCity=" .. tostring(getBool(toggleAncientCity, true)),
		"trailRuins=" .. tostring(getBool(toggleTrailRuins, true)),
		"ruinedPortal=" .. tostring(getBool(toggleRuinedPortal, true)),
		"buriedTreasure=" .. tostring(getBool(toggleBuriedTreasure, true)),
		"geode=" .. tostring(getBool(toggleGeode, true)),
	}
	pcall(fs.writeFile, SAVE_PATH, table.concat(lines, "\n"))
end

local function throttledSave()
	local now = os.clock()
	if now - lastSaveTime >= saveThrottle then
		lastSaveTime = now
		pcall(saveSettings)
	end
end

local function loadSettings()
	local ok, data = pcall(fs.readFile, SAVE_PATH)
	if not ok or not data or type(data) ~= "string" then return end

	local saved = {}
	for line in data:gmatch("[^\n]+") do
		local key, val = line:match("^([^=]+)=(.+)$")
		if key and val then
			saved[key] = val
		end
	end

	-- Apply saved values to settings objects
	if saved.seed then seedTextBox.value = saved.seed end
	if saved.radius then radiusSlider.value = tonumber(saved.radius) or 10 end
	if saved.maxResults then maxResultsSlider.value = tonumber(saved.maxResults) or 15 end
	if saved.serverUrl then serverUrlTextBox.value = saved.serverUrl end
	if saved.notify then notifyToggle.value = saved.notify == "true" end
	if saved.village then toggleVillage.value = saved.village == "true" end
	if saved.desertPyramid then toggleDesertPyramid.value = saved.desertPyramid == "true" end
	if saved.jungleTemple then toggleJungleTemple.value = saved.jungleTemple == "true" end
	if saved.swampHut then toggleSwampHut.value = saved.swampHut == "true" end
	if saved.outpost then toggleOutpost.value = saved.outpost == "true" end
	if saved.igloo then toggleIgloo.value = saved.igloo == "true" end
	if saved.oceanMonument then toggleOceanMonument.value = saved.oceanMonument == "true" end
	if saved.oceanRuin then toggleOceanRuin.value = saved.oceanRuin == "true" end
	if saved.mansion then toggleMansion.value = saved.mansion == "true" end
	if saved.ancientCity then toggleAncientCity.value = saved.ancientCity == "true" end
	if saved.trailRuins then toggleTrailRuins.value = saved.trailRuins == "true" end
	if saved.ruinedPortal then toggleRuinedPortal.value = saved.ruinedPortal == "true" end
	if saved.buriedTreasure then toggleBuriedTreasure.value = saved.buriedTreasure == "true" end
	if saved.geode then toggleGeode.value = saved.geode == "true" end
end

-- ============================================================================
-- Section 5: Module State
-- ============================================================================

local scanResults = {}
local currentSeed = nil
local needsRescan = true
local lastPlayerX = 0
local lastPlayerZ = 0
local lastDimension = ""
local rescanKeyHeld = false

-- ============================================================================
-- Section 6: TickEvent Handler
-- ============================================================================

local function onTick()
	-- Check if player is in a world by verifying position is available
	local px, py, pz = player.position()
	if not px or px == 0.0 and py == 0.0 and pz == 0.0 then return end

	-- Update server URL if changed (use safe reader for persistence)
	local url = getStr(serverUrlTextBox, "http://127.0.0.1:7890")
	if url and url ~= "" then
		SERVER_URL = url:gsub("/+$", "") -- trim trailing slash
	end

	-- Check dimension change
	local dim = player.dimension()
	if dim ~= lastDimension then
		needsRescan = true
		lastDimension = dim or ""
	end

	-- Check seed change (use safe reader for persistence)
	local seed = parseSeed(getStr(seedTextBox, "1"))
	if seed ~= currentSeed then
		currentSeed = seed
		needsRescan = true
	end

	-- Check if player moved enough to warrant rescan
	if px and pz then
		local dx = px - lastPlayerX
		local dz = pz - lastPlayerZ
		local moveDist = math.sqrt(dx * dx + dz * dz)
		local radius = math.floor(getNum(radiusSlider, 10))
		if moveDist > radius * 8 then
			needsRescan = true
		end
		lastPlayerX = px
		lastPlayerZ = pz
	end

	-- Check rescan keybind (KeybindSetting.value = true when held)
	local rescanKeyDown = getBool(rescanKey, false)
	if rescanKeyDown and not rescanKeyHeld then
		needsRescan = true
	end
	rescanKeyHeld = rescanKeyDown

	-- Persist settings to disk (throttled)
	throttledSave()

	if not needsRescan then return end
	if not currentSeed then return end

	-- Build types list (use safe reader for toggle persistence)
	local typeIds = {}
	for _, entry in ipairs(TOGGLE_TYPE_MAP) do
		if getBool(entry.toggle, true) then
			table.insert(typeIds, entry.id)
		end
	end

	if #typeIds == 0 then
		scanResults = {}
		needsRescan = false
		return
	end

	-- Build URL (use getNum + math.floor for integer values)
	local typesStr = table.concat(typeIds, ",")
	local seedStr = string.format("%.0f", currentSeed)
	local scanUrl = string.format(
		"%s/scan?seed=%s&x=%.1f&z=%.1f&radius=%d&max=%d&types=%s",
		SERVER_URL,
		seedStr,
		lastPlayerX,
		lastPlayerZ,
		math.floor(getNum(radiusSlider, 10)),
		math.floor(getNum(maxResultsSlider, 15)),
		typesStr
	)

	-- Call API
	local ok, response = pcall(network.get, scanUrl)

	if ok and response and type(response) == "string" and response ~= "" and response ~= "null" then
		scanResults = parseScanResponse(response)
		serverOnline = true
		serverWarned = false
		if getBool(notifyToggle, true) then
			client.notify(string.format("Scan complete! %d structures found", #scanResults))
		end
	else
		if not serverWarned then
			serverWarned = true
			log("SeedFinder: Failed to reach server at " .. SERVER_URL)
		end
		serverOnline = false
	end

	needsRescan = false
end

-- ============================================================================
-- Section 7: RenderEvent Handler
-- ============================================================================

local function onRender()
	-- Only render if we have a position (player is in a world)
	local px, py, pz = player.position()
	if not px then return end

	ImGui.SetNextWindowSize({350, 300}, 4)
	ImGui.SetNextWindowBgAlpha(0.6)
	ImGui.Begin("SeedFinder")

	if not serverOnline then
		ImGui.Text("Server offline!")
		ImGui.Text("Start seedfinder_server.py first")
		ImGui.Text("URL: " .. SERVER_URL)
	elseif not currentSeed then
		ImGui.Text("Enter a seed in settings to begin")
	elseif #scanResults == 0 then
		ImGui.Text("No structures found nearby")
		ImGui.Text(string.format("Seed: %.0f | Radius: %d chunks", currentSeed, math.floor(getNum(radiusSlider, 10))))
	else
		ImGui.Text(string.format("Nearby Structures (%d)", #scanResults))
		ImGui.Text("--------------------------------")
		for i, result in ipairs(scanResults) do
			local icon = result.icon or "[?]"
			local displayName = result.displayName or result.name
			local distStr = formatDistance(result.distance)

			ImGui.BulletText(string.format(
				"%s %s (X:%.0f Z:%.0f) - %s chunks",
				icon, displayName, result.x, result.z, distStr
			))
		end
	end

	ImGui.End()
end

-- ============================================================================
-- Section 8: Module Lifecycle
-- ============================================================================

function onLoad()
	-- Load saved settings from disk (restores values after script reload)
	loadSettings()
	log("SeedFinder loaded (HTTP Bridge Edition)")
	log("Make sure seedfinder_server.py is running on " .. SERVER_URL)
end

function onEnable()
	needsRescan = true
	lastDimension = ""
	scanResults = {}

	-- Check server availability
	if not checkServer() then
		if not serverWarned then
			serverWarned = true
			log("SeedFinder: Server offline at " .. SERVER_URL .. ". Start seedfinder_server.py first.")
		end
		return
	end
end

function onDisable()
	-- Save settings immediately when module is disabled
	pcall(saveSettings)
	scanResults = {}
end

-- ============================================================================
-- Section 9: Chat Commands
-- ============================================================================

registerCommand("seedscan", function()
	needsRescan = true
	log("SeedFinder: Rescanning...")
end)

-- ============================================================================
-- Event Registration
-- ============================================================================

onEvent("TickEvent", onTick)
onEvent("RenderEvent", onRender)
onEvent("LoadEvent", onLoad)
onEvent("EnableEvent", onEnable)
onEvent("DisableEvent", onDisable)
