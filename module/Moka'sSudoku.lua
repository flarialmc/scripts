
name = "Moka's Sudoku"
description = "Moka's Sudoku, a fun, clean, fully client-side Sudoku game with challenge mode and stats!"
author = "moka"

local sudokuGrid, solutionGrid, lockedGrid, history = {}, {}, {}, {}
local moves, mistakes, hintsUsed, puzzlesCompleted = 0, 0, 0, 0
local maxHints = 3
local lastDifficulty = "medium"
local challenge = false

-- Create blank 9x9
local function initGrids()
    sudokuGrid, solutionGrid, lockedGrid, history = {}, {}, {}, {}
    for i = 1, 9 do
        sudokuGrid[i], solutionGrid[i], lockedGrid[i] = {}, {}, {}
        for j = 1, 9 do
            sudokuGrid[i][j] = 0
            solutionGrid[i][j] = 0
            lockedGrid[i][j] = 0
        end
    end
    moves, mistakes, hintsUsed = 0, 0, 0
end

-- Shuffle
local function shuffle(t)
    for i = #t, 2, -1 do
        local j = math.random(i)
        t[i], t[j] = t[j], t[i]
    end
end

-- Validation
local function isValid(grid, row, col, num)
    for i = 1, 9 do
        if grid[row][i] == num or grid[i][col] == num then return false end
    end
    local sr, sc = math.floor((row - 1) / 3) * 3 + 1, math.floor((col - 1) / 3) * 3 + 1
    for i = sr, sr + 2 do for j = sc, sc + 2 do if grid[i][j] == num then return false end end end
    return true
end

-- Backtrack fill
local function fillGrid(grid)
    for r = 1, 9 do
        for c = 1, 9 do
            if grid[r][c] == 0 then
                local nums = {1,2,3,4,5,6,7,8,9}
                shuffle(nums)
                for _, n in ipairs(nums) do
                    if isValid(grid, r, c, n) then
                        grid[r][c] = n
                        if fillGrid(grid) then return true end
                        grid[r][c] = 0
                    end
                end
                return false
            end
        end
    end
    return true
end

local function removeNumbers(grid, count)
    while count > 0 do
        local r, c = math.random(9), math.random(9)
        if grid[r][c] ~= 0 then grid[r][c] = 0 count = count - 1 end
    end
end

local function printGrid()
    print("    1 2 3 4 5 6 7 8 9")
    for i = 1, 9 do
        local row = (i < 10 and " " or "") .. i .. ": "
        for j = 1, 9 do
            row = row .. (sudokuGrid[i][j] == 0 and "□ " or sudokuGrid[i][j] .. " ")
            if j == 3 or j == 6 then row = row .. "| " end
        end
        print(row)
        if i == 3 or i == 6 then print("   ---------------------") end
    end
end

local function isComplete()
    for i = 1, 9 do for j = 1, 9 do if sudokuGrid[i][j] == 0 then return false end end end
    return true
end

local function generatePuzzle(diff)
    local blanks = { easy = 30, medium = 45, hard = 60 }
    local count = blanks[diff] or 45
    lastDifficulty = diff
    initGrids()
    fillGrid(solutionGrid)
    for i = 1, 9 do for j = 1, 9 do sudokuGrid[i][j] = solutionGrid[i][j] end end
    removeNumbers(sudokuGrid, count)
    for i = 1, 9 do for j = 1, 9 do lockedGrid[i][j] = sudokuGrid[i][j] end end
    print("🧩 New puzzle generated (" .. diff .. ")")
    printGrid()
end

function onEnable()
    -- Default puzzle on load
    generatePuzzle("medium")
end

