local printer = {}

---This is a library to handle mass 16 color printing in ComputerCraft.

-- This requires abstractInvLib https://gist.github.com/MasonGulu/57ef0f52a93304a17a9eaea21f431de6

-- Copyright 2023 Mason Gulu
-- Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
-- The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.


local abstractInventory = require "abstractInvLib"

local PAPER_ITEM = "minecraft:paper"
local DYE_ITEMS = {
    ["0"] = "minecraft:white_dye", -- why?
    ["1"] = "minecraft:orange_dye",
    ["2"] = "minecraft:magenta_dye",
    ["3"] = "minecraft:light_blue_dye",
    ["4"] = "minecraft:yellow_dye",
    ["5"] = "minecraft:lime_dye",
    ["6"] = "minecraft:pink_dye",
    ["7"] = "minecraft:gray_dye",
    ["8"] = "minecraft:light_gray_dye",
    ["9"] = "minecraft:cyan_dye",
    ["a"] = "minecraft:purple_dye",
    ["b"] = "minecraft:blue_dye",
    ["c"] = "minecraft:brown_dye",
    ["d"] = "minecraft:green_dye",
    ["e"] = "minecraft:red_dye",
    ["f"] = "minecraft:black_dye",
}

local PAGE_WIDTH = 25
local PAGE_HEIGHT = 21

local PRINTER_INPUT_SLOT = 2
local PRINTER_DYE_SLOT = 1 -- TODO Check this
local PRINTER_OUT_SLOT = 8

---@alias colChar "0"|"1"|"2"|"3"|"4"|"5"|"6"|"7"|"8"|"9"|"a"|"b"|"c"|"d"|"e"|"f"
---@alias y integer
---@alias x integer


---@alias printablePage table<colChar,table<y,table<x,string>>>

---Shallow clone a table
---@param ot table
---@return table
local function clone(ot)
    local nt = {}
    for k, v in pairs(ot) do
        nt[k] = v
    end
    return nt
end

