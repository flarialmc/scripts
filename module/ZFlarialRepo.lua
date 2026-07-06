name = "ZFlarialRepo"
description = "Browse, manage and install community Lua scripts"
author = "zebedelu"

-- ==========================================================
-- config
-- ==========================================================

-- relative path to flarial's data folder (%LOCALAPPDATA%\Flarial\Client\)
local CONFIG_PATH = "ZFlarialRepo.json"
local DATA_FOLDER = "Scripts/Data"

local MODULES_FOLDER = "Scripts/Modules"

-- default sources that load automatically on the first run
-- note that the folder is "Module" with a capital M (github is case-sensitive!)
local DEFAULT_SOURCES = {
	{ name = "Flarial Scripts - Official", repo = "https://github.com/flarialmc/scripts", folder = "module" },
	{ name = "zebedelu - Trustly", repo = "https://github.com/zebedelu/scripts", folder = "module" },
}

-- script state, kept at the top to avoid clutter
local sources = {}
local moduleCache = {} -- moduleCache[sourceName] = { loading, modules, error }
local installedFiles = {} -- installedFiles[filename] = true

local visible = false
local activeTab = "download"

-- new source form fields (must live outside the render function
-- so they don't reset every frame, imgui is immediate mode and doesn't store state alone)
local formName = ""
local formUrl = ""
local formFolder = ""

-- ==========================================================
-- simple json, just enough to save our config
-- and understand the github api response. there is no native
-- json lib here so we write our own
-- ==========================================================

local json = {}

function json.encode(value)
	local t = type(value)

	if t == "string" then
		local escaped = value:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "")
		return '"' .. escaped .. '"'
	elseif t == "number" or t == "boolean" then
		return tostring(value)
	elseif t == "table" then
		-- if index 1 is filled we treat it as an array
		if value[1] ~= nil then
			local parts = {}
			for _, v in ipairs(value) do
				table.insert(parts, json.encode(v))
			end
			return "[" .. table.concat(parts, ",") .. "]"
		else
			local parts = {}
			for k, v in pairs(value) do
				table.insert(parts, '"' .. tostring(k) .. '":' .. json.encode(v))
			end
			return "{" .. table.concat(parts, ",") .. "}"
		end
	end

	return "null"
end

-- manual decoder walking through the string position, covers what we need:
-- objects, arrays, escaped strings, numbers, bools and null
function json.decode(str)
	if type(str) ~= "string" then
		return nil
	end

	local pos = 1
	local len = #str
	local parseValue

	local function skipSpaces()
		while pos <= len and str:sub(pos, pos):match("%s") do
			pos = pos + 1
		end
	end

	local function parseString()
		pos = pos + 1 -- skip opening quote
		local out = {}
		local chunkStart = pos

		while pos <= len do
			local c = str:sub(pos, pos)

			if c == '"' then
				table.insert(out, str:sub(chunkStart, pos - 1))
				pos = pos + 1
				return table.concat(out)
			elseif c == "\\" then
				table.insert(out, str:sub(chunkStart, pos - 1))
				local nextChar = str:sub(pos + 1, pos + 1)
				local escapes = { n = "\n", t = "\t", r = "\r", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }
				table.insert(out, escapes[nextChar] or nextChar)
				pos = pos + 2
				chunkStart = pos
			else
				pos = pos + 1
			end
		end

		error("malformed json: unclosed string")
	end

	local function parseNumber()
		local start = pos
		while pos <= len and str:sub(pos, pos):match("[%d%.%-%+eE]") do
			pos = pos + 1
		end
		return tonumber(str:sub(start, pos - 1))
	end

	local function parseArray()
		pos = pos + 1
		local arr = {}
		skipSpaces()

		if str:sub(pos, pos) == "]" then
			pos = pos + 1
			return arr
		end

		while true do
			skipSpaces()
			table.insert(arr, parseValue())
			skipSpaces()
			local c = str:sub(pos, pos)
			if c == "," then
				pos = pos + 1
			else
				pos = pos + 1 -- closes ]
				break
			end
		end

		return arr
	end

	local function parseObject()
		pos = pos + 1
		local obj = {}
		skipSpaces()

		if str:sub(pos, pos) == "}" then
			pos = pos + 1
			return obj
		end

		while true do
			skipSpaces()
			local key = parseString()
			skipSpaces()
			pos = pos + 1 -- skips :
			skipSpaces()
			obj[key] = parseValue()
			skipSpaces()
			local c = str:sub(pos, pos)
			if c == "," then
				pos = pos + 1
			else
				pos = pos + 1 -- closes }
				break
			end
		end

		return obj
	end

	parseValue = function()
		skipSpaces()
		local c = str:sub(pos, pos)

		if c == '"' then
			return parseString()
		elseif c == "{" then
			return parseObject()
		elseif c == "[" then
			return parseArray()
		elseif str:sub(pos, pos + 3) == "true" then
			pos = pos + 4
			return true
		elseif str:sub(pos, pos + 4) == "false" then
			pos = pos + 5
			return false
		elseif str:sub(pos, pos + 3) == "null" then
			pos = pos + 4
			return nil
		else
			return parseNumber()
		end
	end

	local ok, result = pcall(function()
		skipSpaces()
		return parseValue()
	end)

	if ok then
		return result
	end

	return nil
