local printer = {}

---This is a library to handle mass 16 color printing in ComputerCraft.

-- This requires abstractInvLib https://gist.github.com/MasonGulu/57ef0f52a93304a17a9eaea21f431de6

-- Copyright 2023 Mason Gulu
-- Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
-- The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.


local abstractInventory = require "libs.abstractInvLib"

local PAPER_ITEM = "minecraft:paper"
local STRING_ITEM = "minecraft:string"
local LEATHER_ITEM = "minecraft:leather"
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

local lname
if turtle then
    -- we are on a turtle
    local modem = assert(peripheral.find("modem", function(name, wrapped)
        return not wrapped.isWireless()
    end), "On a turtle, but not attached to the network!")

    lname = assert(modem.getNameLocal(), "Turtle not attached to network!")
end
local MODEM_PORT = 48752
local PROTOCOL = "SHREKPRINT"

---Create a printer manager
---@param stockpileInvs string[]
---@param workspaceInvs string[]
---@param outputInv string
---@param printers string[]?
---@return ColorPrinter
function printer.printer(stockpileInvs, workspaceInvs, outputInv, printers)
    --- Inventories to pull papers and dyes from
    local stockpile = abstractInventory(stockpileInvs, nil)
    --- list of inventories to use as space for transfering papers around
    local workspace = abstractInventory(workspaceInvs, nil)

    local output = outputInv

    local attachedPeripherals = peripheral.getNames()

    ---@type table<string,true> printers open to print on
    local availablePrinters = {}
    local totalPrinters = 0
    if not printers then
        for k, v in ipairs(attachedPeripherals) do
            if peripheral.hasType(v, "printer") then
                availablePrinters[v] = true
                totalPrinters = totalPrinters + 1
            end
        end
    else
        for i, v in ipairs(printers) do
            availablePrinters[v] = true
        end
    end

    ---@type table<thread,string|nil>
    local threadFilters = {}

    ---@type thread[]
    local printThreads = {}

    ---@alias printID table
    ---@type table<printID,number> workspace slot this tasks' output was placed into
    local printTasks = setmetatable({}, { __mode = 'k' })

    ---@type table<integer,true|nil>
    local freeSlots = {}
    for i = 1, workspace.size() do
        freeSlots[i] = true
    end
    local totalSlots = workspace.size()

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

    ---@return number used
    ---@return number total
    local function slotUsage()
        local count = 0
        for _ in pairs(freeSlots) do
            count = count + 1
        end
        return totalSlots - count, totalSlots
    end

    ---@type table<string,true|nil>
    local freeTurtles = {}
    local availableTurtles = {}
    local totalTurtles = 0
    ---@type table<string,number>
    local turtleIDs = {}

    local function pingTurtles()
        freeTurtles = {}
        totalTurtles = 0
        if lname then
            freeTurtles[lname] = true
            availableTurtles[#availableTurtles + 1] = lname
            totalTurtles = 1
        end
        local network = require("libs.sprint_network")
        network.wiredModem.transmit(MODEM_PORT, MODEM_PORT, {
            type = "PING",
            destination = "*",
            source = os.getComputerID(),
            protocol = PROTOCOL,
        })
        local tid = os.startTimer(0.2)
        while true do
            local event, side, channel, replyChannel, message, distance = os.pullEvent()
            if event == "timer" and side == tid then
                return
            elseif event == "modem_message" and network.isValid(message) then
                if message.type == "PONG" and not freeTurtles[message.name] then
                    freeTurtles[message.name] = true
                    availableTurtles[#availableTurtles + 1] = message.name
                    totalTurtles = totalTurtles + 1
                    turtleIDs[message.name] = message.source
                end
            end
        end
    end

    ---@return string
    local function allocateTurtle()
        local t = next(freeTurtles)
        if not t then
            os.pullEvent("turtle_freed")
            return allocateTurtle()
        end
        freeTurtles[t] = nil
        return t
    end
    ---@param t string
    local function freeTurtle(t)
        freeTurtles[t] = true
        os.queueEvent("turtle_freed")
    end

    ---@return number used
    ---@return number total
    local function turtleUsage()
        local count = 0
        for _ in pairs(freeTurtles) do
            count = count + 1
        end
        return totalTurtles - count, totalTurtles
    end

    ---@return string
    local function allocatePrinter()
        local printer = next(availablePrinters)
        if not printer then
            os.pullEvent("printer_freed")
            return allocatePrinter()
        end
        availablePrinters[printer] = nil -- set as busy
        return printer
    end

    ---@param printer string
    local function freePrinter(printer)
        availablePrinters[printer] = true
        os.queueEvent("printer_freed")
    end

    ---@return number used
    ---@return number total
    local function printerUsage()
        local count = 0
        for _ in pairs(availablePrinters) do
            count = count + 1
        end
        return totalPrinters - count, totalPrinters
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
    local function addSuppliesFromOutput()
        local inv = abstractInventory({ outputInv })
        inv.pushItems(stockpile, PAPER_ITEM)
        inv.pushItems(stockpile, STRING_ITEM)
        inv.pushItems(stockpile, LEATHER_ITEM)
        for _, v in pairs(DYE_ITEMS) do
            inv.pushItems(stockpile, v)
        end
    end
    ---Empty all printers
    local function emptyPrinters()
        for k, v in pairs(workspace.list()) do
            workspace.pushItems(output, k, nil, nil, nil, { optimal = false })
        end
        local e = {}
        for k, v in pairs(availablePrinters) do
            table.insert(e, function() emptyPrinter(k) end)
        end
        for k, v in ipairs(availableTurtles) do
            table.insert(e, function()
                for i = 1, 16 do
                    peripheral.call(outputInv, "pullItems", v, i)
                end
            end)
        end
        parallel.waitForAll(table.unpack(e))
    end

    local function waitForTask(pid)
        while not printTasks[pid] do
            os.pullEvent("page_print_finished")
        end
    end

    local function epullItems(to, from, fromSlot, amount, toSlot, nbt, options)
        local count = 0
        while to.pullItems(from, fromSlot, amount, toSlot, nbt, options) < amount do
            count = count + 1
            if count > 3 then
                error(("%s.pullItems(%s, %s, %s, %s, %s, %s, %s)"):format(to, from, fromSlot, amount, toSlot, nbt,
                    options))
            end
        end
    end

    local function epushItems(from, to, fromSlot, amount, toSlot, nbt, options)
        local count = 0
        while from.pushItems(to, fromSlot, amount, toSlot, nbt, options) < amount do
            count = count + 1
            if count > 3 then
                error(("%s.pushItems(%s, %s, %s, %s, %s, %s, %s)"):format(from, to, fromSlot, amount, toSlot, nbt,
                    options))
            end
        end
    end

    ---Print a given page
    ---@param name string?
    ---@param page printablePage
    ---@param onlyPage boolean?
    ---@return printID?
    local function printPage(name, page, onlyPage)
        if not next(page) then
            return
        end
        local pid = {}
        printTasks[pid] = nil
        page = clone(page)
        local coro = coroutine.create(function()
            local printer = allocatePrinter()
            local free = allocateSlot()
            -- move paper to the printer
            -- assert(stockpile.pushItems(printer, PAPER_ITEM, 1, PRINTER_INPUT_SLOT) == 1, "Failed to move new paper")
            epushItems(stockpile, printer, PAPER_ITEM, 1, PRINTER_INPUT_SLOT)
            while true do
                -- get the next color
                local col, pg = next(page)
                page[col] = nil
                -- stockpile.pushItems(printer, DYE_ITEMS[col], 1, PRINTER_DYE_SLOT)
                epushItems(stockpile, printer, DYE_ITEMS[col], 1, PRINTER_DYE_SLOT)
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
                    -- assert(workspace.pullItems(printer, PRINTER_OUT_SLOT, 1, free) == 1,
                    --     "Failed to move paper out of printer")
                    epullItems(workspace, printer, PRINTER_OUT_SLOT, 1, free)
                    freePrinter(printer)
                    printTasks[pid] = free
                    os.queueEvent("page_print_finished", pid)
                    if onlyPage then
                        epushItems(workspace, outputInv, free, 1, nil, nil, { optimal = false })
                        freeSlot(free)
                    end
                    return
                end
                epullItems(workspace, printer, PRINTER_OUT_SLOT, 1, free)
                -- assert(workspace.pullItems(printer, PRINTER_OUT_SLOT, 1, free) == 1,
                --     "Failed to move paper out of printer")
                epushItems(workspace, printer, free, 1, PRINTER_INPUT_SLOT)
                -- assert(workspace.pushItems(printer, free, 1, PRINTER_INPUT_SLOT) == 1,
                --     "Failed to move paper into printer")
            end
        end)
        printThreads[#printThreads + 1] = coro
        coroutine.resume(printThreads[#printThreads])
        return pid
    end

    ---@param document printablePage[]
    ---@param copies integer
    ---@return table<colChar,integer>
    local function getRequiredInk(document, copies)
        ---@type table<colChar,integer>
        local requiredColors = {}
        for n, page in pairs(document) do
            for col, _ in pairs(page) do
                requiredColors[col] = (requiredColors[col] or 0) + 1
            end
        end
        for n, c in pairs(requiredColors) do
            requiredColors[n] = c * copies
        end
        return requiredColors
    end

    ---@return number paper
    ---@return number string
    ---@return number leather
    local function getPaperCount()
        local paper = stockpile.getCount(PAPER_ITEM)
        local string = stockpile.getCount(STRING_ITEM)
        local leather = stockpile.getCount(LEATHER_ITEM)
        return paper, string, leather
    end

    ---@param document printablePage[]
    ---@param copies integer
    ---@param book boolean?
    ---@return integer paper
    ---@return integer string
    ---@return integer leather
    local function getRequiredPaper(document, copies, book)
        local requiredPaper = #document * copies
        local requiredString = math.ceil(#document / 6) * copies
        local requiredLeather = book and copies or 0
        if #document == 1 then
            requiredLeather = 0
        end
        return requiredPaper, requiredString, requiredLeather
    end

    local DOCUMENT_LENGTH_LIMIT = 16
    ---Check if we can print a document
    ---@param document printablePage[]
    ---@param copies integer
    ---@param book boolean?
    ---@return boolean success
    ---@return string reason
    local function canPrint(document, copies, book)
        if #document > DOCUMENT_LENGTH_LIMIT then
            return false, ("Too many pages! %d of max %d."):format(#document, DOCUMENT_LENGTH_LIMIT)
        end
        local paper, string, leather = getPaperCount()
        local requiredPaper, requiredString, requiredLeather = getRequiredPaper(document, copies, book)
        if requiredPaper > paper then
            return false, ("Not enough paper.\nHave %d of %d."):format(paper, requiredPaper)
        end
        if #document == 1 then
            requiredString = 0
        end
        if requiredString > string then
            return false, ("Not enough string.\nHave %d of %d."):format(string, requiredString)
        end
        if requiredLeather > leather then
            return false, ("Not enough leather.\nHave %d of %d."):format(leather, copies)
        end

        local requiredColors = getRequiredInk(document, copies)
        for col, req in pairs(requiredColors) do
            local dye = stockpile.getCount(DYE_ITEMS[col])
            if req > dye then
                return false, ("Not enough %s.\nHave %d of %d."):format(DYE_ITEMS[col], dye, req)
            end
        end

        return true, ""
    end

    local turtleSlotLut = {
        5, 6, 7,
        9, 10, 11
    }
    local function tellTurtleToCraftAndWait(name)
        local network = require("libs.sprint_network")
        local turtleID = turtleIDs[name]
        network.wiredModem.transmit(network.MODEM_PORT, network.MODEM_PORT, {
            type = "CRAFT",
            source = os.computerID(),
            destination = turtleID,
            protocol = network.PROTOCOL
        })
        while true do
            local _, side, channel, replyChannel, message, distance = os.pullEvent("modem_message")
            if network.isValid(message) and message.type == "CRAFTED" and message.source == turtleID then
                return
            end
        end
    end
    ---@param title string?
    ---@param document printablePage[]
    ---@param bundleStart integer
    ---@param parentBundle printID?
    ---@param book boolean?
    ---@param last boolean?
    ---@return printID
    local function printBundle(title, document, bundleStart, parentBundle, book, last)
        local tasks = {}
        for pn, page in ipairs(document) do
            local s = title
            if title and (bundleStart > 1 or pn ~= 1) then
                s = s .. " " .. bundleStart + pn - 1
            end
            tasks[#tasks + 1] = printPage(s, page)
        end
        local pid = {}
        printTasks[pid] = nil
        local coro = coroutine.create(function()
            local free
            if not last then
                free = allocateSlot()
            end
            for _, v in ipairs(tasks) do
                waitForTask(v)
            end
            if parentBundle then
                waitForTask(parentBundle)
            end
            local t = allocateTurtle()
            for i, v in ipairs(tasks) do
                epushItems(workspace, t, printTasks[v], 1, turtleSlotLut[i])
                freeSlot(printTasks[v])
            end
            epushItems(stockpile, t, STRING_ITEM, 1, 1)
            -- assert(stockpile.pushItems(t, STRING_ITEM, 1, 1) == 1, "Failed to move string")
            if parentBundle then
                epushItems(workspace, t, printTasks[parentBundle], 1, 3)
                -- workspace.pushItems(t, printTasks[parentBundle], 1, 3)
                freeSlot(printTasks[parentBundle])
            end
            if book then
                epushItems(stockpile, t, LEATHER_ITEM, 1, 2)
                -- assert(stockpile.pushItems(t, LEATHER_ITEM, 1, 2) == 1, "Failed to move leather")
            end
            if t == lname then
                turtle.craft()
            else
                tellTurtleToCraftAndWait(t)
            end
            if last then
                peripheral.call(outputInv, "pullItems", t, 1, 1)
            else
                epullItems(workspace, t, 1, 1, free)
                -- workspace.pullItems(t, 1, 1, free)
                printTasks[pid] = free
            end
            os.queueEvent("page_print_finished", pid)
            freeTurtle(t)
        end)

        printThreads[#printThreads + 1] = coro
        coroutine.resume(printThreads[#printThreads])
        return pid
    end

    ---Print a document
    ---@param title string?
    ---@param document printablePage[]
    ---@param copies integer?
    ---@param book boolean?
    ---@return boolean success
    ---@return string? reason
    local function printDocument(title, document, copies, book)
        copies = copies or 1
        local isPrintable, reason = canPrint(document, copies, book)
        if not isPrintable then
            return isPrintable, reason
        end
        local pages = #document
        for copy = 1, copies do
            local lid
            local lastn = math.floor((pages - 1) / 6) * 6 + 1
            if pages > 1 then
                for n = 1, pages, 6 do
                    local islast = n == lastn
                    lid = printBundle(title, { table.unpack(document, n, n + 5) }, n, lid, book and islast, islast)
                end
            else
                printPage(title, document[1], true)
            end
        end
        return true
    end

    --- Start processing print queue, run this in parallel with your code.
    local function processPrintQueue()
        pingTurtles()
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
                        error(debug.traceback(co, filter):sub(1, 200))
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

    local function getInkLevels()
        local level = {}
        for c, v in pairs(DYE_ITEMS) do
            level[c] = stockpile.getCount(v)
        end
        return level
    end

    local function defrag()
        stockpile.defrag()
    end

    local function refresh()
        stockpile.refreshStorage()
    end

    local function threadCount()
        return #printThreads
    end

    ---@class ColorPrinter
    local colorPrinter = {
        printDocument = printDocument,
        printPage = printPage,
        canPrint = canPrint,
        emptyPrinters = emptyPrinters,
        start = processPrintQueue,
        getInkLevels = getInkLevels,
        getRequiredInk = getRequiredInk,
        getPaperCount = getPaperCount,
        defrag = defrag,
        refresh = refresh,
        slotUsage = slotUsage,
        turtleUsage = turtleUsage,
        printerUsage = printerUsage,
        threadCount = threadCount,
        pingTurtles = pingTurtles,
        getRequiredPaper = getRequiredPaper,
    }
    return colorPrinter
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
    defColor = defColor or "f" -- black default
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
