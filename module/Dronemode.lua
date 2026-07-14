name = "Drone mode"
description = "Its a drone mode, not freecam :D"
author = "zebedelu"
version = 3.0

-- ==========================================
-- 1. CONSTANTS AND STATE
-- ==========================================

-- Internal render resolution. Each ray becomes one screen tile.
local W, H = 128, 64
local TILE_W, TILE_H = 15, 16
local MAX_RAY_STEPS = 60

-- Drone camera position and orientation.
local camX, camY, camZ = 0, 64, 0
local centerX, centerY, centerZ = 0, 64, 0
local yaw, pitch = 0, 0
local camInitialized = false

-- Real player position, cached outside RenderEvent. Flarial explicitly marks
-- player API access from RenderEvent as unsafe.
local playerX, playerY, playerZ = 0, 0, 0
local fpX, fpY, fpZ = 0, 0, 0

-- Render and scan state.
local renderVisible = false
local scanCompleted = false
local raycastDirty = true

-- Movement is expressed per second, so it no longer changes with framerate.
local keys = {}
local MOVE_SPEED = 8.0
local FAST_SPEED = 20.0
local SLOW_SPEED = 2.0
local ROTATE_SPEED = 3.9

-- The cache uses one flat integer key per voxel. Air is not stored at all.
-- A procedural shell cursor eliminates millions of coordinate tables, while
-- the flat cache eliminates nested hash tables at large radii.
local worldCache = {}
local scanIndex = 0
local scanRadius, scanFace = 0, 0
local scanA, scanB = 0, 0
local scanCredit = 0
local lastUpdateTime = util.time()
local SIDE, PLANE = 0, 0
local TOTAL_BLOCKS = 0
local worldMinX, worldMaxX = 0, 0
local worldMinY, worldMaxY = 0, 0
local worldMinZ, worldMaxZ = 0, 0

-- Rising-edge state for configurable keybinds.
local uiKeyWasDown = false
local rescanKeyWasDown = false
local teleportKeyWasDown = false

-- Main settings.
local RADIUS = 30
local BLOCKS_PER_SECOND = 5000
local MAX_SCAN_BATCH = 2048

-- Raycasting is capped at 30 Hz. Rendering reuses the most recent run list,
-- and a static completed scene does not raycast again until something changes.
local RAYCAST_INTERVAL_MS = 1000 / 30
local lastRaycastTime = 0

-- Cached pixel colors and two-dimensionally merged draw runs.
local pixelColors = {}
local drawRuns = {}
local drawRunCount = 0
local activeRunsA, activeRunsB = {}, {}

-- Cache hot functions to avoid repeated global/table lookups.
local m_floor = math.floor
local m_abs = math.abs
local m_cos = math.cos
local m_sin = math.sin
local m_min = math.min
local m_max = math.max
local getTime = util.time
local getBlock = world.getBlock
local getPlayerPosition = player.position
local notify = client.notify
local getScreenName = client.getScreenName
local getDeltaTime = ImGui.GetDeltaTime
local getForegroundDrawList = ImGui.GetForegroundDrawList

-- ==========================================
-- 2. SETTINGS
-- ==========================================

settings.addHeader("Configure drone")

local RadiusSlider = settings.addSlider("Radius (blocks)", "Scan radius in blocks; recommended: 30", 30, 100, 5)
local BlockPerSecondSlider = settings.addSlider("Blocks per second", "Scan throughput; recommended: 20000", 5000, 20000, 200)

local OpenDroneUIKey = settings.addKeybind("Open Drone UI", "Open the drone UI while inventory is open", "o")
local RescanKey = settings.addKeybind("Rescan", "Rescan around the current camera position", "u")
local TeleportToPlayerKey = settings.addKeybind("TP to player", "Move the camera to the player and restart the scan", "i")

-- ==========================================
-- 3. KEY MAPPING
-- ==========================================

local keyMap = {
    -- Letters: W, A, S, D (movement).
    [87] = "w", [17] = "w",   -- W (17 = LWJGL KEY_W)
    [65] = "a", [30] = "a",   -- A
    [83] = "s", [31] = "s",   -- S
    [68] = "d", [32] = "d",   -- D

    -- Other letters (fallback mappings).
    [90] = "z", [44] = "z",   -- Z
    [67] = "c", [46] = "c",   -- C
    [88] = "x", [45] = "x",   -- X

    -- Modifiers.
    [32] = "space",           -- ASCII space. This intentionally wins over LWJGL D.
    [57] = "space",           -- LWJGL space.

    [16] = "shift", [42] = "shift",   -- Left Shift.
    [54] = "shift",                   -- Right Shift.
    [340] = "shift", [344] = "shift", -- Shift (GLFW)

    -- 17 is LWJGL W and cannot also be used for Ctrl.
    [29] = "ctrl",                    -- Left Ctrl.
    [157] = "ctrl",                   -- Right Ctrl.
    [341] = "ctrl", [345] = "ctrl",   -- Ctrl (GLFW)
    [162] = "ctrl", [163] = "ctrl",   -- Ctrl (Windows VK)

    -- Arrow keys: camera rotation.
    [265] = "up", [38] = "up", [200] = "up",
    [264] = "down", [40] = "down", [208] = "down",
    [263] = "left", [37] = "left", [203] = "left",
    [266] = "right", [39] = "right", [205] = "right"
}

-- ==========================================
-- 4. BLOCK COLORS
-- ==========================================

