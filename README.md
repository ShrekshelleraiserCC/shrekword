# ShrekWord and ShrekPrint
ShrekWord is a ComputerCraft "word"-like document editing program. It includes a nice menu bar, support for alignments, and text colors. It also includes built in support for printing to a printer running ShrekPrint over rednet.

ShrekPrint is my high speed 16 color printing software designed for use with my ShrekDoc format. Install it on an advanced crafty turtle connected to a network with chests and printers. When running it for the first time you will be prompted for various things. The hostname is whatever you want the printer to identify as on rednet. The workspace chests are chests to use for intermediate storage of documents while they're being printed. The stockpile chests are, well, a stockpile of resources like ink and paper. And the output is a single inventory which finished documents (and scraps when the printer is emptied) will be deposited into. Attach as many printers as you'd like, and optionally additional crafty turtles running `spcrafter.lua`.

## Installation
Download the latest versions of ShrekWord and ShrekPrint from the releases tab.

## ShrekDoc
ShrekDoc is a new ComputerCraft document format that I have created. A document is any string with a header of the format `shrekdoc-v01w00h00mR:`, where there are three 2 digit numbers representing the version (v), width (w), and height (h) of the document. There is also `mR` or `mS`, which represents "raw mode" and "serialized mode" for the document. In raw mode the data is interpreted as is, but in serialized mode anything following the header is passed into `textutils.unserialize` before decoding. This is useful for using lua escape sequences for the control character (`shrekdoc-v01w25h21mS"Hello \160caWorld!\160r"`), but any documents saved using ShrekWord will be saved in raw mode.

# Mbar
Mbar is a library I have written to make simple menu bars for programs. Use any program on a modern operating system, and somewhere it has a menu bar (might be hidden in some web browser based applications), this is a recreation of those.

To make use of the library download it (`libs/mbar.lua`) and place it into your computer directory. Here is an example program:

```lua
local mbar = require("mbar")

local win = window.create(term.current(), 1, 1, term.getSize())
-- before using you must set the window for mbar to draw to
mbar.setWindow(win)

local running = true
local openButton = mbar.button("Open", function(entry)
    -- do stuff
end)
local quitButton = mbar.button("Quit", function(entry)
    running = false
end)
local fileMenu = mbar.buttonMenu {
    openButton,
    quitButton
}
local fileButton = mbar.button("File", nil, fileMenu)

local aboutButton = mbar.button("About", function(entry)
    -- you get it by now
end)

local bar = mbar.bar {
    fileButton,
    aboutButton
}
-- setup control + q to quit
bar.shortcut(quitButton, keys.q, true)

while running do
    win.setVisible(false)
    win.clear()
    bar.render()
    win.setVisible(true)
    local e = { os.pullEvent() }
    if not bar.onEvent(e) then
        -- this returns true when the event is consumed
        -- so via negating it you can take action for
        -- any clicks / etc that are not consumed by the bar and menus
    end
end
```