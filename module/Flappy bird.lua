name = "Flappy Bird"
description = "Flappy Bird on a virtual Game Boy inside the inventory"
author = "zebedelu"

-- Configs
local openKey = settings.addKeybind("Open Flappy Bird", "Opens the game when in the inventory")
local fpsTextBox = settings.addSlider("FPS", "The FPS of the flappy bird", 24, 120, 12, false)

local GAME_FPS = math.floor(tonumber(fpsTextBox.value))
local frame_delay = 1.0 / GAME_FPS

-- Game Boy Base Dimensions (Logical)
local GB_W, GB_H = 440, 680
local SCR_W, SCR_H = 320, 280

-- State
local is_open = false
local state = "MENU" -- MENU, PLAYING, GAMEOVER
local score = 0
local high_score = 0
local bird_x, bird_y, bird_vel = 80, SCR_H/2, 0
local bird_rot = 0
local has_jumped = false
local pipes = {}
local last_pipe_time = 0
local bg1, bg2 = 0, 0
local last_frame = os.clock()

-- Physics & Game Balance
local GRAVITY = 800
local JUMP_VEL = 300
local PIPE_SPEED = 150
local PIPE_GAP = 120
local PIPE_W = 50

function resetGame()
    state = "MENU"
    score = 0
    bird_x, bird_y, bird_vel = 80, SCR_H/2, 0
    bird_rot = 0
    has_jumped = false
    pipes = {}
    last_pipe_time = os.clock()
end

function startGame()
    state = "PLAYING"
    score = 0
    bird_x, bird_y, bird_vel = 80, SCR_H/2, 0
    bird_rot = 0
    has_jumped = false
    pipes = {}
    last_pipe_time = os.clock()
end

function gameOver()
    if state == "PLAYING" then
        state = "GAMEOVER"
        if score > high_score then high_score = score end
    end
end

-- Ponytail: Helper for clouds
local function drawCloud(draw, x, y, s, alpha)
    draw:AddCircleFilled({x, y}, 18 * s, {255, 255, 255, alpha}, 16)
    draw:AddCircleFilled({x + 20 * s, y - 8 * s}, 24 * s, {255, 255, 255, alpha}, 16)
    draw:AddCircleFilled({x + 45 * s, y + 2 * s}, 20 * s, {255, 255, 255, alpha}, 16)
    draw:AddCircleFilled({x + 22 * s, y + 10 * s}, 18 * s, {255, 255, 255, alpha}, 16)
end

-- Ponytail: Dynamic button that accepts scale and centers correctly
local function drawButton(draw, abs_x, abs_y, w, h, text, scale)
    local m = ImGui.GetMousePos()
    local mx, my = m.x or m[1], m.y or m[2]
    local hover = mx >= abs_x and mx <= abs_x + w and my >= abs_y and my <= abs_y + h
    local col = hover and {50, 150, 250, 255} or {80, 80, 80, 255}
    
    draw:AddRectFilled({abs_x, abs_y}, {abs_x + w, abs_y + h}, col, 4 * scale, 0)
    
    local font_size = 14 * scale
    local offset_x = string.len(text) * (font_size * 0.28)
    draw:AddText({abs_x + (w/2) - offset_x, abs_y + (h/2) - (font_size/2)}, {255, 255, 255, 255}, font_size, text)
    return hover and ImGui.IsMouseClicked(0)
end

onEvent("KeyEvent", function(key, isDown)
    GAME_FPS = math.floor(tonumber(fpsTextBox.value))
    frame_delay = 1.0 / GAME_FPS
    if openKey.value == true and isDown then
        if client.getScreenName() == "inventory_screen" then
            is_open = not is_open
            if not is_open then resetGame() end
        else
            is_open = false
        end
    end
    
    if is_open and state == "PLAYING" and key == 32 and isDown then
        if not has_jumped then
            has_jumped = true
            last_pipe_time = os.clock()
        end
        bird_vel = -JUMP_VEL 
    end
end)