local blockColors = {
    ["minecraft:stone"] = {125, 125, 125}, ["minecraft:granite"] = {132, 98, 78}, ["minecraft:polished_granite"] = {140, 104, 82}, ["minecraft:diorite"] = {173, 173, 173}, ["minecraft:polished_diorite"] = {180, 180, 180}, ["minecraft:andesite"] = {126, 126, 131}, ["minecraft:polished_andesite"] = {135, 135, 140}, ["minecraft:deepslate"] = {68, 68, 73}, ["minecraft:cobbled_deepslate"] = {75, 75, 80}, ["minecraft:polished_deepslate"] = {82, 82, 87}, ["minecraft:calcite"] = {200, 200, 190}, ["minecraft:tuff"] = {100, 100, 95}, ["minecraft:dripstone_block"] = {155, 145, 130}, ["minecraft:grass_block"] = {90, 168, 55}, ["minecraft:dirt"] = {134, 96, 67}, ["minecraft:coarse_dirt"] = {125, 90, 62}, ["minecraft:podzol"] = {110, 100, 70}, ["minecraft:rooted_dirt"] = {120, 85, 58}, ["minecraft:mud"] = {75, 60, 45}, ["minecraft:mud_bricks"] = {100, 80, 60}, ["minecraft:packed_mud"] = {85, 68, 50}, ["minecraft:cobblestone"] = {122, 122, 122}, ["minecraft:oak_planks"] = {168, 132, 88}, ["minecraft:spruce_planks"] = {120, 90, 60}, ["minecraft:birch_planks"] = {205, 185, 145}, ["minecraft:jungle_planks"] = {155, 120, 65}, ["minecraft:acacia_planks"] = {175, 125, 70}, ["minecraft:dark_oak_planks"] = {100, 75, 50}, ["minecraft:mangrove_planks"] = {140, 100, 65}, ["minecraft:cherry_planks"] = {215, 175, 155}, ["minecraft:bamboo_planks"] = {195, 170, 110}, ["minecraft:bamboo_mosaic"] = {185, 160, 100}, ["minecraft:oak_log"] = {108, 82, 55}, ["minecraft:spruce_log"] = {85, 65, 45}, ["minecraft:birch_log"] = {175, 155, 125}, ["minecraft:jungle_log"] = {95, 70, 35}, ["minecraft:acacia_log"] = {100, 65, 30}, ["minecraft:dark_oak_log"] = {70, 52, 35}, ["minecraft:mangrove_log"] = {80, 55, 35}, ["minecraft:cherry_log"] = {150, 100, 80}, ["minecraft:stripped_oak_log"] = {165, 135, 95}, ["minecraft:stripped_spruce_log"] = {140, 110, 75}, ["minecraft:stripped_birch_log"] = {200, 180, 145}, ["minecraft:stripped_jungle_log"] = {160, 130, 80}, ["minecraft:stripped_acacia_log"] = {170, 135, 85}, ["minecraft:stripped_dark_oak_log"] = {115, 90, 65}, ["minecraft:stripped_mangrove_log"] = {145, 115, 80}, ["minecraft:stripped_cherry_log"] = {195, 155, 135}, ["minecraft:oak_wood"] = {108, 82, 55}, ["minecraft:spruce_wood"] = {85, 65, 45}, ["minecraft:birch_wood"] = {175, 155, 125}, ["minecraft:jungle_wood"] = {95, 70, 35}, ["minecraft:acacia_wood"] = {100, 65, 30}, ["minecraft:dark_oak_wood"] = {70, 52, 35}, ["minecraft:mangrove_wood"] = {80, 55, 35}, ["minecraft:cherry_wood"] = {150, 100, 80}, ["minecraft:stripped_oak_wood"] = {165, 135, 95}, ["minecraft:stripped_spruce_wood"] = {140, 110, 75}, ["minecraft:stripped_birch_wood"] = {200, 180, 145}, ["minecraft:stripped_jungle_wood"] = {160, 130, 80}, ["minecraft:stripped_acacia_wood"] = {170, 135, 85}, ["minecraft:stripped_dark_oak_wood"] = {115, 90, 65}, ["minecraft:stripped_mangrove_wood"] = {145, 115, 80}, ["minecraft:stripped_cherry_wood"] = {195, 155, 135}, ["minecraft:oak_leaves"] = {55, 140, 45}, ["minecraft:spruce_leaves"] = {40, 75, 35}, ["minecraft:birch_leaves"] = {65, 155, 50}, ["minecraft:jungle_leaves"] = {35, 120, 25}, ["minecraft:acacia_leaves"] = {75, 145, 35}, ["minecraft:dark_oak_leaves"] = {45, 95, 30}, ["minecraft:mangrove_leaves"] = {50, 115, 40}, ["minecraft:cherry_leaves"] = {235, 160, 185}, ["minecraft:azalea_leaves"] = {45, 130, 55}, ["minecraft:flowering_azalea_leaves"] = {180, 100, 160}, ["minecraft:sand"] = {219, 211, 160}, ["minecraft:red_sand"] = {193, 118, 62}, ["minecraft:sandstone"] = {215, 205, 155}, ["minecraft:red_sandstone"] = {185, 110, 55}, ["minecraft:cut_sandstone"] = {215, 205, 155}, ["minecraft:cut_red_sandstone"] = {185, 110, 55}, ["minecraft:chiseled_sandstone"] = {210, 200, 150}, ["minecraft:chiseled_red_sandstone"] = {180, 105, 50}, ["minecraft:smooth_sandstone"] = {220, 212, 165}, ["minecraft:smooth_red_sandstone"] = {195, 120, 65}, ["minecraft:gravel"] = {136, 126, 126}, ["minecraft:flint"] = {100, 100, 105}, ["minecraft:coal_ore"] = {115, 115, 115}, ["minecraft:deepslate_coal_ore"] = {65, 65, 70}, ["minecraft:iron_ore"] = {130, 125, 120}, ["minecraft:deepslate_iron_ore"] = {75, 72, 70}, ["minecraft:copper_ore"] = {135, 120, 100}, ["minecraft:deepslate_copper_ore"] = {80, 72, 62}, ["minecraft:gold_ore"] = {140, 130, 100}, ["minecraft:deepslate_gold_ore"] = {85, 78, 62}, ["minecraft:redstone_ore"] = {140, 110, 110}, ["minecraft:deepslate_redstone_ore"] = {85, 68, 68}, ["minecraft:emerald_ore"] = {120, 140, 115}, ["minecraft:deepslate_emerald_ore"] = {72, 85, 72}, ["minecraft:lapis_ore"] = {110, 115, 140}, ["minecraft:deepslate_lapis_ore"] = {68, 70, 88}, ["minecraft:diamond_ore"] = {125, 130, 140}, ["minecraft:deepslate_diamond_ore"] = {75, 78, 88}, ["minecraft:nether_gold_ore"] = {95, 60, 60}, ["minecraft:raw_iron_block"] = {180, 160, 150}, ["minecraft:raw_copper_block"] = {185, 135, 95}, ["minecraft:raw_gold_block"] = {195, 175, 85}, ["minecraft:coal_block"] = {25, 25, 25}, ["minecraft:iron_block"] = {220, 220, 220}, ["minecraft:gold_block"] = {250, 225, 80}, ["minecraft:copper_block"] = {185, 120, 70}, ["minecraft:exposed_copper"] = {170, 130, 100}, ["minecraft:weathered_copper"] = {110, 110, 105}, ["minecraft:oxidized_copper"] = {75, 110, 105}, ["minecraft:cut_copper"] = {185, 120, 70}, ["minecraft:exposed_cut_copper"] = {170, 130, 100}, ["minecraft:weathered_cut_copper"] = {110, 110, 105}, ["minecraft:oxidized_cut_copper"] = {75, 110, 105}, ["minecraft:chiseled_copper"] = {180, 115, 65}, ["minecraft:exposed_chiseled_copper"] = {165, 125, 95}, ["minecraft:weathered_chiseled_copper"] = {105, 105, 100}, ["minecraft:oxidized_chiseled_copper"] = {70, 105, 100}, ["minecraft:copper_door"] = {185, 120, 70}, ["minecraft:exposed_copper_door"] = {170, 130, 100}, ["minecraft:weathered_copper_door"] = {110, 110, 105}, ["minecraft:oxidized_copper_door"] = {75, 110, 105}, ["minecraft:copper_trapdoor"] = {185, 120, 70}, ["minecraft:exposed_copper_trapdoor"] = {170, 130, 100}, ["minecraft:weathered_copper_trapdoor"] = {110, 110, 105}, ["minecraft:oxidized_copper_trapdoor"] = {75, 110, 105}, ["minecraft:copper_grate"] = {180, 115, 65}, ["minecraft:exposed_copper_grate"] = {165, 125, 95}, ["minecraft:weathered_copper_grate"] = {105, 105, 100}, ["minecraft:oxidized_copper_grate"] = {70, 105, 100}, ["minecraft:copper_bulb"] = {185, 120, 70}, ["minecraft:exposed_copper_bulb"] = {170, 130, 100}, ["minecraft:weathered_copper_bulb"] = {110, 110, 105}, ["minecraft:oxidized_copper_bulb"] = {75, 110, 105}, ["minecraft:waxed_copper_block"] = {185, 120, 70}, ["minecraft:waxed_exposed_copper"] = {170, 130, 100}, ["minecraft:waxed_weathered_copper"] = {110, 110, 105}, ["minecraft:waxed_oxidized_copper"] = {75, 110, 105}, ["minecraft:waxed_cut_copper"] = {185, 120, 70}, ["minecraft:waxed_exposed_cut_copper"] = {170, 130, 100}, ["minecraft:waxed_weathered_cut_copper"] = {110, 110, 105}, ["minecraft:waxed_oxidized_cut_copper"] = {75, 110, 105}, ["minecraft:waxed_chiseled_copper"] = {180, 115, 65}, ["minecraft:waxed_exposed_chiseled_copper"] = {165, 125, 95}, ["minecraft:waxed_weathered_chiseled_copper"] = {105, 105, 100}, ["minecraft:waxed_oxidized_chiseled_copper"] = {70, 105, 100}, ["minecraft:waxed_copper_door"] = {185, 120, 70}, ["minecraft:waxed_exposed_copper_door"] = {170, 130, 100}, ["minecraft:waxed_weathered_copper_door"] = {110, 110, 105}, ["minecraft:waxed_oxidized_copper_door"] = {75, 110, 105}, ["minecraft:waxed_copper_trapdoor"] = {185, 120, 70}, ["minecraft:waxed_exposed_copper_trapdoor"] = {170, 130, 100}, ["minecraft:waxed_weathered_copper_trapdoor"] = {110, 110, 105}, ["minecraft:waxed_oxidized_copper_trapdoor"] = {75, 110, 105}, ["minecraft:waxed_copper_grate"] = {180, 115, 65}, ["minecraft:waxed_exposed_copper_grate"] = {165, 125, 95}, ["minecraft:waxed_weathered_copper_grate"] = {105, 105, 100}, ["minecraft:waxed_oxidized_copper_grate"] = {70, 105, 100}, ["minecraft:waxed_copper_bulb"] = {185, 120, 70}, ["minecraft:waxed_exposed_copper_bulb"] = {170, 130, 100}, ["minecraft:waxed_weathered_copper_bulb"] = {110, 110, 105}, ["minecraft:waxed_oxidized_copper_bulb"] = {75, 110, 105}, ["minecraft:diamond_block"] = {90, 220, 220}, ["minecraft:lapis_block"] = {35, 55, 150}, ["minecraft:emerald_block"] = {45, 180, 80}, ["minecraft:redstone_block"] = {180, 30, 30}, ["minecraft:netherite_block"] = {55, 50, 50}, ["minecraft:obsidian"] = {20, 18, 25}, ["minecraft:crying_obsidian"] = {60, 30, 70}, ["minecraft:glowstone"] = {220, 200, 120}, ["minecraft:redstone_lamp"] = {160, 130, 100}, ["minecraft:sea_lantern"] = {150, 220, 225}, ["minecraft:torch"] = {220, 180, 100}, ["minecraft:soul_torch"] = {80, 130, 200}, ["minecraft:lantern"] = {180, 160, 120}, ["minecraft:soul_lantern"] = {70, 110, 170}, ["minecraft:campfire"] = {160, 130, 100}, ["minecraft:soul_campfire"] = {60, 100, 160}, ["minecraft:white_wool"] = {230, 230, 230}, ["minecraft:orange_wool"] = {220, 130, 50}, ["minecraft:magenta_wool"] = {175, 75, 175}, ["minecraft:light_blue_wool"] = {135, 185, 220}, ["minecraft:yellow_wool"] = {230, 210, 75}, ["minecraft:lime_wool"] = {115, 185, 75}, ["minecraft:pink_wool"] = {220, 150, 165}, ["minecraft:gray_wool"] = {100, 100, 100}, ["minecraft:light_gray_wool"] = {160, 160, 160}, ["minecraft:cyan_wool"] = {75, 175, 175}, ["minecraft:purple_wool"] = {120, 60, 160}, ["minecraft:blue_wool"] = {60, 65, 160}, ["minecraft:brown_wool"] = {120, 85, 60}, ["minecraft:green_wool"] = {75, 120, 55}, ["minecraft:red_wool"] = {170, 50, 50}, ["minecraft:black_wool"] = {30, 30, 30}, ["minecraft:white_concrete"] = {215, 215, 215}, ["minecraft:orange_concrete"] = {210, 120, 45}, ["minecraft:magenta_concrete"] = {165, 65, 165}, ["minecraft:light_blue_concrete"] = {125, 175, 210}, ["minecraft:yellow_concrete"] = {220, 200, 65}, ["minecraft:lime_concrete"] = {105, 175, 65}, ["minecraft:pink_concrete"] = {210, 140, 155}, ["minecraft:gray_concrete"] = {90, 90, 90}, ["minecraft:light_gray_concrete"] = {150, 150, 150}, ["minecraft:cyan_concrete"] = {65, 165, 165}, ["minecraft:purple_concrete"] = {110, 50, 150}, ["minecraft:blue_concrete"] = {50, 55, 150}, ["minecraft:brown_concrete"] = {110, 75, 50}, ["minecraft:green_concrete"] = {65, 110, 45}, ["minecraft:red_concrete"] = {160, 40, 40}, ["minecraft:black_concrete"] = {20, 20, 20}, ["minecraft:white_concrete_powder"] = {215, 215, 215}, ["minecraft:orange_concrete_powder"] = {210, 120, 45}, ["minecraft:magenta_concrete_powder"] = {165, 65, 165}, ["minecraft:light_blue_concrete_powder"] = {125, 175, 210}, ["minecraft:yellow_concrete_powder"] = {220, 200, 65}, ["minecraft:lime_concrete_powder"] = {105, 175, 65}, ["minecraft:pink_concrete_powder"] = {210, 140, 155}, ["minecraft:gray_concrete_powder"] = {90, 90, 90}, ["minecraft:light_gray_concrete_powder"] = {150, 150, 150}, ["minecraft:cyan_concrete_powder"] = {65, 165, 165}, ["minecraft:purple_concrete_powder"] = {110, 50, 150}, ["minecraft:blue_concrete_powder"] = {50, 55, 150}, ["minecraft:brown_concrete_powder"] = {110, 75, 50}, ["minecraft:green_concrete_powder"] = {65, 110, 45}, ["minecraft:red_concrete_powder"] = {160, 40, 40}, ["minecraft:black_concrete_powder"] = {20, 20, 20}, ["minecraft:terracotta"] = {160, 110, 75}, ["minecraft:white_terracotta"] = {210, 205, 195}, ["minecraft:orange_terracotta"] = {185, 115, 65}, ["minecraft:magenta_terracotta"] = {150, 85, 120}, ["minecraft:light_blue_terracotta"] = {140, 155, 175}, ["minecraft:yellow_terracotta"] = {190, 165, 90}, ["minecraft:lime_terracotta"] = {130, 145, 85}, ["minecraft:pink_terracotta"] = {185, 125, 125}, ["minecraft:gray_terracotta"] = {105, 95, 90}, ["minecraft:light_gray_terracotta"] = {155, 145, 135}, ["minecraft:cyan_terracotta"] = {110, 135, 135}, ["minecraft:purple_terracotta"] = {130, 85, 125}, ["minecraft:blue_terracotta"] = {100, 90, 130}, ["minecraft:brown_terracotta"] = {130, 90, 65}, ["minecraft:green_terracotta"] = {105, 110, 80}, ["minecraft:red_terracotta"] = {150, 75, 60}, ["minecraft:black_terracotta"] = {55, 45, 40}, ["minecraft:white_glazed_terracotta"] = {220, 220, 215}, ["minecraft:orange_glazed_terracotta"] = {225, 140, 65}, ["minecraft:magenta_glazed_terracotta"] = {185, 90, 185}, ["minecraft:light_blue_glazed_terracotta"] = {150, 195, 230}, ["minecraft:yellow_glazed_terracotta"] = {235, 215, 85}, ["minecraft:lime_glazed_terracotta"] = {130, 195, 85}, ["minecraft:pink_glazed_terracotta"] = {225, 160, 175}, ["minecraft:gray_glazed_terracotta"] = {115, 115, 115}, ["minecraft:light_gray_glazed_terracotta"] = {175, 175, 175}, ["minecraft:cyan_glazed_terracotta"] = {90, 190, 190}, ["minecraft:purple_glazed_terracotta"] = {135, 70, 175}, ["minecraft:blue_glazed_terracotta"] = {75, 80, 175}, ["minecraft:brown_glazed_terracotta"] = {135, 95, 70}, ["minecraft:green_glazed_terracotta"] = {85, 135, 65}, ["minecraft:red_glazed_terracotta"] = {185, 60, 60}, ["minecraft:black_glazed_terracotta"] = {40, 40, 40}, ["minecraft:glass"] = {200, 220, 235}, ["minecraft:white_stained_glass"] = {215, 220, 225}, ["minecraft:orange_stained_glass"] = {225, 155, 95}, ["minecraft:magenta_stained_glass"] = {195, 120, 195}, ["minecraft:light_blue_stained_glass"] = {160, 200, 230}, ["minecraft:yellow_stained_glass"] = {230, 220, 130}, ["minecraft:lime_stained_glass"] = {145, 210, 130}, ["minecraft:pink_stained_glass"] = {230, 175, 190}, ["minecraft:gray_stained_glass"] = {130, 130, 135}, ["minecraft:light_gray_stained_glass"] = {185, 185, 190}, ["minecraft:cyan_stained_glass"] = {120, 200, 205}, ["minecraft:purple_stained_glass"] = {145, 100, 190}, ["minecraft:blue_stained_glass"] = {105, 115, 200}, ["minecraft:brown_stained_glass"] = {150, 115, 90}, ["minecraft:green_stained_glass"] = {110, 165, 100}, ["minecraft:red_stained_glass"] = {200, 85, 85}, ["minecraft:black_stained_glass"] = {55, 55, 60}, ["minecraft:glass_pane"] = {200, 220, 235}, ["minecraft:white_stained_glass_pane"] = {215, 220, 225}, ["minecraft:orange_stained_glass_pane"] = {225, 155, 95}, ["minecraft:magenta_stained_glass_pane"] = {195, 120, 195}, ["minecraft:light_blue_stained_glass_pane"] = {160, 200, 230}, ["minecraft:yellow_stained_glass_pane"] = {230, 220, 130}, ["minecraft:lime_stained_glass_pane"] = {145, 210, 130}, ["minecraft:pink_stained_glass_pane"] = {230, 175, 190}, ["minecraft:gray_stained_glass_pane"] = {130, 130, 135}, ["minecraft:light_gray_stained_glass_pane"] = {185, 185, 190}, ["minecraft:cyan_stained_glass_pane"] = {120, 200, 205}, ["minecraft:purple_stained_glass_pane"] = {145, 100, 190}, ["minecraft:blue_stained_glass_pane"] = {105, 115, 200}, ["minecraft:brown_stained_glass_pane"] = {150, 115, 90}, ["minecraft:green_stained_glass_pane"] = {110, 165, 100}, ["minecraft:red_stained_glass_pane"] = {200, 85, 85}, ["minecraft:black_stained_glass_pane"] = {55, 55, 60}, ["minecraft:prismarine"] = {80, 160, 150}, ["minecraft:prismarine_bricks"] = {70, 140, 135}, ["minecraft:dark_prismarine"] = {50, 95, 90}, ["minecraft:tube_coral_block"] = {130, 80, 150}, ["minecraft:brain_coral_block"] = {155, 100, 120}, ["minecraft:bubble_coral_block"] = {130, 150, 175}, ["minecraft:fire_coral_block"] = {200, 80, 55}, ["minecraft:horn_coral_block"] = {150, 130, 70}, ["minecraft:dead_tube_coral_block"] = {130, 125, 125}, ["minecraft:dead_brain_coral_block"] = {135, 125, 125}, ["minecraft:dead_bubble_coral_block"] = {130, 130, 130}, ["minecraft:dead_fire_coral_block"] = {135, 120, 115}, ["minecraft:dead_horn_coral_block"] = {130, 125, 115}, ["minecraft:netherrack"] = {100, 45, 45}, ["minecraft:nether_bricks"] = {60, 35, 40}, ["minecraft:red_nether_bricks"] = {100, 45, 35}, ["minecraft:cracked_nether_bricks"] = {60, 35, 40}, ["minecraft:chiseled_nether_bricks"] = {60, 35, 40}, ["minecraft:soul_sand"] = {80, 60, 45}, ["minecraft:soul_soil"] = {75, 60, 45}, ["minecraft:basalt"] = {70, 70, 80}, ["minecraft:polished_basalt"] = {75, 75, 85}, ["minecraft:blackstone"] = {40, 38, 42}, ["minecraft:polished_blackstone"] = {48, 45, 50}, ["minecraft:chiseled_polished_blackstone"] = {48, 45, 50}, ["minecraft:gilded_blackstone"] = {55, 50, 55}, ["minecraft:cracked_polished_blackstone_bricks"] = {48, 45, 50}, ["minecraft:polished_blackstone_bricks"] = {48, 45, 50}, ["minecraft:magma_block"] = {140, 60, 30}, ["minecraft:ancient_debris"] = {60, 55, 50}, ["minecraft:shroomlight"] = {215, 175, 75}, ["minecraft:crimson_nylium"] = {140, 40, 50}, ["minecraft:warped_nylium"] = {30, 110, 80}, ["minecraft:crimson_stem"] = {120, 35, 40}, ["minecraft:stripped_crimson_stem"] = {165, 110, 95}, ["minecraft:crimson_hyphae"] = {100, 30, 35}, ["minecraft:stripped_crimson_hyphae"] = {155, 100, 85}, ["minecraft:warped_stem"] = {40, 100, 75}, ["minecraft:stripped_warped_stem"] = {90, 145, 130}, ["minecraft:warped_hyphae"] = {35, 85, 65}, ["minecraft:stripped_warped_hyphae"] = {80, 135, 120}, ["minecraft:crimson_planks"] = {165, 75, 65}, ["minecraft:warped_planks"] = {60, 140, 115}, ["minecraft:crimson_slab"] = {165, 75, 65}, ["minecraft:warped_slab"] = {60, 140, 115}, ["minecraft:crimson_pressure_plate"] = {165, 75, 65}, ["minecraft:warped_pressure_plate"] = {60, 140, 115}, ["minecraft:crimson_fence"] = {165, 75, 65}, ["minecraft:warped_fence"] = {60, 140, 115}, ["minecraft:crimson_fence_gate"] = {165, 75, 65}, ["minecraft:warped_fence_gate"] = {60, 140, 115}, ["minecraft:crimson_door"] = {165, 75, 65}, ["minecraft:warped_door"] = {60, 140, 115}, ["minecraft:crimson_trapdoor"] = {165, 75, 65}, ["minecraft:warped_trapdoor"] = {60, 140, 115}, ["minecraft:crimson_sign"] = {165, 75, 65}, ["minecraft:warped_sign"] = {60, 140, 115}, ["minecraft:crimson_button"] = {165, 75, 65}, ["minecraft:warped_button"] = {60, 140, 115}, ["minecraft:nether_wart_block"] = {110, 30, 50}, ["minecraft:warped_wart_block"] = {25, 85, 70}, ["minecraft:lodestone"] = {60, 55, 50}, ["minecraft:respawn_anchor"] = {55, 50, 55}, ["minecraft:end_stone"] = {220, 215, 180}, ["minecraft:end_stone_bricks"] = {210, 205, 170}, ["minecraft:purpur_block"] = {150, 110, 170}, ["minecraft:purpur_pillar"] = {150, 110, 170}, ["minecraft:chiseled_purpur"] = {145, 105, 165}, ["minecraft:mycelium"] = {120, 150, 110}, ["minecraft:sculk_sensor"] = {20, 50, 60}, ["minecraft:sculk_catalyst"] = {30, 60, 70}, ["minecraft:sculk_shrieker"] = {25, 55, 65}, ["minecraft:sculk_vein"] = {20, 60, 60}, ["minecraft:calibrated_sculk_sensor"] = {20, 50, 60}, ["minecraft:ochre_froglight"] = {200, 160, 75}, ["minecraft:verdant_froglight"] = {130, 195, 90}, ["minecraft:pearlescent_froglight"] = {195, 150, 200}, ["minecraft:bamboo_block"] = {160, 140, 80}, ["minecraft:stripped_bamboo_block"] = {195, 170, 110}, ["minecraft:bamboo_mosaic_slab"] = {185, 160, 100}, ["minecraft:bamboo_mosaic_stairs"] = {185, 160, 100}, ["minecraft:sponge"] = {200, 180, 130}, ["minecraft:wet_sponge"] = {100, 120, 140}, ["minecraft:ice"] = {160, 210, 230}, ["minecraft:packed_ice"] = {150, 200, 220}, ["minecraft:blue_ice"] = {120, 160, 200}, ["minecraft:frosted_ice"] = {160, 210, 230}, ["minecraft:snow_block"] = {240, 240, 245}, ["minecraft:clay"] = {165, 165, 160}, ["minecraft:bone_block"] = {220, 215, 195}, ["minecraft:honeycomb_block"] = {225, 185, 70}, ["minecraft:slime_block"] = {120, 200, 90}, ["minecraft:hay_block"] = {210, 190, 80}, ["minecraft:melon"] = {140, 175, 60}, ["minecraft:pumpkin"] = {200, 130, 50}, ["minecraft:carved_pumpkin"] = {200, 130, 50}, ["minecraft:jack_o_lantern"] = {200, 130, 50}, ["minecraft:jukebox"] = {130, 95, 65}, ["minecraft:bookshelf"] = {150, 125, 85}, ["minecraft:chiseled_bookshelf"] = {145, 120, 80}, ["minecraft:enchanting_table"] = {130, 110, 145}, ["minecraft:brewing_stand"] = {180, 150, 120}, ["minecraft:cauldron"] = {50, 50, 50}, ["minecraft:water_cauldron"] = {50, 50, 50}, ["minecraft:lava_cauldron"] = {50, 50, 50}, ["minecraft:powder_snow_cauldron"] = {50, 50, 50}, ["minecraft:end_portal_frame"] = {50, 50, 55}, ["minecraft:spawner"] = {40, 40, 45}, ["minecraft:furnace"] = {130, 130, 130}, ["minecraft:blast_furnace"] = {110, 100, 100}, ["minecraft:smoker"] = {110, 110, 105}, ["minecraft:crafting_table"] = {155, 125, 85}, ["minecraft:anvil"] = {60, 60, 65}, ["minecraft:chipped_anvil"] = {60, 60, 65}, ["minecraft:damaged_anvil"] = {60, 60, 65}, ["minecraft:grindstone"] = {140, 130, 120}, ["minecraft:stonecutter"] = {135, 135, 135}, ["minecraft:smithing_table"] = {130, 100, 70}, ["minecraft:loom"] = {155, 125, 85}, ["minecraft:fletching_table"] = {155, 125, 85}, ["minecraft:cartography_table"] = {155, 125, 85}, ["minecraft:composter"] = {140, 120, 85}, ["minecraft:barrel"] = {145, 115, 80}, ["minecraft:chest"] = {150, 120, 80}, ["minecraft:trapped_chest"] = {150, 120, 80}, ["minecraft:ender_chest"] = {30, 30, 40}, ["minecraft:shulker_box"] = {140, 110, 150}, ["minecraft:white_shulker_box"] = {220, 220, 220}, ["minecraft:orange_shulker_box"] = {215, 125, 45}, ["minecraft:magenta_shulker_box"] = {170, 70, 170}, ["minecraft:light_blue_shulker_box"] = {130, 180, 215}, ["minecraft:yellow_shulker_box"] = {225, 205, 70}, ["minecraft:lime_shulker_box"] = {110, 180, 70}, ["minecraft:pink_shulker_box"] = {215, 145, 160}, ["minecraft:gray_shulker_box"] = {95, 95, 95}, ["minecraft:light_gray_shulker_box"] = {155, 155, 155}, ["minecraft:cyan_shulker_box"] = {70, 170, 170}, ["minecraft:purple_shulker_box"] = {115, 55, 155}, ["minecraft:blue_shulker_box"] = {55, 60, 155}, ["minecraft:brown_shulker_box"] = {115, 80, 55}, ["minecraft:green_shulker_box"] = {70, 115, 50}, ["minecraft:red_shulker_box"] = {165, 45, 45}, ["minecraft:black_shulker_box"] = {25, 25, 25}, ["minecraft:bedrock"] = {85, 85, 85}, ["minecraft:barrier"] = {220, 220, 220}, ["minecraft:command_block"] = {140, 80, 60}, ["minecraft:repeating_command_block"] = {60, 90, 140}, ["minecraft:chain_command_block"] = {50, 130, 70}, ["minecraft:structure_block"] = {100, 140, 180}, ["minecraft:jigsaw"] = {90, 130, 170}, ["minecraft:light"] = {255, 255, 255}, ["minecraft:structure_void"] = {50, 50, 50}, ["minecraft:end_gateway"] = {50, 50, 55}, ["minecraft:end_portal"] = {30, 30, 40}, ["minecraft:portal"] = {80, 30, 120}, ["minecraft:dragon_egg"] = {25, 20, 30}, ["minecraft:infested_stone"] = {125, 125, 125}, ["minecraft:infested_deepslate"] = {68, 68, 73}, ["minecraft:infested_cobblestone"] = {122, 122, 122}, ["minecraft:infested_stone_bricks"] = {135, 135, 130}, ["minecraft:infested_mossy_stone_bricks"] = {115, 135, 105}, ["minecraft:infested_cracked_stone_bricks"] = {135, 135, 130}, ["minecraft:infested_chiseled_stone_bricks"] = {135, 135, 130}, ["minecraft:stone_bricks"] = {135, 135, 130}, ["minecraft:mossy_stone_bricks"] = {115, 135, 105}, ["minecraft:cracked_stone_bricks"] = {135, 135, 130}, ["minecraft:chiseled_stone_bricks"] = {135, 135, 130}, ["minecraft:mossy_cobblestone"] = {115, 135, 105}, ["minecraft:infested_mud_bricks"] = {100, 80, 60}, ["minecraft:dandelion"] = {250, 220, 50}, ["minecraft:poppy"] = {200, 40, 40}, ["minecraft:blue_orchid"] = {50, 70, 180}, ["minecraft:allium"] = {170, 70, 170}, ["minecraft:azure_bluet"] = {220, 220, 230}, ["minecraft:red_tulip"] = {200, 50, 50}, ["minecraft:orange_tulip"] = {220, 130, 40}, ["minecraft:white_tulip"] = {230, 230, 235}, ["minecraft:pink_tulip"] = {230, 150, 170}, ["minecraft:oxeye_daisy"] = {230, 235, 210}, ["minecraft:cornflower"] = {60, 80, 200}, ["minecraft:lily_of_the_valley"] = {225, 230, 225}, ["minecraft:sunflower"] = {250, 210, 50}, ["minecraft:lilac"] = {170, 100, 180}, ["minecraft:peony"] = {210, 120, 150}, ["minecraft:rose_bush"] = {190, 45, 45}, ["minecraft:wither_rose"] = {40, 20, 40}, ["minecraft:dead_bush"] = {140, 120, 80}, ["minecraft:sugar_cane"] = {110, 150, 60}, ["minecraft:bamboo"] = {100, 145, 60}, ["minecraft:oak_sapling"] = {75, 135, 50}, ["minecraft:spruce_sapling"] = {50, 85, 40}, ["minecraft:birch_sapling"] = {85, 155, 65}, ["minecraft:jungle_sapling"] = {55, 115, 30}, ["minecraft:acacia_sapling"] = {85, 130, 40}, ["minecraft:dark_oak_sapling"] = {55, 85, 35}, ["minecraft:mangrove_propagule"] = {65, 110, 50}, ["minecraft:cherry_sapling"] = {210, 140, 170}, ["minecraft:spore_blossom"] = {140, 80, 160}, ["minecraft:flowering_azalea"] = {180, 100, 160}, ["minecraft:azalea"] = {45, 130, 55}, ["minecraft:water"] = {40, 80, 180}, ["minecraft:lava"] = {210, 100, 20}, ["minecraft:powder_snow"] = {230, 240, 250}, ["minecraft:fire"] = {230, 150, 50}, ["minecraft:soul_fire"] = {60, 120, 200}, ["minecraft:redstone_wire"] = {180, 30, 30}, ["minecraft:redstone_torch"] = {180, 50, 40}, ["minecraft:repeater"] = {130, 130, 130}, ["minecraft:comparator"] = {130, 130, 130}, ["minecraft:observer"] = {130, 130, 130}, ["minecraft:piston"] = {130, 130, 130}, ["minecraft:sticky_piston"] = {130, 130, 130}, ["minecraft:dispenser"] = {130, 130, 130}, ["minecraft:dropper"] = {130, 130, 130}, ["minecraft:note_block"] = {130, 95, 65}, ["minecraft:target"] = {210, 175, 155}, ["minecraft:lever"] = {100, 100, 100}, ["minecraft:button"] = {130, 130, 130}, ["minecraft:stone_button"] = {130, 130, 130}, ["minecraft:oak_button"] = {168, 132, 88}, ["minecraft:spruce_button"] = {120, 90, 60}, ["minecraft:birch_button"] = {205, 185, 145}, ["minecraft:jungle_button"] = {155, 120, 65}, ["minecraft:acacia_button"] = {175, 125, 70}, ["minecraft:dark_oak_button"] = {100, 75, 50}, ["minecraft:mangrove_button"] = {140, 100, 65}, ["minecraft:bamboo_button"] = {195, 170, 110}, ["minecraft:polished_blackstone_button"] = {48, 45, 50}, ["minecraft:pressure_plate"] = {130, 130, 130}, ["minecraft:stone_pressure_plate"] = {130, 130, 130}, ["minecraft:oak_pressure_plate"] = {168, 132, 88}, ["minecraft:spruce_pressure_plate"] = {120, 90, 60}, ["minecraft:birch_pressure_plate"] = {205, 185, 145}, ["minecraft:jungle_pressure_plate"] = {155, 120, 65}, ["minecraft:acacia_pressure_plate"] = {175, 125, 70}, ["minecraft:dark_oak_pressure_plate"] = {100, 75, 50}, ["minecraft:mangrove_pressure_plate"] = {140, 100, 65}, ["minecraft:bamboo_pressure_plate"] = {195, 170, 110}, ["minecraft:polished_blackstone_pressure_plate"] = {48, 45, 50}, ["minecraft:heavy_weighted_pressure_plate"] = {130, 130, 130}, ["minecraft:light_weighted_pressure_plate"] = {200, 180, 50}, ["minecraft:door"] = {130, 130, 130}, ["minecraft:iron_door"] = {160, 160, 160}, ["minecraft:oak_door"] = {168, 132, 88}, ["minecraft:spruce_door"] = {120, 90, 60}, ["minecraft:birch_door"] = {205, 185, 145}, ["minecraft:jungle_door"] = {155, 120, 65}, ["minecraft:acacia_door"] = {175, 125, 70}, ["minecraft:dark_oak_door"] = {100, 75, 50}, ["minecraft:mangrove_door"] = {140, 100, 65}, ["minecraft:bamboo_door"] = {195, 170, 110}, ["minecraft:trapdoor"] = {130, 130, 130}, ["minecraft:iron_trapdoor"] = {160, 160, 160}, ["minecraft:oak_trapdoor"] = {168, 132, 88}, ["minecraft:spruce_trapdoor"] = {120, 90, 60}, ["minecraft:birch_trapdoor"] = {205, 185, 145}, ["minecraft:jungle_trapdoor"] = {155, 120, 65}, ["minecraft:acacia_trapdoor"] = {175, 125, 70}, ["minecraft:dark_oak_trapdoor"] = {100, 75, 50}, ["minecraft:mangrove_trapdoor"] = {140, 100, 65}, ["minecraft:bamboo_trapdoor"] = {195, 170, 110}, ["minecraft:fence"] = {130, 130, 130}, ["minecraft:oak_fence"] = {168, 132, 88}, ["minecraft:spruce_fence"] = {120, 90, 60}, ["minecraft:birch_fence"] = {205, 185, 145}, ["minecraft:jungle_fence"] = {155, 120, 65}, ["minecraft:acacia_fence"] = {175, 125, 70}, ["minecraft:dark_oak_fence"] = {100, 75, 50}, ["minecraft:mangrove_fence"] = {140, 100, 65}, ["minecraft:bamboo_fence"] = {195, 170, 110}, ["minecraft:nether_brick_fence"] = {60, 35, 40}, ["minecraft:fence_gate"] = {130, 130, 130}, ["minecraft:oak_fence_gate"] = {168, 132, 88}, ["minecraft:spruce_fence_gate"] = {120, 90, 60}, ["minecraft:birch_fence_gate"] = {205, 185, 145}, ["minecraft:jungle_fence_gate"] = {155, 120, 65}, ["minecraft:acacia_fence_gate"] = {175, 125, 70}, ["minecraft:dark_oak_fence_gate"] = {100, 75, 50}, ["minecraft:mangrove_fence_gate"] = {140, 100, 65}, ["minecraft:bamboo_fence_gate"] = {195, 170, 110}, ["minecraft:wall_torch"] = {220, 180, 100}, ["minecraft:soul_wall_torch"] = {80, 130, 200}, ["minecraft:redstone_wall_torch"] = {180, 50, 40}, ["minecraft:sign"] = {130, 130, 130}, ["minecraft:oak_sign"] = {168, 132, 88}, ["minecraft:spruce_sign"] = {120, 90, 60}, ["minecraft:birch_sign"] = {205, 185, 145}, ["minecraft:jungle_sign"] = {155, 120, 65}, ["minecraft:acacia_sign"] = {175, 125, 70}, ["minecraft:dark_oak_sign"] = {100, 75, 50}, ["minecraft:mangrove_sign"] = {140, 100, 65}, ["minecraft:bamboo_sign"] = {195, 170, 110}, ["minecraft:wall_sign"] = {130, 130, 130}, ["minecraft:oak_wall_sign"] = {168, 132, 88}, ["minecraft:spruce_wall_sign"] = {120, 90, 60}, ["minecraft:birch_wall_sign"] = {205, 185, 145}, ["minecraft:jungle_wall_sign"] = {155, 120, 65}, ["minecraft:acacia_wall_sign"] = {175, 125, 70}, ["minecraft:dark_oak_wall_sign"] = {100, 75, 50}, ["minecraft:mangrove_wall_sign"] = {140, 100, 65}, ["minecraft:bamboo_wall_sign"] = {195, 170, 110}, ["minecraft:hanging_sign"] = {130, 130, 130}, ["minecraft:oak_hanging_sign"] = {168, 132, 88}, ["minecraft:spruce_hanging_sign"] = {120, 90, 60}, ["minecraft:birch_hanging_sign"] = {205, 185, 145}, ["minecraft:jungle_hanging_sign"] = {155, 120, 65}, ["minecraft:acacia_hanging_sign"] = {175, 125, 70}, ["minecraft:dark_oak_hanging_sign"] = {100, 75, 50}, ["minecraft:mangrove_hanging_sign"] = {140, 100, 65}, ["minecraft:bamboo_hanging_sign"] = {195, 170, 110}, ["minecraft:ladder"] = {160, 130, 85}, ["minecraft:scaffolding"] = {180, 170, 130}, ["minecraft:chain"] = {90, 90, 95}, ["minecraft:candle"] = {220, 210, 180}, ["minecraft:white_candle"] = {220, 220, 220}, ["minecraft:orange_candle"] = {220, 140, 60}, ["minecraft:magenta_candle"] = {180, 80, 180}, ["minecraft:light_blue_candle"] = {140, 190, 220}, ["minecraft:yellow_candle"] = {230, 215, 80}, ["minecraft:lime_candle"] = {120, 190, 80}, ["minecraft:pink_candle"] = {225, 155, 170}, ["minecraft:gray_candle"] = {110, 110, 110}, ["minecraft:light_gray_candle"] = {170, 170, 170}, ["minecraft:cyan_candle"] = {80, 180, 180}, ["minecraft:purple_candle"] = {130, 70, 170}, ["minecraft:blue_candle"] = {70, 75, 170}, ["minecraft:brown_candle"] = {130, 95, 70}, ["minecraft:green_candle"] = {80, 130, 60}, ["minecraft:red_candle"] = {180, 55, 55}, ["minecraft:black_candle"] = {40, 40, 40}, ["minecraft:rails"] = {130, 130, 130}, ["minecraft:powered_rail"] = {130, 130, 130}, ["minecraft:detector_rail"] = {130, 130, 130}, ["minecraft:activator_rail"] = {130, 130, 130}, ["minecraft:lime_candle_cake"] = {230, 215, 80}, ["minecraft:oak_slab"] = {168, 132, 88}, ["minecraft:spruce_slab"] = {120, 90, 60}, ["minecraft:birch_slab"] = {205, 185, 145}, ["minecraft:jungle_slab"] = {155, 120, 65}, ["minecraft:acacia_slab"] = {175, 125, 70}, ["minecraft:dark_oak_slab"] = {100, 75, 50}, ["minecraft:mangrove_slab"] = {140, 100, 65}, ["minecraft:bamboo_slab"] = {195, 170, 110}, ["minecraft:stone_slab"] = {125, 125, 125}, ["minecraft:smooth_stone_slab"] = {175, 175, 175}, ["minecraft:stone_brick_slab"] = {135, 135, 130}, ["minecraft:sandstone_slab"] = {215, 205, 155}, ["minecraft:purpur_slab"] = {150, 110, 170}, ["minecraft:quartz_slab"] = {230, 230, 225}, ["minecraft:red_sandstone_slab"] = {185, 110, 55}, ["minecraft:prismarine_slab"] = {80, 160, 150}, ["minecraft:prismarine_brick_slab"] = {70, 140, 135}, ["minecraft:dark_prismarine_slab"] = {50, 95, 90}, ["minecraft:granite_slab"] = {132, 98, 78}, ["minecraft:polished_granite_slab"] = {140, 104, 82}, ["minecraft:diorite_slab"] = {173, 173, 173}, ["minecraft:polished_diorite_slab"] = {180, 180, 180}, ["minecraft:andesite_slab"] = {126, 126, 131}, ["minecraft:polished_andesite_slab"] = {135, 135, 140}, ["minecraft:cobblestone_slab"] = {122, 122, 122}, ["minecraft:brick_slab"] = {150, 100, 80}, ["minecraft:mud_brick_slab"] = {100, 80, 60}, ["minecraft:cut_copper_slab"] = {185, 120, 70}, ["minecraft:exposed_cut_copper_slab"] = {170, 130, 100}, ["minecraft:weathered_cut_copper_slab"] = {110, 110, 105}, ["minecraft:oxidized_cut_copper_slab"] = {75, 110, 105}, ["minecraft:waxed_cut_copper_slab"] = {185, 120, 70}, ["minecraft:waxed_exposed_cut_copper_slab"] = {170, 130, 100}, ["minecraft:waxed_weathered_cut_copper_slab"] = {110, 110, 105}, ["minecraft:waxed_oxidized_cut_copper_slab"] = {75, 110, 105}, ["minecraft:tuff_slab"] = {100, 100, 95}, ["minecraft:polished_tuff_slab"] = {110, 110, 105}, ["minecraft:tuff_brick_slab"] = {105, 105, 100}, ["minecraft:polished_tuff_double_slab"] = {110, 110, 105}, ["minecraft:oak_stairs"] = {168, 132, 88}, ["minecraft:spruce_stairs"] = {120, 90, 60}, ["minecraft:birch_stairs"] = {205, 185, 145}, ["minecraft:jungle_stairs"] = {155, 120, 65}, ["minecraft:acacia_stairs"] = {175, 125, 70}, ["minecraft:dark_oak_stairs"] = {100, 75, 50}, ["minecraft:mangrove_stairs"] = {140, 100, 65}, ["minecraft:bamboo_stairs"] = {195, 170, 110}, ["minecraft:stone_stairs"] = {125, 125, 125}, ["minecraft:smooth_stone_stairs"] = {175, 175, 175}, ["minecraft:stone_brick_stairs"] = {135, 135, 130}, ["minecraft:sandstone_stairs"] = {215, 205, 155}, ["minecraft:purpur_stairs"] = {150, 110, 170}, ["minecraft:quartz_stairs"] = {230, 230, 225}, ["minecraft:red_sandstone_stairs"] = {185, 110, 55}, ["minecraft:prismarine_stairs"] = {80, 160, 150}, ["minecraft:prismarine_brick_stairs"] = {70, 140, 135}, ["minecraft:dark_prismarine_stairs"] = {50, 95, 90}, ["minecraft:granite_stairs"] = {132, 98, 78}, ["minecraft:polished_granite_stairs"] = {140, 104, 82}, ["minecraft:diorite_stairs"] = {173, 173, 173}, ["minecraft:polished_diorite_stairs"] = {180, 180, 180}, ["minecraft:andesite_stairs"] = {126, 126, 131}, ["minecraft:polished_andesite_stairs"] = {135, 135, 140}, ["minecraft:cobblestone_stairs"] = {122, 122, 122}, ["minecraft:brick_stairs"] = {150, 100, 80}, ["minecraft:mud_brick_stairs"] = {100, 80, 60}, ["minecraft:cut_copper_stairs"] = {185, 120, 70}, ["minecraft:exposed_cut_copper_stairs"] = {170, 130, 100}, ["minecraft:weathered_cut_copper_stairs"] = {110, 110, 105}, ["minecraft:oxidized_cut_copper_stairs"] = {75, 110, 105}, ["minecraft:waxed_cut_copper_stairs"] = {185, 120, 70}, ["minecraft:waxed_exposed_cut_copper_stairs"] = {170, 130, 100}, ["minecraft:waxed_weathered_cut_copper_stairs"] = {110, 110, 105}, ["minecraft:waxed_oxidized_cut_copper_stairs"] = {75, 110, 105}, ["minecraft:tuff_stairs"] = {100, 100, 95}, ["minecraft:polished_tuff_stairs"] = {110, 110, 105}, ["minecraft:tuff_brick_stairs"] = {105, 105, 100}, ["minecraft:wall"] = {125, 125, 125}, ["minecraft:cobblestone_wall"] = {122, 122, 122}, ["minecraft:mossy_cobblestone_wall"] = {115, 135, 105}, ["minecraft:stone_brick_wall"] = {135, 135, 130}, ["minecraft:mossy_stone_brick_wall"] = {115, 135, 105}, ["minecraft:granite_wall"] = {132, 98, 78}, ["minecraft:polished_granite_wall"] = {140, 104, 82}, ["minecraft:diorite_wall"] = {173, 173, 173}, ["minecraft:polished_diorite_wall"] = {180, 180, 180}, ["minecraft:andesite_wall"] = {126, 126, 131}, ["minecraft:polished_andesite_wall"] = {135, 135, 140}, ["minecraft:sandstone_wall"] = {215, 205, 155}, ["minecraft:red_sandstone_wall"] = {185, 110, 55}, ["minecraft:brick_wall"] = {150, 100, 80}, ["minecraft:prismarine_wall"] = {80, 160, 150}, ["minecraft:red_nether_brick_wall"] = {100, 45, 35}, ["minecraft:nether_brick_wall"] = {60, 35, 40}, ["minecraft:end_stone_brick_wall"] = {210, 205, 170}, ["minecraft:mud_brick_wall"] = {100, 80, 60}, ["minecraft:blackstone_wall"] = {40, 38, 42}, ["minecraft:polished_blackstone_wall"] = {48, 45, 50}, ["minecraft:polished_blackstone_brick_wall"] = {48, 45, 50}, ["minecraft:cobbled_deepslate_wall"] = {75, 75, 80}, ["minecraft:polished_deepslate_wall"] = {82, 82, 87}, ["minecraft:deepslate_brick_wall"] = {72, 72, 77}, ["minecraft:deepslate_tile_wall"] = {78, 78, 83}, ["minecraft:tuff_wall"] = {100, 100, 95}, ["minecraft:polished_tuff_wall"] = {110, 110, 105}, ["minecraft:tuff_brick_wall"] = {105, 105, 100}, ["minecraft:quartz_block"] = {230, 230, 225}, ["minecraft:chiseled_quartz_block"] = {230, 230, 225}, ["minecraft:quartz_pillar"] = {230, 230, 225}, ["minecraft:quartz_bricks"] = {230, 230, 225}, ["minecraft:smooth_quartz"] = {235, 235, 230}, ["minecraft:bricks"] = {150, 100, 80}, ["minecraft:chiseled_bricks"] = {150, 100, 80}, ["minecraft:deepslate_bricks"] = {72, 72, 77}, ["minecraft:cracked_deepslate_bricks"] = {72, 72, 77}, ["minecraft:deepslate_tiles"] = {78, 78, 83}, ["minecraft:cracked_deepslate_tiles"] = {78, 78, 83}, ["minecraft:chiseled_deepslate"] = {68, 68, 73}, ["minecraft:reinforced_deepslate"] = {50, 50, 55}, ["minecraft:polished_tuff"] = {110, 110, 105}, ["minecraft:chiseled_tuff"] = {110, 110, 105}, ["minecraft:tuff_bricks"] = {105, 105, 100}, ["minecraft:potted_dandelion"] = {130, 130, 130}, ["minecraft:potted_poppy"] = {130, 130, 130}, ["minecraft:potted_blue_orchid"] = {130, 130, 130}, ["minecraft:potted_allium"] = {130, 130, 130}, ["minecraft:potted_azure_bluet"] = {130, 130, 130}, ["minecraft:potted_red_tulip"] = {130, 130, 130}, ["minecraft:potted_orange_tulip"] = {130, 130, 130}, ["minecraft:potted_white_tulip"] = {130, 130, 130}, ["minecraft:potted_pink_tulip"] = {130, 130, 130}, ["minecraft:potted_oxeye_daisy"] = {130, 130, 130}, ["minecraft:potted_cornflower"] = {130, 130, 130}, ["minecraft:potted_lily_of_the_valley"] = {130, 130, 130}, ["minecraft:potted_wither_rose"] = {130, 130, 130}, ["minecraft:potted_oak_sapling"] = {130, 130, 130}, ["minecraft:potted_spruce_sapling"] = {130, 130, 130}, ["minecraft:potted_birch_sapling"] = {130, 130, 130}, ["minecraft:potted_jungle_sapling"] = {130, 130, 130}, ["minecraft:potted_acacia_sapling"] = {130, 130, 130}, ["minecraft:potted_dark_oak_sapling"] = {130, 130, 130}, ["minecraft:potted_mangrove_propagule"] = {130, 130, 130}, ["minecraft:potted_cherry_sapling"] = {130, 130, 130}, ["minecraft:potted_fern"] = {130, 130, 130}, ["minecraft:potted_dead_bush"] = {130, 130, 130}, ["minecraft:potted_cactus"] = {130, 130, 130}, ["minecraft:potted_bamboo"] = {130, 130, 130}, ["minecraft:potted_azalea"] = {130, 130, 130}, ["minecraft:potted_flowering_azalea"] = {130, 130, 130}, ["minecraft:potted_torchflower"] = {130, 130, 130}, ["minecraft:torchflower"] = {230, 210, 70}, ["minecraft:torchflower_crop"] = {60, 120, 40}, ["minecraft:potatoes"] = {60, 120, 40}, ["minecraft:carrots"] = {60, 120, 40}, ["minecraft:wheat"] = {140, 160, 50}, ["minecraft:beetroots"] = {60, 120, 40}, ["minecraft:melon_stem"] = {60, 120, 40}, ["minecraft:pumpkin_stem"] = {60, 120, 40}, ["minecraft:sweet_berry_bush"] = {60, 120, 40}, ["minecraft:cocoa"] = {140, 100, 50}, ["minecraft:kelp"] = {40, 100, 40}, ["minecraft:kelp_plant"] = {40, 100, 40}, ["minecraft:seagrass"] = {50, 130, 60}, ["minecraft:tall_seagrass"] = {50, 130, 60}, ["minecraft:fern"] = {50, 140, 50}, ["minecraft:large_fern"] = {50, 140, 50}, ["minecraft:vine"] = {50, 110, 40}, ["minecraft:lily_pad"] = {40, 120, 50}, ["minecraft:nether_sprouts"] = {50, 80, 60}, ["minecraft:crimson_fungus"] = {160, 40, 50}, ["minecraft:warped_fungus"] = {30, 110, 80}, ["minecraft:crimson_roots"] = {140, 40, 50}, ["minecraft:warped_roots"] = {30, 100, 75}, ["minecraft:weeping_vines"] = {100, 50, 60}, ["minecraft:weeping_vines_plant"] = {100, 50, 60}, ["minecraft:twisting_vines"] = {40, 120, 80}, ["minecraft:twisting_vines_plant"] = {40, 120, 80}, ["minecraft:dead_tube_coral"] = {130, 125, 125}, ["minecraft:dead_brain_coral"] = {135, 125, 125}, ["minecraft:dead_bubble_coral"] = {130, 130, 130}, ["minecraft:dead_fire_coral"] = {135, 120, 115}, ["minecraft:dead_horn_coral"] = {130, 125, 115}, ["minecraft:tube_coral"] = {130, 80, 150}, ["minecraft:brain_coral"] = {155, 100, 120}, ["minecraft:bubble_coral"] = {130, 150, 175}, ["minecraft:fire_coral"] = {200, 80, 55}, ["minecraft:horn_coral"] = {150, 130, 70}, ["minecraft:tube_coral_fan"] = {130, 80, 150}, ["minecraft:brain_coral_fan"] = {155, 100, 120}, ["minecraft:bubble_coral_fan"] = {130, 150, 175}, ["minecraft:fire_coral_fan"] = {200, 80, 55}, ["minecraft:horn_coral_fan"] = {150, 130, 70}, ["minecraft:dead_tube_coral_fan"] = {130, 125, 125}, ["minecraft:dead_brain_coral_fan"] = {135, 125, 125}, ["minecraft:dead_bubble_coral_fan"] = {130, 130, 130}, ["minecraft:dead_fire_coral_fan"] = {135, 120, 115}, ["minecraft:dead_horn_coral_fan"] = {130, 125, 115}, ["minecraft:cobweb"] = {200, 200, 200}, ["minecraft:snow"] = {240, 240, 245}, ["minecraft:tall_grass"] = {90, 150, 50}, ["minecraft:head"] = {130, 110, 90}, ["minecraft:skull"] = {130, 120, 110}, ["minecraft:player_head"] = {130, 110, 90}, ["minecraft:zombie_head"] = {100, 130, 90}, ["minecraft:creeper_head"] = {90, 140, 80}, ["minecraft:skeleton_skull"] = {160, 160, 150}, ["minecraft:wither_skeleton_skull"] = {50, 50, 55}, ["minecraft:piglin_head"] = {160, 120, 100}, ["minecraft:dragon_head"] = {80, 80, 90}, ["minecraft:bell"] = {180, 170, 140}, ["minecraft:lectern"] = {155, 125, 85}, ["minecraft:armorer_stand"] = {130, 130, 130}, ["minecraft:weaponsmith_stand"] = {130, 130, 130}, ["minecraft:toolsmith_stand"] = {130, 130, 130}, ["minecraft:butcher_stand"] = {130, 130, 130}, ["minecraft:leatherworker_stand"] = {130, 130, 130}, ["minecraft:decorated_pot"] = {180, 150, 100}, ["minecraft:suspicious_sand"] = {215, 200, 150}, ["minecraft:suspicious_gravel"] = {130, 120, 115}, ["minecraft:cake"] = {230, 210, 160}, ["minecraft:candle_cake"] = {230, 210, 160}, ["minecraft:white_candle_cake"] = {230, 210, 160}, ["minecraft:orange_candle_cake"] = {230, 210, 160}, ["minecraft:magenta_candle_cake"] = {230, 210, 160}, ["minecraft:light_blue_candle_cake"] = {230, 210, 160}, ["minecraft:yellow_candle_cake"] = {230, 210, 160}, ["minecraft:pink_candle_cake"] = {230, 210, 160}, ["minecraft:gray_candle_cake"] = {230, 210, 160}, ["minecraft:light_gray_candle_cake"] = {230, 210, 160}, ["minecraft:cyan_candle_cake"] = {230, 210, 160}, ["minecraft:purple_candle_cake"] = {230, 210, 160}, ["minecraft:blue_candle_cake"] = {230, 210, 160}, ["minecraft:brown_candle_cake"] = {230, 210, 160}, ["minecraft:green_candle_cake"] = {230, 210, 160}, ["minecraft:red_candle_cake"] = {230, 210, 160}, ["minecraft:black_candle_cake"] = {230, 210, 160}, ["minecraft:monster_egg"] = {125, 125, 125}, ["minecraft:stone_monster_egg"] = {125, 125, 125}, ["minecraft:cobblestone_monster_egg"] = {122, 122, 122}, ["minecraft:stone_brick_monster_egg"] = {135, 135, 130}, ["minecraft:mossy_stone_brick_monster_egg"] = {115, 135, 105}, ["minecraft:cracked_stone_brick_monster_egg"] = {135, 135, 130}, ["minecraft:chiseled_stone_brick_monster_egg"] = {135, 135, 130}, ["minecraft:deepslate_monster_egg"] = {68, 68, 73}
}