---Create a printer manager
---@param stockpileInvs string[]
---@param workspaceInvs string[]
---@param outputInv string
---@param printers string[]?
---@return table
function printer.printer(stockpileInvs, workspaceInvs, outputInv, printers)
    --- Inventories to pull papers and dyes from
    local stockpile = abstractInventory(stockpileInvs, nil)
    --- list of inventories to use as space for transfering papers around
    local workspace = abstractInventory(workspaceInvs, nil, { filename = "workspace.log", cache = false })

    local output = outputInv

    local attachedPeripherals = peripheral.getNames()

    ---@type table<integer,string> printers open to print on
    local availablePrinters = printers or {}
    if not printers then
        for k, v in ipairs(attachedPeripherals) do
            if peripheral.hasType(v, "printer") then
                availablePrinters[#availablePrinters + 1] = v
            end
        end
    end

    ---@type table<thread,string|nil>
    local threadFilters = {}

    ---@type thread[]
    local printThreads = {}

    ---@type table<integer,true|nil>
    local freeSlots = {}
    for i = 1, workspace.size() do
        freeSlots[i] = true
    end

    ---@return integer
    local function allocateSlot()
        local i = next(freeSlots)
        if not i then
            os.pullEvent("slot_freed")
            return allocateSlot()
        end
        freeSlots[i] = nil
        return i
    end

    ---@param slot integer
    local function freeSlot(slot)
        freeSlots[slot] = true
        os.queueEvent("slot_freed")
    end

    ---@return string
    local function allocatePrinter()
        local i, printer = next(availablePrinters)
        if not printer then
            os.pullEvent("printer_freed")
            return allocatePrinter()
        end
        availablePrinters[i] = nil -- set as busy
        return printer
    end

    ---@param printer string
    local function freePrinter(printer)
        availablePrinters[#availablePrinters + 1] = printer
        os.queueEvent("printer_freed")
    end

    local function emptyPrinter(printer)
        pcall(peripheral.call, printer, "endPage")
        stockpile.pullItems(printer, PRINTER_DYE_SLOT)
        local slot = allocateSlot()
        for i = PRINTER_INPUT_SLOT, 13 do
            workspace.pullItems(printer, i, nil, slot)
            workspace.pushItems(output, slot, nil, nil, nil, { optimal = false })
        end
        freeSlot(slot)
    end
    ---Empty all printers
    local function emptyPrinters()
        for k, v in pairs(workspace.list()) do
            workspace.pushItems(output, k, nil, nil, nil, { optimal = false })
        end
        local e = {}
        for k, v in pairs(availablePrinters) do
            table.insert(e, function() emptyPrinter(v) end)
        end
        parallel.waitForAll(table.unpack(e))
    end
    ---Print a given page
    ---@param name string
    ---@param page printablePage
    local function printPage(name, page)
        if not next(page) then
            return
        end
        page = clone(page)
        local coro = coroutine.create(function()
            local free = allocateSlot()
            local printer = allocatePrinter()
            -- move paper to the printer
            stockpile.pushItems(printer, PAPER_ITEM, 1, PRINTER_INPUT_SLOT)
            while true do
                -- get the next color
                local col, pg = next(page)
                page[col] = nil
                stockpile.pushItems(printer, DYE_ITEMS[col], 1, PRINTER_DYE_SLOT)
                if not peripheral.call(printer, "newPage") then
                    error("Failed to start page on " .. printer, 2)
                end
                for y, line in pairs(pg) do
                    for x, ch in pairs(line) do
                        peripheral.call(printer, "setCursorPos", x, y)
                        peripheral.call(printer, "write", ch)
                    end
                end
                peripheral.call(printer, "setPageTitle", name)
                peripheral.call(printer, "endPage")
                if not next(page) then
                    -- ran out of colors
                    assert(workspace.pullItems(printer, PRINTER_OUT_SLOT, 1, free) == 1, "Failed to move")
                    assert(workspace.pushItems(output, free, 1, nil, nil, { optimal = false }) == 1, "Failed to move")
                    freePrinter(printer)
                    freeSlot(free)
                    return
                end
                assert(workspace.pullItems(printer, PRINTER_OUT_SLOT, 1, free) == 1, "Failed to move")
                assert(workspace.pushItems(printer, free, 1, PRINTER_INPUT_SLOT) == 1, "Failed to move")
            end
        end)
        printThreads[#printThreads + 1] = coro
        coroutine.resume(printThreads[#printThreads])
    end

    ---Check if we can print a document
    ---@param document printablePage[]
    ---@return boolean success
    ---@return string reason
    local function canPrint(document)
        if #document > stockpile.getCount(PAPER_ITEM) then
            return false, "Not enough paper."
        end
        ---@type table<colChar,integer>
        local requiredColors = {}
        for n, page in pairs(document) do
            for col, _ in pairs(page) do
                requiredColors[col] = (requiredColors[col] or 0) + 1
            end
        end

        for col, req in pairs(requiredColors) do
            if req > stockpile.getCount(DYE_ITEMS[col]) then
                return false, ("Not enough %s."):format(DYE_ITEMS[col])
            end
        end

        return true, ""
    end

    ---Print a document
    ---@param title string
    ---@param document printablePage[]
    ---@return boolean success
    ---@return string? reason
    local function printDocument(title, document)
        local isPrintable, reason = canPrint(document)
        if not isPrintable then
            return isPrintable, reason
        end
        local pages = #document
        for n, page in ipairs(document) do
            if pages > 1 then
                printPage(string.format("%s (%u of %u)", title, n, pages), page)
            else
                printPage(title, page)
            end
        end
        return true
    end

    --- Start processing print queue, run this in parallel with your code.
    local function processPrintQueue()
        while true do
            local timerId = os.startTimer(0)
            local e = table.pack(os.pullEventRaw())
            os.cancelTimer(timerId)
            if e[1] == "terminate" then
                print("Terminated.")
                return
            end
            local dead = {}
            for i, co in ipairs(printThreads) do
                if not threadFilters[co] or threadFilters[co] == "" or threadFilters[co] == e[1] then
                    local ok, filter = coroutine.resume(co, table.unpack(e, 1, e.n))
                    if not ok then
                        error(filter)
                    elseif coroutine.status(co) == "dead" then
                        dead[#dead + 1] = i
                        threadFilters[co] = nil
                    else
                        threadFilters[co] = filter
                    end
                end
            end
            for i = #dead, 1, -1 do
                local v = dead[i]
                table.remove(printThreads, v)
            end
        end
    end

    return {
        printDocument = printDocument,
        printPage = printPage,
        canPrint = canPrint,
        emptyPrinters = emptyPrinters,
        start = processPrintQueue
    }
end

---Convert a correctly sized blitmap into a printable page
---@param blit {[1]: string, [2]: string}[]
---@return printablePage
local function splitBlitColors(blit)
    local page = {}
    for y, line in ipairs(blit) do
        local lastMatchX = 0
        local lastMatch
        for x = 1, #line[1] do
            local char = line[1]:sub(x, x)
            local bg = line[2]:sub(x, x)
            page[bg] = page[bg] or {}
            page[bg][y] = page[bg][y] or {}
            if bg == lastMatch then
                page[bg][y][lastMatchX] = page[bg][y][lastMatchX] .. char
            else
                lastMatchX = x
                lastMatch = bg
                page[bg][y][x] = char
            end
        end
    end
    return page
end

---Convert a Blit table into correctly sized pages
---@param blit table
---@return {[1]: string, [2]: string}[][]? pages
local function splitBlit(blit)
    ---@type {[1]: string, [2]: string}[][]
    local splitPages = { {} }
    local currentPageNo = 1
    local function incPage()
        currentPageNo = currentPageNo + 1
    end

    local function splitLine(charN, frame)
        local offset = 0
        for lineN, line in ipairs(frame) do
            -- this will maybe split the image to fit on multiple pages horizontally and vertically ???
            splitPages[currentPageNo] = splitPages[currentPageNo] or {}
            splitPages[currentPageNo][lineN - offset] = { line[1]:sub(charN, charN + PAGE_WIDTH), line[2]:sub(charN,
                charN + PAGE_WIDTH) }
            if (lineN / PAGE_HEIGHT) >= 1 and (lineN % PAGE_HEIGHT == 0) then
                incPage()
                offset = offset + PAGE_HEIGHT
            end
        end
        if (#frame % PAGE_HEIGHT ~= 0) then
            incPage()
        end
    end

    local function processFrame(frame)
        for charN = 1, frame[1][1]:len(), PAGE_WIDTH do
            splitLine(charN, frame)
        end
    end

    if type(blit[1][1]) == "string" then
        -- this is a 2D blit table
        processFrame(blit)
    elseif type(blit[1][1]) == "table" then
        -- this is a bimg compatible blit table
        for frameN, frame in ipairs(blit) do
            processFrame(frame)
        end
    else
        -- this is an unknown format
        return
    end
    return splitPages
end

---Convert a Blit table into a document
---@param blit table
---@return printablePage[]?
---@return string?
function printer.convertBlit(blit)
    local split = splitBlit(blit)
    if not split then
        return nil, "Unrecognized blit format"
    end
    local document = {}
    for i = 1, #split do
        document[i] = splitBlitColors(split[i])
    end
    return document
end

---@param s string
---@return string[]
local function newlineSplit(s)
    local t = {}
    for line in s:gmatch("([^\n]*)\n?") do
        t[#t + 1] = line
    end
    return t
end

---Convert plaintext
---@param text string
---@param defColor colChar?
---@return printablePage[]
function printer.convertPlaintext(text, defColor)
    defColor = defColor or "3" -- black default
    local document = {}
    local curLine, curPage = 1, 1
    local function incLine()
        curLine = curLine + 1
        if curLine > PAGE_HEIGHT then
            curPage = curPage + 1
            curLine = 1
        end
    end
    for _, line in ipairs(newlineSplit(text)) do
        for i = 1, #line, PAGE_WIDTH do
            document[curPage] = document[curPage] or {}
            document[curPage][defColor] = document[curPage][defColor] or {}
            document[curPage][defColor][curLine] = document[curPage][defColor][curLine] or {}
            document[curPage][defColor][curLine][1] = line:sub(i, i + PAGE_WIDTH)
            incLine()
        end
    end
    return document
end

---@param color colChar
---@return boolean
function printer.isValidColor(color)
    if DYE_ITEMS[color] then
        return true
    end
    return false
end

return printer
