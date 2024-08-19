local sdoc = require("sdoc")
local mbar = require("mbar")
local printer = require("printer")
local scolors = require("scolors")

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
local fileMenu = mbar.buttonMenu { quitButton }
local fileButton = mbar.button("File", nil, fileMenu)
local aboutButton = mbar.button("About", function(entry)
    local s = ("ShrekPrint v%s\nMbar v%s\nSdoc v%s"):format(version, mbar._VERSION, sdoc._VERSION)

    if buildVersion ~= "##VERSION" then
        s = s .. ("\nBuild %s"):format(buildVersion)
    end
    mbar.popup("About", s, { "Close" }, 15)
    bar.resetKeys()
end)
bar = mbar.bar { fileButton, aboutButton }
bar.shortcut(quitButton, keys.q, true)

local function drawInkLevels(x, y)
    local levels = p.getInkLevels()
    win.setTextColor(colors.gray)
    mbar.box(x, y, 8, 4)
    for i = 0, 15 do
        local color = 2 ^ i
        local ch = colors.toBlit(color)
        local level = levels[ch]
        local dx = (i % 4) * 2
        local dy = math.floor(i / 4)
        win.setCursorPos(x + dx, y + dy)
        local s = ("%02d"):format(level)
        if level > 99 then
            s = "++"
        end
        win.blit(s, scolors.contrastBlitLut[ch]:rep(2), ch:rep(2))
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
    drawInkLevels(4, 5)
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

local function drawPrinterOperationInfo()
    win.setTextColor(colors.black)
    win.setBackgroundColor(colors.lightGray)
    fill(18, 3, 20, 10)
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

while running do
    render()
    local e = { os.pullEvent() }
    bar.onEvent(e)
end
term.clear()
term.setCursorPos(1, 1)