-- Interned RGBA tables let adjacent pixels compare colors by identity and let
-- every cached voxel reference one shared, pre-shaded palette entry.
local internedColors = {}
local colorIds = {}
local nextColorId = 0

local function internColor(r, g, b, a)
    local key = ((r * 256 + g) * 256 + b) * 256 + a
    local color = internedColors[key]
    if not color then
        color = {r, g, b, a}
        internedColors[key] = color
        nextColorId = nextColorId + 1
        colorIds[color] = nextColorId
    end
    return color
end

local function makeShades(rgb)
    local r, g, b = rgb[1], rgb[2], rgb[3]
    return {
        internColor(m_floor(r * 0.8), m_floor(g * 0.8), m_floor(b * 0.8), 255),
        internColor(m_floor(r * 0.9), m_floor(g * 0.9), m_floor(b * 0.9), 255),
        internColor(m_floor(r * 0.6), m_floor(g * 0.6), m_floor(b * 0.6), 255)
    }
end

for blockName, rgb in pairs(blockColors) do
    blockColors[blockName] = makeShades(rgb)
end

local SKY_COLOR = internColor(135, 206, 235, 255)
local PLAYER_COLOR = internColor(255, 30, 30, 255)
local UNKNOWN_COLOR = internColor(150, 50, 200, 255)
local UNKNOWN_SHADES = {UNKNOWN_COLOR, UNKNOWN_COLOR, UNKNOWN_COLOR}