end

-- ==========================================================
-- helpers
-- ==========================================================

-- wraps text at spaces so it doesn't get cut off or overflow the imgui window
local function wrapText(text, maxChars)
    if not text or text == "" then return "No description provided." end
    if #text <= maxChars then return text end
    
    local wrapped = ""
    local currentLine = ""
    
    for word in text:gmatch("%S+") do
        if #currentLine + #word + 1 > maxChars then
            wrapped = wrapped .. currentLine .. "\n"
            currentLine = word
        else
            if currentLine == "" then
                currentLine = word
            else
                currentLine = currentLine .. " " .. word
            end
        end
    end
    wrapped = wrapped .. currentLine
    return wrapped
end

-- reads the first lines of the .lua and tries to find name/description/author,
-- without executing the file (we don't want to run third-party code just
-- to get metadata)
local function extractMeta(source)
	local meta = { name = "unknown", description = "no description", author = "unknown", version=0.0 }

	for line in source:gmatch("[^\r\n]+") do
		local n = line:match('^%s*name%s*=%s*["\'](.-)["\']')
		if n then meta.name = n end

		local d = line:match('^%s*description%s*=%s*["\'](.-)["\']')
		if d then meta.description = d end

		local a = line:match('^%s*author%s*=%s*["\'](.-)["\']')
		if a then meta.author = a end
		
		local v = line:match('^%s*version%s*=%s*["\'](.-)["\']')
		if v then meta.version = v end

		-- as soon as it hits a top-level function we are past the header,
		-- no need to keep reading the whole file
		if line:match("^%s*function%s") then
			break
		end
	end

	return meta
end

-- extracts owner/repo from a url like https://github.com/owner/repo
local function parseRepoUrl(url)
	local owner, repo = url:match("github%.com/([^/]+)/([^/]+)")
	if repo then
		repo = repo:gsub("%.git$", ""):gsub("/+$", "")
	end
	return owner, repo
end

-- checks what already exists in the local modules folder
local function getInstalledFiles()
	local installed = {}

	if fs.exists(MODULES_FOLDER) then
		local files = fs.listDirectory(MODULES_FOLDER)
		for _, filename in ipairs(files) do
			installed[filename] = true
		end
	end

	return installed
end

-- ==========================================================
-- source persistence
-- ==========================================================

local function saveSources()
	fs.remove(DATA_FOLDER.."/"..CONFIG_PATH)
	fs.writeFile(DATA_FOLDER.."/"..CONFIG_PATH, json.encode({ sources = sources }))
end

local function loadSources()
	if fs.exists(CONFIG_PATH) then
		local raw = fs.readFile(CONFIG_PATH)
		local data = json.decode(raw)

		if data and data.sources and data.sources[1] then
			sources = data.sources
			return
		end
	end

	-- first run or corrupted file: load defaults and save them
	sources = DEFAULT_SOURCES
	saveSources()
end

-- ==========================================================
-- github (the trick to avoid 403 errors)
-- ==========================================================