-- Command handler
registerCommand("sudoku", function(args)
    if #args == 0 or args[1] == "help" then
        print("🧠 Moka's Sudoku Commands:")
        print(".sudoku print       → Show the puzzle")
        print(".sudoku set r c n   → Set row/col = number (1–9)")
        print(".sudoku show r c    → Reveal correct value at cell")
        print(".sudoku easy|medium|hard → New puzzle by difficulty")
        print(".sudoku reset       → Reset current puzzle")
        print(".sudoku undo        → Undo last move")
        print(".sudoku hint        → Fill one empty cell (3 max)")
        print(".sudoku stats       → Show progress")
        print(".sudoku challenge on/off → Toggle challenge mode")
        print(".sudoku new         → Regenerate last-used difficulty")
        return
    end

    local cmd = args[1]

    if cmd == "print" then
        printGrid()

    elseif cmd == "new" then
        generatePuzzle(lastDifficulty)

    elseif cmd == "easy" or cmd == "medium" or cmd == "hard" then
        generatePuzzle(cmd)

    elseif cmd == "reset" then
        for i = 1, 9 do for j = 1, 9 do sudokuGrid[i][j] = lockedGrid[i][j] end end
        history, moves, mistakes, hintsUsed = {}, 0, 0, 0
        print("🔄 Puzzle reset.")
        printGrid()

    elseif cmd == "set" and #args == 4 then
        local r, c, n = tonumber(args[2]), tonumber(args[3]), tonumber(args[4])
        if not r or not c or not n or r < 1 or r > 9 or c < 1 or c > 9 or n < 1 or n > 9 then
            print("❌ Use: .sudoku set <row> <col> <number> (1–9)")
            return
        end
        if lockedGrid[r][c] ~= 0 then print("❌ That cell is locked.") return end
        if not isValid(sudokuGrid, r, c, n) then
            print("❌ Invalid move.")
            mistakes = mistakes + 1
            if challenge and mistakes > 3 then print("☠️ Challenge failed — too many mistakes.") end
            return
        end
        table.insert(history, { row = r, col = c, prev = sudokuGrid[r][c] })
        sudokuGrid[r][c] = n
        moves = moves + 1
        print("✅ Set [" .. r .. "," .. c .. "] = " .. n)
        if isComplete() then
            local acc = math.floor((1 - (mistakes / math.max(1, moves))) * 1000) / 10
            print("🎯 Puzzle Complete!")
            print("✅ Accuracy: " .. acc .. "% | Moves: " .. moves .. " | Mistakes: " .. mistakes)
        end

    elseif cmd == "undo" then
        if challenge then print("❌ Undo disabled in challenge mode.") return end
        local last = table.remove(history)
        if last then
            sudokuGrid[last.row][last.col] = last.prev
            print("↩️ Undid move at [" .. last.row .. "," .. last.col .. "]")
        else
            print("Nothing to undo.")
        end

    elseif cmd == "hint" then
        if challenge then print("❌ Hints disabled in challenge mode.") return end
        if hintsUsed >= maxHints then print("❌ No hints left.") return end
        local empties = {}
        for i = 1, 9 do for j = 1, 9 do if sudokuGrid[i][j] == 0 then table.insert(empties, {i, j}) end end end
        if #empties == 0 then print("❌ No empty cells.") return end
        local pick = empties[math.random(#empties)]
        sudokuGrid[pick[1]][pick[2]] = solutionGrid[pick[1]][pick[2]]
        lockedGrid[pick[1]][pick[2]] = solutionGrid[pick[1]][pick[2]]
        hintsUsed = hintsUsed + 1
        print("💡 Hint: [" .. pick[1] .. "," .. pick[2] .. "] = " .. solutionGrid[pick[1]][pick[2]])

    elseif cmd == "show" and #args == 3 then
        local r, c = tonumber(args[2]), tonumber(args[3])
        if r and c and r >= 1 and r <= 9 and c >= 1 and c <= 9 then
            print("👁️ [" .. r .. "," .. c .. "] = " .. solutionGrid[r][c])
        else print("Use: .sudoku show <row> <col>") end

    elseif cmd == "stats" then
        print("📊 Moka's Sudoku Progress:")
        print("Moves: " .. moves .. " | Mistakes: " .. mistakes .. " | Hints: " .. hintsUsed .. "/" .. maxHints)

    elseif cmd == "challenge" and #args == 2 then
        if args[2] == "on" then challenge = true print("⚔️ Challenge mode ON") end
        if args[2] == "off" then challenge = false print("🛡️ Challenge mode OFF") end
    else
        print("❓ Unknown command. Try: .sudoku help")
    end
end)