-- Two one-dimensional ray axes replace 8,192 nested direction tables.
local fovY = 0.8
local rayU, rayV = {}, {}

local function updateRayAxes()
    local fovX = fovY * (W / H)
    for px = 1, W do
        rayU[px] = (((px - 0.5) / W) * 2 - 1) * fovX
    end
    for py = 1, H do
        rayV[py] = (1 - ((py - 0.5) / H) * 2) * fovY
    end
    raycastDirty = true
end

local function rebuildDrawRuns()
    local runCount = 0
    local active, nextActive = activeRunsA, activeRunsB

    for key in pairs(active) do active[key] = nil end
    for key in pairs(nextActive) do nextActive[key] = nil end

    for py = 1, H do
        for key in pairs(nextActive) do nextActive[key] = nil end
        local rowStart = (py - 1) * W
        local startX = 0
        local color = pixelColors[rowStart + 1]

        for px = 2, W do
            local nextColor = pixelColors[rowStart + px]
            if nextColor ~= color then
                local endX = px - 1
                local key = (colorIds[color] * (W + 1) + startX) * (W + 1) + endX
                local run = active[key]
                if run then
                    run.p2[2] = py * TILE_H
                else
                    runCount = runCount + 1
                    run = drawRuns[runCount]
                    if not run then
                        run = {p1 = {0, 0}, p2 = {0, 0}, color = color}
                        drawRuns[runCount] = run
                    end
                    run.p1[1], run.p1[2] = startX * TILE_W, (py - 1) * TILE_H
                    run.p2[1], run.p2[2] = endX * TILE_W, py * TILE_H
                    run.color = color
                end
                nextActive[key] = run
                startX = px - 1
                color = nextColor
            end
        end

        local endX = W
        local key = (colorIds[color] * (W + 1) + startX) * (W + 1) + endX
        local run = active[key]
        if run then
            run.p2[2] = py * TILE_H
        else
            runCount = runCount + 1
            run = drawRuns[runCount]
            if not run then
                run = {p1 = {0, 0}, p2 = {0, 0}, color = color}
                drawRuns[runCount] = run
            end
            run.p1[1], run.p1[2] = startX * TILE_W, (py - 1) * TILE_H
            run.p2[1], run.p2[2] = endX * TILE_W, py * TILE_H
            run.color = color
        end
        nextActive[key] = run
        active, nextActive = nextActive, active
    end

    drawRunCount = runCount
