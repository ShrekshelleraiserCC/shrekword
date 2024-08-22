local sdoc = require("sdoc")
local mbar = require("mbar")
local printer = require("printer")
local scolors = require("scolors")
local network = require("sprint_network")


local wirelessModem = peripheral.find("modem", function(name, wrapped)
    return wrapped.isWireless()
end) --[[@as Modem?]]


local hostname = "TEST"
local rednetEnabled = false
if wirelessModem then
    rednet.open(peripheral.getName(wirelessModem))
    rednet.host(network.PROTOCOL, hostname)
    rednetEnabled = true
end

local version = "INDEV"
local buildVersion = '##VERSION'

local tw, th = term.getSize()
local win = window.create(term.current(), 1, 1, tw, th)

local p = printer.printer(
    { "minecraft:chest_3", "minecraft:chest_4" },
    { "minecraft:chest_1", "minecraft:chest_2" },
    "minecraft:chest_0"
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
            local toprint, err = printer.convertBlit(doc.blit)
            if toprint then
                local ok, err = p.printDocument("TEST", toprint, 12, true)
                if not ok then
                    mbar.popup("Error", err or "", { "Ok" }, 15)
                end
            else
                mbar.popup("Error", err or "", { "Ok" }, 15)
            end
        end
    end
end)
local fileMenu = mbar.buttonMenu { printButton, quitButton }
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
        local can, reason = p.canPrint(toprint, msg.copies, msg.asBook)
        rednet.send(id, { type = "DOCINFO", result = can, reason = reason }, network.PROTOCOL)
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
        rednet.send(id, { type = "INFO", ink = inkLevels, paper = paper, string = string, leather = leather },
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
