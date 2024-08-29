local sdoc = require("libs.sdoc")
local mbar = require("libs.mbar")
local printer = require("libs.printer")
local scolors = require("libs.scolors")
local network = require("libs.sprint_network")
local supdate = require("libs.supdate")

local rednetModem
local hostname = "TEST"

local updateUrl = "https://github.com/ShrekshelleraiserCC/shrekword/releases/latest/download/sprint.lua"
local version = "1.0.3"
local buildVersion = '##VERSION'

local tw, th = term.getSize()
local win = window.create(term.current(), 1, 1, tw, th)

local function saveList(fn, t)
    local f = assert(fs.open(fn, "w"))
    for i, v in ipairs(t) do
        f.writeLine(v)
    end
    f.close()
end
local function loadList(fn)
    local t = {}
    local f = assert(fs.open(fn, "r"))
    repeat
        local value = f.readLine()
        t[#t + 1] = value
    until not value
    f.close()
    return t
end

local WORKSPACE_CHEST_FN = "workspace.chests"
local STOCKPILE_CHEST_FN = "stockpile.chests"
local OUTPUT_CHEST_FN = "output.chests"

local chestList = {}
peripheral.find("inventory", function(name, wrapped)
    chestList[#chestList + 1] = name
    return true
end)

local chestCompletion = function(str)
    return require("cc.completion").choice(str, chestList, false)
end

local function getList(str)
    local t = {}
    print(str)
    print("Leave blank to finish.")
    while true do
        term.write("? ")
        local value = read(nil, nil, chestCompletion)
        if value == "" then
            term.write("Enter again to exit: ")
            value = read()
            if value == "" then
                return t
            end
        elseif peripheral.isPresent(value) then
            t[#t + 1] = value
        end
    end
end
settings.define("sprint.hostname", { type = "string", description = "Rednet hostname" })
settings.define("sprint.modem", { type = "string", description = "Modem to open rednet on" })
if not settings.get("sprint.hostname") then
    print("Enter a hostname:")
    local hn = read()
    settings.set("sprint.hostname", hn)
    settings.save()
end
hostname = settings.get("sprint.hostname")
if not settings.get("sprint.modem") then
    local modems = {}
    peripheral.find("modem", function(name, wrapped)
        modems[#modems + 1] = name
        return true
    end)
    assert(#modems > 0, "No modems attached!")
    print("Enter a modem for rednet:")
    repeat
        local modemSide = read(nil, nil, function(partial)
            return require("cc.completion").choice(partial, modems, false)
        end)
        rednetModem = modemSide
    until peripheral.hasType(modemSide, "modem")
    settings.set("sprint.modem", rednetModem)
    settings.save()
end
rednetModem = settings.get("sprint.modem")
if not fs.exists(WORKSPACE_CHEST_FN) then
    local l = getList("Enter inventories to use as a workspace:")
    saveList(WORKSPACE_CHEST_FN, l)
end
if not fs.exists(STOCKPILE_CHEST_FN) then
    local l = getList("Enter inventories to use for storage:")
    saveList(STOCKPILE_CHEST_FN, l)
end
if not fs.exists(OUTPUT_CHEST_FN) then
    print("Enter inventory to use for output:")
    term.write("? ")
    local c = read(nil, nil, chestCompletion)
    saveList(OUTPUT_CHEST_FN, { c })
end

settings.define("sprint.checkForUpdates", { type = "boolean", description = "Check for updates on startup" })
if settings.get("sprint.checkForUpdates") == nil then
    print("Check for updates on startup?")
    settings.set("sprint.checkForUpdates", read():sub(1, 1):lower() == "y")
    settings.save()
end

local rednetEnabled = false
if rednetModem then
    rednet.open(rednetModem)
    rednet.host(network.PROTOCOL, hostname)
    rednetEnabled = true
end

local p = printer.printer(
    loadList(STOCKPILE_CHEST_FN),
    loadList(WORKSPACE_CHEST_FN),
    loadList(OUTPUT_CHEST_FN)[1]
)

local bar
mbar.setWindow(win)

local running = true
local quitButton = mbar.button("Quit", function(entry)
    running = false
end)

---@return string?
---@return Document?
local function openDocument(fn)
    if not fs.exists(fn) then
        mbar.popup("Error", ("File '%s' does not exist."):format(fn), { "Ok" }, 15)
        bar.resetKeys()
        return
    end
    if fs.isDir(fn) then
        mbar.popup("Error", "Directories are not documents!", { "Ok" }, 15)
        bar.resetKeys()
        return
    end
    local f = assert(fs.open(fn, "r"))
    local s = f.readAll()
    f.close()
    local ok, err = pcall(sdoc.decode, s)
    if ok then
        return s, err
    end
    mbar.popup("Error", err --[[@as string]], { "Ok :)", "Ok :(" }, 20)
    bar.resetKeys()
    return
end

---@param doc Document
local function printPopup(doc)
    local toprint, err = printer.convertBlit(doc.blit)
    if not toprint then
        mbar.popup("Error", err or "", { "Ok" }, 15)
        return
    end
    local copies = tonumber(mbar.popupRead("Copies?", 15, nil, nil, "1"))
    if not copies then
        return
    end
    local book = #doc.pages > 1 and mbar.popup("Books?", "Bundle each copy into a book", { "No", "Yes" }, 20) == 2
    local canPrint, reason = p.canPrint(toprint, copies, book)
    if not canPrint then
        mbar.popup("Cannot Print!", reason, { "Ok" }, 15)
        return
    end
    local doPrint = mbar.popupPrint(p.getRequiredInk(toprint, copies), p.getRequiredPaper(toprint, copies, book))
    if not doPrint then
        return
    end
    local ok, err = p.printDocument(doc.editable.title or "Untitled Document", toprint, copies, book)
    if not ok then
        mbar.popup("Error", err or "", { "Ok" }, 15)
        return
    end
end
local printButton = mbar.button("Print...", function(entry)
    local fn = mbar.popupRead("Open", 15, nil, function(str)
        local list = require("cc.shell.completion").file(shell, str)
        for i = #list, 1, -1 do
            if not (list[i]:match("/$") or list[i]:match("%.sdoc$")) then
                table.remove(list, i)
            end
        end
        return list
    end)
    bar.resetKeys()
    if fn then
        local s, doc = openDocument(fn)
        if doc then
            printPopup(doc)
        end
    end
end)
local updateButton = mbar.button("Update", function(entry)
    supdate.checkUpdatePopup(updateUrl, version, buildVersion)
end)
local fileMenu = mbar.buttonMenu { printButton, updateButton, quitButton }
local fileButton = mbar.button("File", nil, fileMenu)
local aboutButton = mbar.button("About", function(entry)
    local s = ("ShrekPrint v%s\nMbar v%s\nSdoc v%s"):format(version, mbar._VERSION, sdoc._VERSION)

    if buildVersion ~= "##VERSION" then
        s = s .. ("\nBuild %s"):format(buildVersion)
    end
    mbar.popup("About", s, { "Close" }, 15)
    bar.resetKeys()
end)
local refreshButton = mbar.button("Refresh", p.refresh)
local defragButton = mbar.button("Defrag", p.defrag)
local emptyButton = mbar.button("Empty", p.emptyPrinters)
local turtleButton = mbar.button("Rescan Turtles", p.pingTurtles)
local inventoryMenu = mbar.buttonMenu { refreshButton, defragButton, emptyButton, turtleButton }
local inventoryButton = mbar.button("Inventory", nil, inventoryMenu)
bar = mbar.bar { fileButton, inventoryButton, aboutButton }
bar.shortcut(quitButton, keys.q, true)

local function drawInkLevels(x, y)
    local levels = p.getInkLevels()
    win.setTextColor(colors.gray)
    mbar.box(x, y, 12, 4)
    for i = 0, 15 do
        local color = 2 ^ i
        local ch = colors.toBlit(color)
        local level = levels[ch]
        local dx = (i % 4) * 3
        local dy = math.floor(i / 4)
        win.setCursorPos(x + dx, y + dy)
        local s = ("%3d"):format(level)
        if level > 999 then
            s = "+++"
        end
        win.blit(s, scolors.contrastBlitLut[ch]:rep(3), ch:rep(3))
    end
end

local function fill(x, y, w, h)
    for dy = 1, h do
        win.setCursorPos(x, y + dy - 1)
        win.write((" "):rep(w))
    end
end

local function drawPrinterStock()
    win.setTextColor(colors.black)
    win.setBackgroundColor(colors.lightGray)
    fill(2, 3, 14, 10)
    win.setCursorPos(3, 3)
    win.write("Ink Level:")
    drawInkLevels(3, 5)
    win.setTextColor(colors.black)
    win.setBackgroundColor(colors.lightGray)
    local paper, string, leather = p.getPaperCount()
    win.setCursorPos(3, 10)
    win.write(("Paper: %d"):format(paper))
    win.setCursorPos(3, 11)
    win.write(("String: %d"):format(string))
    win.setCursorPos(3, 12)
    win.write(("Leather: %d"):format(leather))
    win.setTextColor(colors.gray)
    mbar.corner(2, 3, 14, 10, true)
end

local function centerWrite(x, y, w, str)
    local dx = math.floor((w - #str) / 2)
    win.setCursorPos(x + dx, y)
    win.write(str)
end

local function drawProgressbar(x, y, label, used, total)
    local w = 20
    win.setTextColor(colors.black)
    win.setBackgroundColor(colors.lightGray)
    centerWrite(x, y, w, label)
    win.setCursorPos(x + 1, y + 1)
    win.setTextColor(colors.white)
    win.setBackgroundColor(colors.white)
    local i = math.floor(18 * (used / total))
    win.write((" "):rep(i))
    win.setBackgroundColor(colors.lightGray)
    win.write(("\127"):rep(w - 2 - i))
    win.setTextColor(colors.black)
    win.setCursorPos(x + 1, y + 2)
    win.write(used)
    win.setCursorPos(x + w - #tostring(total) - 1, y + 2)
    win.write(total)
end

local function drawPrinterOperationInfo()
    win.setTextColor(colors.black)
    win.setBackgroundColor(colors.lightGray)
    fill(18, 3, 20, 10)
    drawProgressbar(18, 3, "Printers", p.printerUsage())
    drawProgressbar(18, 6, "Slots", p.slotUsage())
    drawProgressbar(18, 9, "Turtles", p.turtleUsage())
    win.setCursorPos(18, 12)
    win.write(("Threads: %d"):format(p.threadCount()))
    win.setTextColor(colors.gray)
    mbar.corner(18, 3, 20, 10, true)
end

local function render()
    win.setVisible(false)
    win.setTextColor(colors.white)
    win.setBackgroundColor(colors.black)
    win.clear()
    drawPrinterStock()
    drawPrinterOperationInfo()
    bar.render()
    win.setVisible(true)
end

local function handleRednet(id, msg)
    if type(msg) ~= "table" then
        return
    end
    if msg.type == "DOCINFO" then
        local ok, document = pcall(sdoc.decode, msg.document)
        if not ok then
            rednet.send(id, { type = "DOCINFO", result = false, reason = document }, network.PROTOCOL)
            return
        end
        local toprint, err = printer.convertBlit(document.blit)
        if not toprint then
            rednet.send(id, { type = "DOCINFO", result = false, reason = err }, network.PROTOCOL)
            return
        end
        local ink = p.getRequiredInk(toprint, msg.copies)
        local can, reason = p.canPrint(toprint, msg.copies, msg.asBook)
        local paper, string, leather = p.getRequiredPaper(toprint, msg.copies, msg.asBook)
        rednet.send(id,
            {
                type = "DOCINFO",
                result = can,
                reason = reason,
                ink = ink,
                paper = paper,
                string = string,
                leather =
                    leather
            }, network.PROTOCOL)
    elseif msg.type == "PRINT" then
        local ok, document = pcall(sdoc.decode, msg.document)
        if not ok then
            rednet.send(id, { type = "PRINT", result = false, reason = document }, network.PROTOCOL)
            return
        end
        local toprint, err = printer.convertBlit(document.blit)
        if not toprint then
            rednet.send(id, { type = "PRINT", result = false, reason = err }, network.PROTOCOL)
            return
        end
        local can, reason = p.printDocument(document.editable.title or "Untitled Document", toprint, msg.copies,
            msg.asBook)
        rednet.send(id, { type = "PRINT", result = can, reason = reason }, network.PROTOCOL)
    elseif msg.type == "INFO" then
        local inkLevels = p.getInkLevels()
        local paper, string, leather = p.getPaperCount()
        rednet.send(id,
            { type = "INFO", ink = inkLevels, paper = paper, string = string, leather = leather, name = hostname },
            network.PROTOCOL)
    end
end

local function rednetThread()
    while true do
        local id, msg = rednet.receive(network.PROTOCOL)
        if rednetEnabled then
            handleRednet(id, msg)
        end
    end
end

parallel.waitForAny(
    function()
        render()
        if settings.get("sprint.checkForUpdates") then
            supdate.checkUpdatePopup(updateUrl, version, buildVersion)
        end
        while running do
            render()
            local e = { os.pullEvent() }
            bar.onEvent(e)
        end
    end,
    p.start,
    rednetThread
)
term.clear()
term.setCursorPos(1, 1)