end

for i = 1, W * H do
    pixelColors[i] = SKY_COLOR
end
updateRayAxes()
rebuildDrawRuns()

-- ==========================================
-- 5. SCANNING
-- ==========================================

local function resetCache(showNotification)
    RADIUS = m_floor(tonumber(RadiusSlider.value) or RADIUS)
    BLOCKS_PER_SECOND = m_floor(tonumber(BlockPerSecondSlider.value) or BLOCKS_PER_SECOND)

    centerX, centerY, centerZ = m_floor(camX), m_floor(camY), m_floor(camZ)
    worldMinX, worldMaxX = centerX - RADIUS, centerX + RADIUS
    worldMinY, worldMaxY = centerY - RADIUS, centerY + RADIUS
    worldMinZ, worldMaxZ = centerZ - RADIUS, centerZ + RADIUS

    SIDE = RADIUS * 2 + 1
    PLANE = SIDE * SIDE
    TOTAL_BLOCKS = PLANE * SIDE

    worldCache = {}
    scanIndex = 0
    scanRadius, scanFace = 0, 0
    scanA, scanB = 0, 0
    scanCredit = 0
    lastUpdateTime = getTime()
    scanCompleted = false
    raycastDirty = true

    if showNotification then
        notify("Cache cleared! Radius: " .. RADIUS .. " | Restarting scan...")
    end