onEvent("RenderEvent", function()
    local screen = client.getScreenName()
    if not is_open or screen ~= "inventory_screen" then
        if is_open and screen ~= "inventory_screen" then
            is_open = false
            resetGame()
        end
        return
    end

    -- 1. Time and Scale Calculation
    local now = os.clock()
    local dt = now - last_frame
    local disp = ImGui.GetDisplaySize()
    local dx, dy = disp.x or disp[1], disp.y or disp[2]
    
    local scale = (dx * 0.8) / GB_W
    if GB_H * scale > dy * 0.9 then
        scale = (dy * 0.9) / GB_H
    end

    local gx = (dx - GB_W * scale) / 2
    local gy = (dy - GB_H * scale) / 2
    local sx = gx + 60 * scale
    local sy = gy + 110 * scale
    local scr_w_s = SCR_W * scale
    local scr_h_s = SCR_H * scale

    -- 2. Game Logic (24 FPS)
    if dt >= frame_delay then
        last_frame = now
        
        if state == "PLAYING" then
            if has_jumped then
                bird_vel = bird_vel + GRAVITY * dt
                bird_y = bird_y + bird_vel * dt
                bird_rot = util.clamp(bird_vel / JUMP_VEL * 0.4, -0.4, 0.5)
                
                for i, p in ipairs(pipes) do
                    p.x = p.x - PIPE_SPEED * dt
                    if not p.scored and p.x + PIPE_W < bird_x then
                        p.scored = true
                        score = score + 1
                    end
                end
                while #pipes > 0 and pipes[1].x < -PIPE_W do table.remove(pipes, 1) end
                
                local interval = (#pipes == 0) and 2.0 or 1.5
                if now - last_pipe_time > interval then
                    table.insert(pipes, { x = SCR_W, gap_y = math.random(60, SCR_H - 90), scored = false })
                    last_pipe_time = now
                end
                
                if bird_y < 0 or bird_y > SCR_H - 20 then gameOver() end
                for i, p in ipairs(pipes) do
                    if p.x < bird_x + 10 and p.x + PIPE_W > bird_x - 10 then
                        if bird_y - 10 < p.gap_y - PIPE_GAP/2 or bird_y + 10 > p.gap_y + PIPE_GAP/2 then
                            gameOver()
                        end
                    end
                end
            end
            
            -- Ponytail: 480 = 4 * 120px. Modulo greater than the screen ensures it spawns off-screen and disappears off-screen
            bg1 = (bg1 - 10 * dt) % 480
            bg2 = (bg2 - 30 * dt) % 480
        end
    end

    -- 3. Rendering
    local draw = ImGui.GetForegroundDrawList()
    
    -- A. Screen Background (Blue)
    draw:AddRectFilled({sx, sy}, {sx + scr_w_s, sy + scr_h_s}, {150, 220, 255, 255}, 0, 0)
    
    -- Section for Clouds
    for i = 0, 2 do
        local cx = sx + ((bg2 + i * 120) % 365) * scale
        local cy = sy + 40 * scale
        drawCloud(draw, cx-50, cy, scale * 0.6, 220)
    end

    -- C. Static Ground
    draw:AddRectFilled({sx, sy + (SCR_H - 20) * scale}, {sx + scr_w_s, sy + scr_h_s}, {60, 180, 100, 255}, 0, 0)
    draw:AddRectFilled({sx, sy + (SCR_H - 20) * scale}, {sx + scr_w_s, sy + (SCR_H - 15) * scale}, {150, 230, 80, 255}, 0, 0)

    -- D. Pipes
    for i, p in ipairs(pipes) do
        local px = sx + p.x * scale
        local py_top = sy + (p.gap_y - PIPE_GAP/2) * scale
        local py_bot = sy + (p.gap_y + PIPE_GAP/2) * scale
        local pw = PIPE_W * scale
        
        draw:AddRectFilled({px, sy}, {px + pw, py_top}, {100, 200, 100, 255}, 0, 0)
        draw:AddRectFilled({px - 5 * scale, py_top - 20 * scale}, {px + pw + 5 * scale, py_top}, {80, 180, 80, 255}, 0, 0)
        draw:AddRectFilled({px, py_bot}, {px + pw, sy + (SCR_H - 20) * scale}, {100, 200, 100, 255}, 0, 0)
        draw:AddRectFilled({px - 5 * scale, py_bot}, {px + pw + 5 * scale, py_bot + 20 * scale}, {80, 180, 80, 255}, 0, 0)
    end

    -- E. Bird
    local wing_off = (math.floor(os.clock() * 10) % 2 == 0) and -5 or 5
    local bx, by = sx + bird_x * scale, sy + bird_y * scale
    local cr, sr = math.cos(bird_rot), math.sin(bird_rot)
    local function rot(px, py)
        local dx, dy = px * scale, py * scale
        return {bx + dx * cr - dy * sr, by + dx * sr + dy * cr}
    end
    draw:AddCircleFilled({bx, by}, 10 * scale, {255, 220, 0, 255}, 12)
    draw:AddTriangleFilled(rot(5, -2), rot(15, 0), rot(5, 2), {255, 150, 0, 255})
    draw:AddCircleFilled(rot(4, -3), 2 * scale, {0, 0, 0, 255}, 4)
    draw:AddTriangleFilled(rot(-5, wing_off), rot(5, 0), rot(-5, 5), {255, 200, 0, 255})

    -- F. UI and Buttons
    if state == "PLAYING" then
        local fs = 20 * scale
        local s_offset = string.len(tostring(score)) * (fs * 0.3)
        draw:AddText({sx + (scr_w_s/2) - (s_offset/2), sy + 10 * scale}, {255, 255, 255, 255}, fs, tostring(score))
    elseif state == "MENU" then
        draw:AddRectFilled({sx, sy}, {sx + scr_w_s, sy + scr_h_s}, {0, 0, 0, 150}, 0, 0)
        
        local title = "FLAPPY BIRD"
        local tfs = 24 * scale
        local t_off = string.len(title) * (tfs * 0.28)
        draw:AddText({sx + (scr_w_s/2) - (t_off/2) - 40, sy + 40 * scale}, {255, 255, 0, 255}, tfs, title)
        
        local sub = "High Score: " .. tostring(high_score)
        local sfs = 16 * scale
        local s_off = string.len(sub) * (sfs * 0.28)
        draw:AddText({sx + (scr_w_s/2) - (s_off/2) - 25, sy + 90 * scale}, {255, 255, 255, 255}, sfs, sub)
        
        local btn_w, btn_h = 110 * scale, 35 * scale
        local btn_x = sx + (scr_w_s / 2) - (btn_w / 2)
        local btn_y = sy + scr_h_s * 0.65
        if drawButton(draw, btn_x, btn_y, btn_w, btn_h, "Play", scale) then startGame() end
    elseif state == "GAMEOVER" then
        draw:AddRectFilled({sx, sy}, {sx + scr_w_s, sy + scr_h_s}, {0, 0, 0, 150}, 0, 0)
        
        local title = "GAME OVER"
        local tfs = 24 * scale
        local t_off = string.len(title) * (tfs * 0.28)
        draw:AddText({sx + (scr_w_s/2) - (t_off/2) - 40, sy + 40 * scale}, {255, 0, 0, 255}, tfs, title)
        
        local p_txt = "Score: " .. tostring(score)
        local pfs = 16 * scale
        local p_off = string.len(p_txt) * (pfs * 0.28)
        draw:AddText({sx + (scr_w_s/2) - (p_off/2) - 25, sy + 90 * scale}, {255, 255, 255, 255}, pfs, p_txt)
        
        local r_txt = "High Score: " .. tostring(high_score)
        local rfs = 16 * scale
        local r_off = string.len(r_txt) * (rfs * 0.28)
        draw:AddText({sx + (scr_w_s/2) - (r_off/2) - 25, sy + 120 * scale}, {255, 255, 0, 255}, rfs, r_txt)
        
        local btn_w, btn_h = 110 * scale, 35 * scale
        local btn_x = sx + (scr_w_s / 2) - (btn_w / 2)
        local btn1_y = sy + scr_h_s * 0.65
        local btn2_y = sy + scr_h_s * 0.82
        
        if drawButton(draw, btn_x, btn1_y, btn_w, btn_h, "Restart", scale) then startGame() end
        if drawButton(draw, btn_x, btn2_y, btn_w, btn_h, "Exit", scale) then is_open = false; resetGame() end
    end

    -- G. Masking (GameBoy Frame)
    local bezel = 32 * scale
    -- Black around the screen (Border)
    draw:AddRectFilled({sx - bezel, sy - bezel}, {sx + scr_w_s + bezel, sy}, {50, 50, 50, 255}, 0, 0)
    draw:AddRectFilled({sx - bezel, sy + scr_h_s}, {sx + scr_w_s + bezel, sy + scr_h_s + bezel}, {50, 50, 50, 255}, 0, 0)
    draw:AddRectFilled({sx - bezel, sy}, {sx, sy + scr_h_s}, {50, 50, 50, 255}, 0, 0)
    draw:AddRectFilled({sx + scr_w_s, sy}, {sx + scr_w_s + bezel, sy + scr_h_s}, {50, 50, 50, 255}, 0, 0)

    -- Beige Chassis (Final layer that hides everything leaking outside)
    -- Top
    draw:AddRectFilled({gx, gy+60}, {gx + GB_W * scale, sy - bezel}, {220, 210, 190, 255}, 12 * scale, 3)
    -- Bottom
    draw:AddRectFilled({gx, sy + scr_h_s + bezel}, {gx + GB_W * scale, gy + GB_H * scale}, {220, 210, 190, 255}, 12 * scale, 12)
    -- Left
    draw:AddRectFilled({gx, sy - bezel - 20}, {sx - bezel, sy + scr_h_s + bezel + 20}, {220, 210, 190, 255}, 0, 0)
    -- Right
    draw:AddRectFilled({sx + scr_w_s + bezel, sy - bezel - 20}, {gx + GB_W * scale, sy + scr_h_s + bezel + 20}, {220, 210, 190, 255}, 0, 0)
    -- H. DMG Details (Reference)
    -- DOT MATRIX Text
    draw:AddText({sx, sy - 50 * scale}, {80, 80, 80, 255}, 15 * scale, "DOT MATRIX WITH STEREO SOUND")
    
    -- D-Pad (Black Cross with center)
    draw:AddRectFilled({gx + 80 * scale - 35, gy + 500 * scale - 35}, {gx + 110 * scale - 35, gy + 570 * scale - 35}, {40, 40, 40, 255}, 0, 0)
    draw:AddRectFilled({gx + 60 * scale - 35, gy + 520 * scale - 35}, {gx + 130 * scale - 35, gy + 550 * scale - 35}, {40, 40, 40, 255}, 0, 0)
    
    -- A/B Buttons (Magenta)
    draw:AddCircleFilled({gx + 400 * scale, gy + 520 * scale}, 22 * scale, {180, 50, 100, 255}, 12)
    draw:AddCircleFilled({gx + 340 * scale, gy + 550 * scale}, 22 * scale, {180, 50, 100, 255}, 12)
    draw:AddText({gx + 395 * scale, gy + 510 * scale}, {255, 50, 50, 255}, 20 * scale, "A")
    draw:AddText({gx + 335 * scale, gy + 540 * scale}, {255, 50, 50, 255}, 20 * scale, "B")
    
    -- Start/Select (Gray pill-shaped)    
    draw:AddLine({gx + 166 * scale, gy + 590 * scale}, {gx + 210 * scale, gy + 580 * scale}, {100, 100, 100, 255}, 12 * scale)
    draw:AddLine({gx + 226 * scale, gy + 590 * scale}, {gx + 270 * scale, gy + 580 * scale}, {100, 100, 100, 255}, 12 * scale)
    draw:AddText({gx + 170 * scale, gy + 600 * scale}, {80, 80, 80, 255}, 7 * scale, "SELECT")
    draw:AddText({gx + 230 * scale, gy + 600 * scale}, {80, 80, 80, 255}, 7 * scale, "START")
    
    -- Speaker (Diagonal lines)
    for i=0, 5 do
        local off = i * 10 * scale
        draw:AddLine({gx + 330 * scale + off, gy + 620 * scale - i * 8}, {gx + 350 * scale + off, gy + 660 * scale - i * 8}, {80, 80, 80, 255}, 2 * scale)
    end
end)