-- helper function to process jsdelivr list and download metadata
local function processListAndFetchMetas(response, owner, repo, branch, folder, sourceName)
	local ok, data = pcall(json.decode, response)
	
	-- jsdelivr returns a json with a "files" table
	if not ok or type(data) ~= "table" or not data.files then
		moduleCache[sourceName] = { loading = false, modules = {}, error = "no .lua modules found in this folder" }
		return
	end

	local pending = 0
	local collected = {}

	for _, file in ipairs(data.files) do
		-- filter only files ending with .lua
		if file.name and file.name:match("%.lua$") then
			pending = pending + 1
			
			-- build raw.githubusercontent url to download raw content
			local rawUrl = "https://raw.githubusercontent.com/" .. owner .. "/" .. repo .. "/" .. branch .. "/" .. folder .. "/" .. file.name
			
			network.getAsync(rawUrl, function(content, code2, ok2)
				pending = pending - 1

				if ok2 and content and content ~= "" then
					local meta = extractMeta(content)
					table.insert(collected, {
						filename = file.name,
						name = meta.name,
						description = meta.description,
						author = meta.author,
						version = meta.version,
						downloadUrl = rawUrl,
					})
				end

				-- when all headers are downloaded, update cache
				if pending == 0 then
					moduleCache[sourceName] = { loading = false, modules = collected, error = nil }
				end
			end)
		end
	end

	if pending == 0 then
		moduleCache[sourceName] = { loading = false, modules = {}, error = "no .lua modules found in this folder" }
	end
end

local function refreshSource(source)
	moduleCache[source.name] = { loading = true, modules = {}, error = nil }

	local owner, repo = parseRepoUrl(source.repo)
	if not owner or not repo then
		moduleCache[source.name] = { loading = false, modules = {}, error = "invalid repository url" }
		return
	end

	local branch = "main"
	local folder = source.folder

	-- TACTIC 1: Try to download index.json (used by flarialmc) via raw.githubusercontent
	-- raw doesn't require user-agent so it doesn't throw 403.
	-- flarialmc uses "module-index.json" (all lowercase) at the root.
	local indexUrl = "https://raw.githubusercontent.com/" .. owner .. "/" .. repo .. "/" .. branch .. "/" .. string.lower(folder) .. "-index.json"
	
	network.getAsync(indexUrl, function(indexResponse, indexStatus, indexSuccess)
		if indexSuccess and indexStatus == 200 and indexResponse then
			-- found the index! flarialmc uses a specific format with "filename" and "path"
			local ok, list = pcall(json.decode, indexResponse)
			if ok and type(list) == "table" then
				local pending = 0
				local collected = {}
				
				for _, item in ipairs(list) do
					if item.filename and item.filename:match("%.lua$") then
						pending = pending + 1
						-- the path in flarial's index already includes the folder (e.g., Module/Script.lua)
						local rawUrl = "https://raw.githubusercontent.com/" .. owner .. "/" .. repo .. "/" .. branch .. "/" .. (item.path or item.filename)
						
						network.getAsync(rawUrl, function(content, code2, ok2)
							pending = pending - 1
							if ok2 and content and content ~= "" then
								local meta = extractMeta(content)
								table.insert(collected, {
									filename = item.filename,
									name = meta.name,
									description = meta.description,
									author = meta.author,
									version = meta.version,
									downloadUrl = rawUrl,
								})
							end
							if pending == 0 then
								moduleCache[source.name] = { loading = false, modules = collected, error = nil }
							end
						end)
					end
				end
				
				if pending == 0 then
					moduleCache[source.name] = { loading = false, modules = {}, error = "no .lua modules found in the index" }
				end
				return
			end
		end

		-- TACTIC 2 (FALLBACK): If there's no index.json, we use jsDelivr to list the folder.
		-- jsDelivr is a CDN that mirrors github, DOES NOT require User-Agent and DOES NOT throw 403.
		local listUrl = "https://data.jsdelivr.com/v1/package/gh/" .. owner .. "/" .. repo .. "@" .. branch .. "/" .. folder
		
		network.getAsync(listUrl, function(listResponse, listStatus, listSuccess)
			if not listSuccess or listStatus ~= 200 then
				-- if it fails on main, try master (older repos use master)
				local masterUrl = "https://data.jsdelivr.com/v1/package/gh/" .. owner .. "/" .. repo .. "@master/" .. folder
				network.getAsync(masterUrl, function(masterResponse, masterStatus, masterSuccess)
					if not masterSuccess or masterStatus ~= 200 then
						moduleCache[source.name] = { loading = false, modules = {}, error = "could not access folder (check url, branch and folder)" }
						return
					end
					processListAndFetchMetas(masterResponse, owner, repo, "master", folder, source.name)
				end)
				return
			end
			
			processListAndFetchMetas(listResponse, owner, repo, branch, folder, source.name)
		end)
	end)