end

-- Walk concentric cube shells without materializing a scan queue. The six face
-- ranges are disjoint, so every voxel is produced exactly once and nearby data
-- becomes visible first.
local function nextScanPosition()
    if scanRadius == 0 then
        scanRadius, scanFace = 1, 1
        scanA, scanB = -1, -1
        return centerX, centerY, centerZ
    end

    local r = scanRadius
    local x, y, z
    local minA, maxA, minB, maxB

    if scanFace <= 2 then
        x, y, z = scanA, (scanFace == 1 and -r or r), scanB
        minA, maxA, minB, maxB = -r, r, -r, r
    elseif scanFace <= 4 then
        x, y, z = (scanFace == 3 and -r or r), scanA, scanB
        minA, maxA, minB, maxB = -r + 1, r - 1, -r, r
    else
        x, y, z = scanA, scanB, (scanFace == 5 and -r or r)
        minA, maxA, minB, maxB = -r + 1, r - 1, -r + 1, r - 1
    end

    scanB = scanB + 1
    if scanB > maxB then
        scanB = minB
        scanA = scanA + 1
        if scanA > maxA then
            scanFace = scanFace + 1
            if scanFace > 6 then
                scanRadius = scanRadius + 1
                scanFace = 1
            end

            r = scanRadius
            if scanFace <= 2 then
                scanA, scanB = -r, -r
            elseif scanFace <= 4 then
                scanA, scanB = -r + 1, -r
            else
                scanA, scanB = -r + 1, -r + 1
            end
        end
    end

    return centerX + x, centerY + y, centerZ + z
