local sdoc = require("sdoc")
local mbar = require("mbar")

local version = "INDEV"

local running = true

local args = { ... }
if #args < 1 then
    print("sword <fn>")
    return
end


local function load(fn)
    local f = assert(fs.open(fn, "r"))
    local s = f.readAll()
    f.close()
    return s
end

local WIDTH, HEIGHT = 25, 21
local PHEIGHT = HEIGHT + 2

local tw, th = term.getSize()
local win = window.create(term.current(), 1, 1, tw, th)
mbar.setWindow(win)

local pageX = math.floor((tw - WIDTH) / 2)
local scrollOffset = 1
local documentString = load(args[1])
local document = sdoc.decode(documentString)
local a, b
local cursor = 1
local blit = sdoc.render(document, a, b)
local documentUpdated = false
local documentUpdatedSinceSnapshot = false
---@type {state:string,cursor:integer}[]
local undoStates = { { state = documentString, cursor = cursor } }

local writeToDocument

local openButton = mbar.button("Open")
local saveButton = mbar.button("Save")
local newButton = mbar.button("New")
local quitButton = mbar.button("Quit", function()
    running = false
    return true
end)

local filesm = mbar.buttonMenu({ openButton, saveButton, newButton, quitButton })

local fileButton = mbar.button("File", nil, filesm)
local charMenu = mbar.charMenu(function(self, ch)
    writeToDocument(ch)
end)
local colorMenu = mbar.colorMenu(function(self)
    charMenu.color = self.selectedCol
    if a and b then
        documentString = document:setColor(self.selectedChar, a, b)
        document = sdoc.decode(documentString)
        documentUpdated = true
    end
end)
local alignments = { "l", "c", "r" }
local alignmentMenu = mbar.radialMenu({ "Left", "Center", "Right" }, function(self)
    local value = alignments[self.selected]
    documentString = document:setAlignment(cursor, value)
    document = sdoc.decode(documentString)
    documentUpdated = true
end)
local colorButton = mbar.button("Color", nil, colorMenu)
local insertMenu = mbar.buttonMenu {
    mbar.button("New Page", function(entry)
        documentString = document:insertPage(cursor)
        document = sdoc.decode(documentString)
        documentUpdated = true
    end),
    mbar.button("Character", nil, charMenu)
}
local undoButton = mbar.button("Undo", function(entry)
    local str = table.remove(undoStates, 2)
    if str then
        documentString = str.state
        document = sdoc.decode(documentString)
        documentUpdated = true
        cursor = str.cursor
    end
end)
local editMenu = mbar.buttonMenu {
    colorButton,
    mbar.button("Alignment", nil, alignmentMenu),
    mbar.button("Insert", nil, insertMenu),
    undoButton
}
local editButton = mbar.button("Edit", nil, editMenu)
local helpButton = mbar.button("Help")

local bar = mbar.bar({ fileButton, editButton, helpButton })
bar.shortcut(saveButton, keys.s, true)
bar.shortcut(quitButton, keys.q, true)
bar.shortcut(undoButton, keys.z, true)


---Writes the string s to the a, b area of the document, updating the selection as necessary
function writeToDocument(s)
    if a and b then
        a, b = math.min(a, b), math.max(a, b)
        documentString = document:remove(a, b)
        document = sdoc.decode(documentString)
        a, b = nil, nil
    end
    documentString = document:insertAt(cursor, s, colorMenu.selectedChar)
    cursor = cursor + #s
    document = sdoc.decode(documentString)
    documentUpdated = true
end