end

local function refreshAllSources()
	for _, source in ipairs(sources) do
		refreshSource(source)
	end
end

local function downloadModule(mod)
	network.getAsync(mod.downloadUrl, function(content, statusCode, success)
		if success and content and content ~= "" then
			if not fs.exists(MODULES_FOLDER) then
				fs.create(MODULES_FOLDER)
			end

			fs.writeFile(MODULES_FOLDER .. "/" .. mod.filename, content)
			installedFiles = getInstalledFiles()
			client.notify("Module downloaded: " .. mod.name)
		else
			client.notify("Error downloading module: " .. mod.name)
		end
	end)
end

local function deleteModule(filename)
	local path = MODULES_FOLDER .. "/" .. filename

	if fs.exists(path) then
		fs.remove(path)
		installedFiles = getInstalledFiles()
		client.notify("Module removed: " .. filename)
	end
end

-- ==========================================================
-- interface
-- ==========================================================

local function renderDownloadTab()
	
	if not sources[1] then
		ImGui.Text("No sources registered. Add one in the 'Sources' tab.")
		return
	end

	for _, source in ipairs(sources) do
		if ImGui.CollapsingHeader(source.name, 0) then
			local cache = moduleCache[source.name]

			if not cache or cache.loading then
				ImGui.BulletText("loading...")
			elseif cache.error then
				ImGui.BulletText(cache.error)
			else
				-- downloaded ones go to the top of the list for this source
				local downloaded, notDownloaded = {}, {}
				for _, mod in ipairs(cache.modules) do
					if installedFiles[mod.filename] then
						table.insert(downloaded, mod)
					else
						table.insert(notDownloaded, mod)
					end
				end

				local ordered = {}
				for _, m in ipairs(downloaded) do table.insert(ordered, m) end
				for _, m in ipairs(notDownloaded) do table.insert(ordered, m) end

				for i, mod in ipairs(ordered) do
					-- unique id to avoid widget conflicts when two modules
					-- have similar names across different sources
					local uid = source.name .. "_" .. mod.filename .. "_" .. i

					ImGui.BulletText("Name: "..mod.name)
					ImGui.Text("   Author: " .. mod.author)
					
					-- wrap description text so it breaks into new lines without cutting words
					local wrappedDesc = wrapText(mod.description, 60)
					ImGui.Text("   Description: ")
					ImGui.Text("   "..wrappedDesc)

					ImGui.Text("   Version: "..mod.version)

					local alreadyExists = fs.exists(MODULES_FOLDER.."/"..mod.filename)
					local label = alreadyExists and "Download (Overwrite)" or "Download"

					if ImGui.Button(label .. "##dl_" .. uid) then
						if alreadyExists then
                            deleteModule(mod.filename)
                        end
						downloadModule(mod)
					end

					if alreadyExists then
						ImGui.SameLine(0, -1)
						if ImGui.Button("Delete##del_" .. uid) then
							deleteModule(mod.filename)
						end
					end
					
					ImGui.Text("")
				end
			end
		end
	end
end