end

local function updateScan(now)
    local elapsed = (now - lastUpdateTime) * 0.001
    lastUpdateTime = now

    if scanCompleted or TOTAL_BLOCKS == 0 then return end
    if elapsed < 0 then elapsed = 0 end
    if elapsed > 0.1 then elapsed = 0.1 end

    scanCredit = m_min(scanCredit + elapsed * BLOCKS_PER_SECOND, MAX_SCAN_BATCH)
    local blocksToScan = m_floor(scanCredit)
    if blocksToScan <= 0 then return end
    scanCredit = scanCredit - blocksToScan

    local remaining = TOTAL_BLOCKS - scanIndex
    if blocksToScan > remaining then blocksToScan = remaining end

    for _ = 1, blocksToScan do
        local wx, wy, wz = nextScanPosition()
        local blockName = getBlock(wx, wy, wz)
        if blockName and blockName ~= "minecraft:air" then
            local cacheIndex = (wx - worldMinX) * PLANE +
                               (wy - worldMinY) * SIDE +
                               (wz - worldMinZ)
            worldCache[cacheIndex] = blockColors[blockName] or UNKNOWN_SHADES
        end

        scanIndex = scanIndex + 1
    end

    raycastDirty = true
    if scanIndex >= TOTAL_BLOCKS then
        scanCompleted = true
        notify("Scan complete!")
    end
