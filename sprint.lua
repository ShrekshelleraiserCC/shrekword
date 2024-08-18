local sdoc = require("sdoc")
local mbar = require("mbar")
local printer = require("printer")

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

local aboutButton = mbar.button("About", function(entry)
    local s = ("ShrekPrint v%s\nMbar v%s\nSdoc v%s"):format(version, mbar._VERSION, sdoc._VERSION)

    if buildVersion ~= "##VERSION" then
        s = s .. ("\nBuild %s"):format(buildVersion)
    end
    mbar.popup("About", s, { "Close" }, 15)
    bar.resetKeys()
end)
bar = mbar.bar { aboutButton }

while true do
    win.setVisible(false)
    win.clear()
    bar.render()
    win.setVisible(true)
    local e = { os.pullEvent() }
    bar.onEvent(e)
end