---@param idx integer
---@return integer x
---@return integer y
local function documentIndexToScreen(idx)
    local info = document.indicies[idx]
    assert(info, ("%d %d %d"):format(idx, #document.indicies, #document.editable.content[1]))
    local y = (info.page - 1) * PHEIGHT + info.line + 4 - scrollOffset
    local lineX = 1
    if document.pages[info.page][info.line] then
        lineX = document.pages[info.page][info.line].lineX
    end
    local x = info.col + pageX + lineX - 2
    return x, y
end

local function render()
    win.setVisible(false)
    if documentUpdated then
        blit = sdoc.render(document, a, b)
        documentUpdated = false
        documentUpdatedSinceSnapshot = true
    end
    win.clear()
    scrollOffset = math.max(1, scrollOffset)
    local maxScroll = #document.pages * PHEIGHT - th + 4
    scrollOffset = math.min(maxScroll, scrollOffset)
    local startPage = math.max(1, math.floor((scrollOffset - 2) / PHEIGHT) + 1)
    local endPage = math.min(startPage + math.ceil(th / PHEIGHT), #document.pages)
    for i = startPage, endPage do
        local y = ((i - 1) * PHEIGHT) + 5 - scrollOffset
        sdoc.blitOn(blit, i, pageX, y, win)
    end
    bar.render()
    win.setCursorBlink(true)
    win.setTextColor(colors.black)
    win.setCursorPos(documentIndexToScreen(cursor))
    win.setVisible(true)
end

---@param x integer
---@param y integer
---@return integer?
local function screenToDocumentIndex(x, y)
    local dx, dy
    local page = math.floor((y + scrollOffset - 4) / PHEIGHT) + 1
    local line = y + scrollOffset - 4 - (page - 1) * PHEIGHT
    if line < 1 or line > HEIGHT then
        return
    end
    local chn
    if x < pageX or x >= pageX + WIDTH then
        return
    end
    local lineX = 1
    if document.pages[page][line] then
        lineX = document.pages[page][line].lineX
    end
    chn = x - pageX + 2 - lineX
    -- local latestLine = line
    -- while not document.indexlut[page][latestLine] do
    --     if latestLine <= 1 then return end
    --     latestLine = latestLine - 1
    -- end
    -- local latestChn = chn
    -- while not document.indexlut[page][latestLine][latestChn] do
    --     if latestChn <= 1 then return end
    --     latestChn = latestChn - 1
    -- end
    return document.indexlut[page][line][chn]
end

local alignmentReverseLUT = {
    l = 1,
    c = 2,
    r = 3
}
local function moveCursor(idx)
    cursor = math.max(1, math.min(#document.editable.content[1] + 1, idx))
    local info = document.indicies[cursor]
    if info and document.pages[info.page][info.line] then
        local alignment = document.pages[info.page][info.line].alignment
        alignmentMenu.selected = alignmentReverseLUT[alignment]
        local colch = document.editable.content[2]:sub(cursor, cursor)
        if colch ~= "" then
            colorMenu.setSelected(colch)
        end
    end
end

local function deleteSelection()
    if a and b then
        a, b = math.min(a, b), math.max(a, b)
        documentString = document:remove(a, b)
        document = sdoc.decode(documentString)
        moveCursor(a)
        a, b = nil, nil
    end
end

local function mainLoop()
    while running do
        render()
        local e = { os.pullEvent() }
        if not bar.onEvent(e) then
            -- event not consumed, do something with it
            if e[1] == "mouse_scroll" then
                scrollOffset = scrollOffset + e[2]
            elseif e[1] == "mouse_click" then
                local idx = screenToDocumentIndex(e[3], e[4])
                a, b = nil, nil
                moveCursor(idx or cursor)
                documentUpdated = true
            elseif e[1] == "mouse_drag" then
                local idx = screenToDocumentIndex(e[3], e[4])
                a = cursor
                b = idx or b or cursor
                documentUpdated = true
            elseif e[1] == "key" then
                if e[2] == keys.backspace then
                    if not (a or b) then
                        cursor = cursor - 1
                        if cursor < 1 then
                            cursor = 1
                        else
                            a = cursor
                            b = cursor
                        end
                    end
                    deleteSelection()
                    documentUpdated = true
                elseif e[2] == keys.delete then
                    if not (a or b) then
                        a = cursor
                        b = cursor
                    end
                    deleteSelection()
                    documentUpdated = true
                elseif e[2] == keys.left then
                    moveCursor(cursor - 1)
                elseif e[2] == keys.right then
                    moveCursor(cursor + 1)
                elseif e[2] == keys.enter then
                    deleteSelection()
                    -- moveCursor(cursor - 1)
                    writeToDocument("\n")
                    -- moveCursor(cursor + 1)
                end
            elseif e[1] == "char" then
                deleteSelection()
                -- moveCursor(cursor - 1)
                writeToDocument(e[2])
                -- moveCursor(cursor + 1)
            end
        end
    end
end

local function run()
    parallel.waitForAny(
        mainLoop,
        function()
            local tid = os.startTimer(2)
            while true do
                local _, id = os.pullEvent("timer")
                if id == tid then
                    if documentUpdatedSinceSnapshot then
                        documentUpdatedSinceSnapshot = false
                        table.insert(undoStates, 1, { state = documentString, cursor = cursor })
                        undoStates[5] = nil
                    end
                    tid = os.startTimer(2)
                end
            end
        end

    )
end

local ok, err = xpcall(mainLoop, debug.traceback)
term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)
print(("Thank you for using ShrekWord v%s"):format(version))

if not ok then
    term.setTextColor(colors.red)
    print("Exited with error:")
    print(err)
end