end

-- ==========================================
-- 6. RAYCASTING
-- ==========================================

local function raycastFrame()
    local cosY, sinY = m_cos(yaw), m_sin(yaw)
    local cosP, sinP = m_cos(pitch), m_sin(pitch)
    local camMapX, camMapY, camMapZ = m_floor(camX), m_floor(camY), m_floor(camZ)
    local camInBounds = camMapX >= worldMinX and camMapX <= worldMaxX and
                        camMapY >= worldMinY and camMapY <= worldMaxY and
                        camMapZ >= worldMinZ and camMapZ <= worldMaxZ
    local camCacheIndex = (camMapX - worldMinX) * PLANE +
                          (camMapY - worldMinY) * SIDE +
                          (camMapZ - worldMinZ)
    local camCellSolid = camInBounds and worldCache[camCacheIndex] ~= nil
    local pixelIndex = 0

    for py = 1, H do
        local v = rayV[py]
        local forward = v * sinP + cosP
        local dirY = v * cosP - sinP

        for px = 1, W do
            local u = rayU[px]
            local dirX = u * cosY + forward * sinY
            local dirZ = u * sinY - forward * cosY
            local mapX, mapY, mapZ = camMapX, camMapY, camMapZ
            local cacheIndex = camCacheIndex

            local deltaDistX = dirX == 0 and 1e30 or m_abs(1 / dirX)
            local deltaDistY = dirY == 0 and 1e30 or m_abs(1 / dirY)
            local deltaDistZ = dirZ == 0 and 1e30 or m_abs(1 / dirZ)
            local stepX, stepY, stepZ
            local sideDistX, sideDistY, sideDistZ

            if dirX < 0 then
                stepX, sideDistX = -1, (camX - mapX) * deltaDistX
            else
                stepX, sideDistX = 1, (mapX + 1 - camX) * deltaDistX
            end
            if dirY < 0 then
                stepY, sideDistY = -1, (camY - mapY) * deltaDistY
            else
                stepY, sideDistY = 1, (mapY + 1 - camY) * deltaDistY
            end
            if dirZ < 0 then
                stepZ, sideDistZ = -1, (camZ - mapZ) * deltaDistZ
            else
                stepZ, sideDistZ = 1, (mapZ + 1 - camZ) * deltaDistZ
            end

            local color = SKY_COLOR
            local previousSolid = camCellSolid
            local enteredBounds = camInBounds

            for _ = 1, MAX_RAY_STEPS do
                local side
                if sideDistX < sideDistY and sideDistX < sideDistZ then
                    sideDistX = sideDistX + deltaDistX
                    mapX = mapX + stepX
                    cacheIndex = cacheIndex + stepX * PLANE
                    side = 1
                elseif sideDistY < sideDistZ then
                    sideDistY = sideDistY + deltaDistY
                    mapY = mapY + stepY
                    cacheIndex = cacheIndex + stepY * SIDE
                    side = 2
                else
                    sideDistZ = sideDistZ + deltaDistZ
                    mapZ = mapZ + stepZ
                    cacheIndex = cacheIndex + stepZ
                    side = 3
                end

                if mapX == fpX and mapZ == fpZ and (mapY == fpY or mapY == fpY + 1) then
                    color = PLAYER_COLOR
                    break
                end

                local inBounds = mapX >= worldMinX and mapX <= worldMaxX and
                                 mapY >= worldMinY and mapY <= worldMaxY and
                                 mapZ >= worldMinZ and mapZ <= worldMaxZ

                if inBounds then
                    enteredBounds = true
                    local block = worldCache[cacheIndex]
                    if block and not previousSolid then
                        color = block[side]
                        break
                    end
                    previousSolid = block ~= nil
                elseif enteredBounds then
                    break
                else
                    previousSolid = false
                end
            end

            pixelIndex = pixelIndex + 1
            pixelColors[pixelIndex] = color
        end
    end
end

-- ==========================================
-- 7. EVENT HANDLERS
-- ==========================================

-- Movement keys are tracked here; configurable keybinds are edge-detected in
-- SetupAndRenderEvent because their .value field already represents key state.
onEvent("KeyEvent", function(key, action)
    local keyName = keyMap[key]
    if keyName then
        if action == 1 then
            keys[keyName] = true
        elseif action == 0 then
            keys[keyName] = false
        end
    end
end)

-- Mouse wheel adjusts FOV. Only 192 scalar axis values are refreshed.
onEvent("MouseEvent", function(button, action)
    if button ~= 4 then return end

    if action == 4 then
        fovY = m_min(fovY + 0.1, 1.8)
    elseif action == 3 then
        fovY = m_max(fovY - 0.1, 0.1)
    else
        return
    end
    updateRayAxes()
end)

-- This event is faster than TickEvent and explicitly safe for player access.
-- Smaller scan batches greatly reduce frame-time spikes at high scan rates.
onEvent("SetupAndRenderEvent", function()
    local oldFpX, oldFpY, oldFpZ = fpX, fpY, fpZ
    playerX, playerY, playerZ = getPlayerPosition()
    fpX, fpY, fpZ = m_floor(playerX), m_floor(playerY), m_floor(playerZ)

    if fpX ~= oldFpX or fpY ~= oldFpY or fpZ ~= oldFpZ then
        raycastDirty = true
    end

    if not camInitialized then
        centerX, centerY, centerZ = fpX, fpY, fpZ
        camX, camY, camZ = playerX, playerY + 1.6, playerZ
        camInitialized = true
        resetCache(false)
    end

    local uiDown = OpenDroneUIKey.value
    local rescanDown = RescanKey.value
    local teleportDown = TeleportToPlayerKey.value

    if uiDown and not uiKeyWasDown then
        renderVisible = not renderVisible
    end
    if rescanDown and not rescanKeyWasDown and renderVisible then
        resetCache(true)
    end
    if teleportDown and not teleportKeyWasDown and renderVisible then
        camX, camY, camZ = playerX, playerY + 1.6, playerZ
        notify("Camera teleported to player!")
    end

    uiKeyWasDown = uiDown
    rescanKeyWasDown = rescanDown
    teleportKeyWasDown = teleportDown

    updateScan(getTime())
end)

onEvent("ChangeDimensionEvent", function()
    renderVisible = false
    camInitialized = false
    scanCompleted = false
    worldCache = {}
    scanIndex = 0
    TOTAL_BLOCKS = 0
    raycastDirty = true
end)

-- RenderEvent only handles ImGui and cached numeric state. No player/world API
-- calls occur here, matching Flarial's event safety contract.
onEvent("RenderEvent", function()
    if getScreenName() ~= "inventory_screen" then
        renderVisible = false
    end
    if not renderVisible then return end

    local dt = getDeltaTime()
    if dt < 0 then dt = 0 end
    if dt > 0.05 then dt = 0.05 end

    local changed = false
    local rotationDelta = ROTATE_SPEED * dt
    if keys["left"] then yaw = yaw - rotationDelta; changed = true end
    if keys["right"] then yaw = yaw + rotationDelta; changed = true end
    if keys["up"] then pitch = pitch - rotationDelta; changed = true end
    if keys["down"] then pitch = pitch + rotationDelta; changed = true end
    if pitch > 1.5 then pitch = 1.5 end
    if pitch < -1.5 then pitch = -1.5 end

    local speed = MOVE_SPEED
    if keys["shift"] then speed = FAST_SPEED
    elseif keys["z"] then speed = SLOW_SPEED end
    speed = speed * dt

    if keys["w"] or keys["s"] or keys["a"] or keys["d"] then
        local sinYaw, cosYaw = m_sin(yaw), m_cos(yaw)
        if keys["w"] then camX = camX + sinYaw * speed; camZ = camZ - cosYaw * speed end
        if keys["s"] then camX = camX - sinYaw * speed; camZ = camZ + cosYaw * speed end
        if keys["a"] then camX = camX - cosYaw * speed; camZ = camZ - sinYaw * speed end
        if keys["d"] then camX = camX + cosYaw * speed; camZ = camZ + sinYaw * speed end
        changed = true
    end
    if keys["space"] then camY = camY + speed; changed = true end
    if keys["c"] then camY = camY - speed; changed = true end
    if changed then raycastDirty = true end

    local now = getTime()
    if raycastDirty and now - lastRaycastTime >= RAYCAST_INTERVAL_MS then
        lastRaycastTime = now
        raycastFrame()
        rebuildDrawRuns()
        raycastDirty = false
    end

    local drawList = getForegroundDrawList()
    local addRectFilled = drawList.AddRectFilled
    for i = 1, drawRunCount do
        local run = drawRuns[i]
        addRectFilled(drawList, run.p1, run.p2, run.color, 0, 0)
    end
end)