local function renderSourcesTab()
	ImGui.Text("Registered Sources")

	local toRemove = nil

	for i, source in ipairs(sources) do
		ImGui.BulletText("Name: "..source.name)
		ImGui.Text("   Repository: "..source.repo)
		ImGui.Text("   Folder: "..source.folder)
		if ImGui.Button("Remove##src_" .. i) then
			toRemove = i
		end
		ImGui.Text("  ")
	end

	if toRemove then
		table.remove(sources, toRemove)
		saveSources()
	end

	ImGui.Text(string.rep("-", 50))
	ImGui.Text("Add new source")

    -- these inputs now work properly because client.freeMouse() is called onEnable
	formName = ImGui.InputText("Custom Name", formName)
	formUrl = ImGui.InputText("Repository URL", formUrl)
	formFolder = ImGui.InputText("Folder inside repo", formFolder)

	if ImGui.Button("Add New Source") then
		local name = util.trim(formName)
		local url = util.trim(formUrl)
		local folder = util.trim(formFolder)

		if name ~= "" and url ~= "" and folder ~= "" then
			local newSource = { name = name, repo = url, folder = folder }
			table.insert(sources, newSource)
			saveSources()
			refreshSource(newSource)

			formName, formUrl, formFolder = "", "", ""
		else
			client.notify("Please fill all fields before adding")
		end
	end

	ImGui.Text("If it doesn't work, try:")
	ImGui.Text(".zflarialrepo help")
	ImGui.Text("")
	ImGui.BulletText("CONTRIBUTING A SCRIPT")
	ImGui.Text("To publish your script in the official Flarial repository, follow these steps:")
	ImGui.Text("1. Go to https://github.com/flarialmc/scripts")
	ImGui.Text("2. Create a Fork of the official repository.")
	ImGui.Text("3. Add your .lua script to the 'Module' folder.")
	ImGui.Text("4. Edit the 'module-index.json' file in the root directory.")
	ImGui.Text("   4.1. Add your script's information there.")
	ImGui.Text("5. Open a Pull Request to the main repository.")
	ImGui.Text("6. Wait for the review. And that's it!")
	ImGui.Text("")
	ImGui.BulletText("ADDING A CUSTOM SOURCE")
	ImGui.Text("If you own a GitHub repository and want it featured")
	ImGui.Text("as a default source in ZFlarialRepo:")
	ImGui.Text("1. Make sure your repository is public and organized.")
	ImGui.Text("2. Open a Pull Request on https://github.com/zebedelu/scripts")
	ImGui.Text("3. Add your repository's URL and folder to the default sources list.")
	ImGui.Text("4. Wait for the review to be approved. And done!")
end

local function renderWindow()
	ImGui.SetNextWindowSize({500, 600}, 4)
	ImGui.SetNextWindowBgAlpha(0.6)
	ImGui.Begin("ZFlarialRepo")

	if ImGui.Button("Download Modules") then
		activeTab = "download"
	end

	ImGui.SameLine(0, -1)

	if ImGui.Button("Sources") then
		activeTab = "sources"
	end

	if activeTab == "download" then
		if ImGui.Button("Refresh List") then
			refreshAllSources()
		end
		renderDownloadTab()
	else
		renderSourcesTab()
	end

	ImGui.End()
end

-- ==========================================================
-- module lifecycle
-- ==========================================================

function onEnable()
	visible = true
    -- free the mouse and keyboard so ImGui InputText can actually receive typing events
    client.freeMouse()
	loadSources()
	installedFiles = getInstalledFiles()
	refreshAllSources()
end

function onDisable()
	visible = false
    -- grab the mouse back so the player can look around and play normally
    client.grabMouse()
end

onEvent("RenderEvent", function()
	if visible then
		renderWindow()
	end
end)
-- ==========================================================
-- chat commands (type them directly in game chat with a dot)
-- ==========================================================

registerCommand("zflarialrepo", "Manage ZFlarialRepo sources and actions via chat", function(args)
    -- if no arguments, show help
    if not args or #args == 0 then
        client.displayLocalMessage("[ZFlarialRepo] Use '.zflarialrepo help' to see available commands.")
        return
    end

    local subcommand = util.lower(util.trim(args[1]))

    -- HELP command
    if subcommand == "help" then
        client.displayLocalMessage("[ZFlarialRepo] Available commands:")
        client.displayLocalMessage("  .zflarialrepo help - Shows this help message")
        client.displayLocalMessage("  .zflarialrepo addfont <name> <repo_url> <folder> - Adds a new source")
        client.displayLocalMessage("  .zflarialrepo removefont <name> - Removes a source by its custom name")
        client.displayLocalMessage("  .zflarialrepo list - Lists all registered sources")
        client.displayLocalMessage("  .zflarialrepo open - Opens the Store window")
        return
    end

    -- LIST command
    if subcommand == "list" then
        if not sources or #sources == 0 then
            client.displayLocalMessage("[ZFlarialRepo] No sources registered.")
            return
        end
        
        client.displayLocalMessage("[ZFlarialRepo] Registered sources (" .. #sources .. "):")
        for i, source in ipairs(sources) do
            client.displayLocalMessage("  " .. i .. ". " .. source.name)
            client.displayLocalMessage("     Repo: " .. source.repo)
            client.displayLocalMessage("     Folder: " .. source.folder)
        end
        return
    end

    -- OPEN command (toggles the ImGui window)
    if subcommand == "open" then
        visible = not visible
        if visible then
            client.freeMouse()
            client.displayLocalMessage("[ZFlarialRepo] Window opened.")
        else
            client.grabMouse()
            client.displayLocalMessage("[ZFlarialRepo] Window closed.")
        end
        return
    end

    -- ADDFONT command: .zflarialrepo addfont <name> <repo> <folder>
    if subcommand == "addfont" then
        -- we need exactly 3 more arguments (name, repo, folder)
        if #args < 4 then
            client.displayLocalMessage("[ZFlarialRepo] Error: Missing arguments.")
            client.displayLocalMessage("[ZFlarialRepo] Usage: .zflarialrepo addfont <name> <repo_url> <folder>")
            client.displayLocalMessage("[ZFlarialRepo] Example: .zflarialrepo addfont \"My Repo\" https://github.com/user/repo Module")
            return
        end

        -- if the user passed more than 4 args, they probably didn't quote a name with spaces
        -- let's try to be smart: args[2] to args[#args-2] is the name, args[#args-1] is repo, args[#args] is folder
        -- but if there are exactly 4 args, it's simple: args[2]=name, args[3]=repo, args[4]=folder
        local name = ""
        local repo = ""
        local folder = ""
        
        if #args == 4 then
            name = util.trim(args[2])
            repo = util.trim(args[3])
            folder = util.trim(args[4])
        else
            -- if there are spaces in the name (and user forgot quotes), try to parse smartly:
            -- last arg is folder, second to last is repo, everything in between is name
            folder = util.trim(args[#args])
            repo = util.trim(args[#args - 1])
            
            local nameParts = {}
            for i = 2, #args - 2 do
                table.insert(nameParts, args[i])
            end
            name = util.trim(table.concat(nameParts, " "))
        end

        if name == "" or repo == "" or folder == "" then
            client.displayLocalMessage("[ZFlarialRepo] Error: Name, repository URL and folder cannot be empty.")
            return
        end

        -- check if a source with this name already exists
        for _, source in ipairs(sources) do
            if util.lower(source.name) == util.lower(name) then
                client.displayLocalMessage("[ZFlarialRepo] Error: A source named '" .. name .. "' already exists.")
                return
            end
        end

        -- basic url validation (must contain github.com)
        if not repo:find("github%.com") then
            client.displayLocalMessage("[ZFlarialRepo] Warning: The URL doesn't look like a GitHub repository. Adding anyway...")
        end

        local newSource = { name = name, repo = repo, folder = folder }
        table.insert(sources, newSource)
        saveSources()
        refreshSource(newSource)

        client.displayLocalMessage("[ZFlarialRepo] Source '" .. name .. "' added successfully! Fetching modules...")
        return
    end

    -- REMOVEFONT command: .zflarialrepo removefont <name>
    if subcommand == "removefont" or subcommand == "remove" then
        if #args < 2 then
            client.displayLocalMessage("[ZFlarialRepo] Error: Missing source name.")
            client.displayLocalMessage("[ZFlarialRepo] Usage: .zflarialrepo removefont <name>")
            return
        end

        -- if name has spaces, join all args from index 2 onwards
        local nameParts = {}
        for i = 2, #args do
            table.insert(nameParts, args[i])
        end
        local nameToRemove = util.trim(table.concat(nameParts, " "))

        local found = false
        local removedIndex = nil
        
        for i, source in ipairs(sources) do
            if util.lower(source.name) == util.lower(nameToRemove) then
                found = true
                removedIndex = i
                break
            end
        end

        if found then
            local removedSource = table.remove(sources, removedIndex)
            saveSources()
            
            -- clear cache for this source
            if moduleCache[removedSource.name] then
                moduleCache[removedSource.name] = nil
            end

            client.displayLocalMessage("[ZFlarialRepo] Source '" .. removedSource.name .. "' removed successfully!")
        else
            client.displayLocalMessage("[ZFlarialRepo] Error: No source found with the name '" .. nameToRemove .. "'.")
            client.displayLocalMessage("[ZFlarialRepo] Tip: Use '.zflarialrepo list' to see all registered sources.")
        end
        return
    end

    -- unknown subcommand
    client.displayLocalMessage("[ZFlarialRepo] Unknown command: '" .. subcommand .. "'")
    client.displayLocalMessage("[ZFlarialRepo] Use '.zflarialrepo help' to see available commands.")
end)