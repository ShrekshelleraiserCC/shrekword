local sdoc = require("sdoc")
local mbar = require("mbar")

local version = "INDEV"
local buildVersion = '##VERSION'

if buildVersion ~= "##VERSION" then
    version = version .. "-" .. buildVersion
end

local running = true

local args = { ... }

---@type number?,number?
local a, b
---@type number
local cursor = 1
---@type string?
local documentFilename
---@type string
local documentString
---@type Document
local document
local documentUpdateRender = false
local documentUpdatedSinceSnapshot = false
local documentUpdatedSinceSave = false
local bar
local clipboard = ""
local copy, paste

local WIDTH, HEIGHT
local PHEIGHT
local pageX

local tw, th = term.getSize()
local win = window.create(term.current(), 1, 1, tw, th)
mbar.setWindow(win)

local function updateDocumentSize(w, h)
    WIDTH, HEIGHT = w, h
    PHEIGHT = HEIGHT + 2
    pageX = math.max(1, math.floor((tw - WIDTH) / 2))
end
updateDocumentSize(25, 21)

local function updateTermSize()
    tw, th = term.getSize()
    win.reposition(1, 1, tw, th)
    updateDocumentSize(WIDTH, HEIGHT)
end


---Mark document for re-render
local function documentRenderUpdate()
    documentUpdateRender = true
end
---Mark document for re-render + unsaved changes notification
local function documentContentUpdate()
    documentUpdateRender = true
    documentUpdatedSinceSave = true
    documentUpdatedSinceSnapshot = true
end

local function openDocument(fn)
    if not fs.exists(fn) then
        mbar.popup("Error", ("File '%s' does not exist."):format(fn), { "Ok" }, 15)
        bar.resetKeys()
        return false
    end
    if fs.isDir(fn) then
        mbar.popup("Error", "Directories are not documents!", { "Ok" }, 15)
        bar.resetKeys()
        return false
    end
    local f = assert(fs.open(fn, "r"))
    local s = f.readAll()
    f.close()
    local ok, err = pcall(sdoc.decode, s)
    if ok then
        documentString = s
        document = err
        documentFilename = fn
        updateDocumentSize(document.pageWidth, document.pageHeight)
        documentRenderUpdate()
        cursor = 1
        a, b = nil, nil
        return true
    end
    mbar.popup("Error", err --[[@as string]], { "Ok :)", "Ok :(" }, 20)
    bar.resetKeys()
    return false
end
---@return boolean continue
local function unsavedDocumentPopup()
    if documentUpdatedSinceSave then
        local option = mbar.popup("Warning", "You have unsaved changes. Discard these?", { "Yes", "No" },
            20)
        bar.resetKeys()
        return option == 1
    end
    return true
end
local function newDocument()
    if not unsavedDocumentPopup() then
        return
    end
    documentString = "shrekdoc-v01w25h21mR:"
    document = sdoc.decode(documentString)
    updateDocumentSize(document.pageWidth, document.pageHeight)
    documentRenderUpdate()
    cursor = 1
    documentFilename = nil
end

if args[1] then
    if not openDocument(args[1]) then
        newDocument()
    end
else
    newDocument()
end

local scrollOffset = 1
local blit = sdoc.render(document, a, b)
---@type {state:string,cursor:integer}[]
local undoStates = { { state = documentString, cursor = cursor } }

local writeToDocument
local openButton = mbar.button("Open", function(entry)
    if not unsavedDocumentPopup() then
        return
    end
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
        openDocument(fn)
    end
end)
local function saveAsRaw(fn)
    local f = assert(fs.open(fn, "w"))
    f.write(documentString)
    f.close()
end
local function saveAs(fn)
    saveAsRaw(fn)
    documentUpdatedSinceSave = false
end
local saveAsButton = mbar.button("Save As", function(entry)
    local fn = mbar.popupRead("Save As", 15)
    bar.resetKeys()
    if fn then
        saveAs(fn)
        documentFilename = fn
    end
end)
local saveButton = mbar.button("Save", function(entry)
    if not documentFilename then
        saveAsButton.click()
    else
        saveAs(documentFilename)
    end
end)
local newButton = mbar.button("New", newDocument)
local quitButton = mbar.button("Quit", function()
    if not unsavedDocumentPopup() then
        return
    end
    running = false
    return true
end)

local filesm = mbar.buttonMenu {
    newButton,
    mbar.divider(),
    openButton,
    mbar.divider(),
    saveButton,
    saveAsButton,
    mbar.divider(),
    quitButton
}

local fileButton = mbar.button("File", nil, filesm)
local charMenu = mbar.charMenu(function(self, ch)
    writeToDocument(ch)
end)

-- EDIT MENU

local colorMenu = mbar.colorMenu(function(self)
    charMenu.color = self.selectedCol
    if a and b then
        documentString = document:setColor(self.selectedChar, a, b)
        document = sdoc.decode(documentString)
        documentContentUpdate()
    end
end)
local alignments = { "l", "c", "r" }
local alignmentMenu = mbar.radialMenu({ "Left", "Center", "Right" }, function(self)
    local value = alignments[self.selected]
    if a and b then
        cursor = math.min(a, b)
    end
    documentString = document:setAlignment(cursor, value, b)
    document = sdoc.decode(documentString)
    documentContentUpdate()
end)
local colorButton = mbar.button("Color", nil, colorMenu)
local insertMenu = mbar.buttonMenu {
    mbar.button("Character", nil, charMenu),
    mbar.button("New Page", function(entry)
        documentString = document:insertPage(cursor)
        document = sdoc.decode(documentString)
        documentContentUpdate()
    end),
}
local undoButton = mbar.button("Undo", function(entry)
    local str = table.remove(undoStates, 2)
    if str then
        documentString = str.state
        document = sdoc.decode(documentString)
        updateDocumentSize(document.pageWidth, document.pageHeight)
        documentContentUpdate()
        cursor = str.cursor
    end
end)
local selectAllButton = mbar.button("Select All", function(entry)
    a = 1
    b = #document.editable.content[1]
    documentRenderUpdate()
end)
local copyButton = mbar.button("Copy", function(entry)
    copy()
end)
local pasteButton = mbar.button("Paste", function(entry)
    paste()
end)
local editMenu = mbar.buttonMenu {
    mbar.button("Alignment", nil, alignmentMenu),
    colorButton,
    mbar.divider(),
    mbar.button("Insert", nil, insertMenu),
    undoButton,
    mbar.divider(),
    selectAllButton,
    copyButton,
    pasteButton
}
local editButton = mbar.button("Edit", nil, editMenu)

-- VIEW MENU

local drawRuler = true
local drawRulerButton = mbar.toggleButton("Ruler", function(entry)
    drawRuler = entry.value
end)
local drawStatusBar = true
local drawStatusBarButton = mbar.toggleButton("Status Bar", function(entry)
    drawStatusBar = entry.value
end)
drawStatusBarButton.setValue(true)
drawRulerButton.setValue(true)
local drawCharInfo = false
local drawCharInfoButton = mbar.toggleButton("Character Info", function(entry)
    drawCharInfo = entry.value
end)
local renderNewlines = false
local renderNewlineButton = mbar.toggleButton("New Lines", function(entry)
    renderNewlines = entry.value
    documentRenderUpdate()
end)
local renderNewpages = false
local renderNewpageButton = mbar.toggleButton("New Pages", function(entry)
    renderNewpages = entry.value
    documentRenderUpdate()
end)
local debugViewMenu = mbar.buttonMenu {
    renderNewpageButton,
    drawCharInfoButton
}
local debugViewButton = mbar.button("Debug", nil, debugViewMenu)
local viewMenu = mbar.buttonMenu({
    drawRulerButton,
    drawStatusBarButton,
    mbar.divider(),
    renderNewlineButton,
    debugViewButton
})
local viewButton = mbar.button("View", nil, viewMenu)
local helpButton = mbar.button("About", function()
    win.setVisible(true)
    mbar.popup("About", ("ShrekWord v%s"):format(version), { "Close" }, 20)
    bar.resetKeys()
    win.setVisible(false)
end)

bar = mbar.bar({ fileButton, editButton, viewButton, helpButton })
bar.shortcut(saveButton, keys.s, true)
bar.shortcut(quitButton, keys.q, true)
bar.shortcut(undoButton, keys.z, true)
bar.shortcut(newButton, keys.n, true)
bar.shortcut(openButton, keys.o, true)
bar.shortcut(selectAllButton, keys.a, true)

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
    documentContentUpdate()
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
    assert(lineX, ("%d, %d, %d"):format(idx, info.page, info.line))
    local x = info.col + pageX + lineX - 2
    return x, y
end

local function render()
    win.setVisible(false)
    win.setTextColor(colors.white)
    win.setBackgroundColor(colors.black)
    if documentUpdateRender then
        blit = sdoc.render(document, a, b, renderNewlines, renderNewpages)
        documentUpdateRender = false
    end
    win.clear()
    scrollOffset = math.max(1, scrollOffset)
    local maxScroll = #document.pages * PHEIGHT - th + 4
    if #document.pages * PHEIGHT > th then
        scrollOffset = math.min(maxScroll, scrollOffset)
    else
        scrollOffset = 1
    end
    local startPage = math.max(1, math.floor((scrollOffset - 2) / PHEIGHT) + 1)
    local endPage = math.min(startPage + math.ceil(th / PHEIGHT), #document.pages)
    for i = startPage, endPage do
        local y = ((i - 1) * PHEIGHT) + 5 - scrollOffset
        sdoc.blitOn(blit, i, pageX, y, win)
        if drawRuler then
            for dy = 1, HEIGHT do
                win.setCursorPos(pageX - 2, y + dy - 1)
                local ch = "\183"
                if dy % 5 == 0 then
                    ch = "-"
                end
                if dy % 10 == 0 then
                    ch = ("%d"):format(dy / 10)
                end
                win.write(ch)
            end
        end
    end
    if drawRuler then
        win.setTextColor(colors.white)
        win.setBackgroundColor(colors.black)
        win.setCursorPos(pageX, 2)
        for i = 1, WIDTH do
            local ch = "\183"
            if i % 5 == 0 then
                ch = "|"
            end
            if i % 10 == 0 then
                ch = ("%d"):format(i / 10)
            end
            win.write(ch)
        end
    end
    if drawStatusBar then
        win.setTextColor(colors.white)
        win.setBackgroundColor(colors.gray)
        win.setCursorPos(1, th)
        win.clearLine()
        local info = document.indicies[cursor]
        win.write(("Page %2d/%2d |"):format(info.page, #document.pages))
        win.write(("Cursor %3d/%3d"):format(cursor, #document.indicies))
    end
    if drawCharInfo then
        win.setTextColor(colors.white)
        win.setBackgroundColor(colors.black)
        win.setCursorPos(1, 3)
        local fgstr = document.editable.content[1]
        win.write(("CH:%02X[%1s]"):format(fgstr:byte(cursor, cursor) or 0, fgstr:sub(cursor, cursor)))
        win.setCursorPos(1, 4)
        win.write(("PAGE:%1d"):format(document.editable.pages[cursor] or 0))
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
    local page = math.floor((y + scrollOffset - 4) / PHEIGHT) + 1
    if page < 1 then
        return
    end
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
    return document.indexlut[page][line][chn]
end

local alignmentReverseLUT = {
    l = 1,
    c = 2,
    r = 3
}

local function moveScreenToFitCursor()
    local x, y = documentIndexToScreen(cursor)
    if y < 3 then
        scrollOffset = scrollOffset - (3 - y)
    elseif y > th - 1 then
        scrollOffset = scrollOffset + y - th + 1
    end
end

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
    moveScreenToFitCursor()
end

local function deleteSelection()
    if a and b then
        a, b = math.min(a, b), math.max(a, b)
        documentString = document:remove(a, b)
        document = sdoc.decode(documentString)
        moveCursor(a)
        a, b = nil, nil
        documentContentUpdate()
    end
end

function copy()
    if not (a and b) then
        return
    end
    clipboard = document.editable.content[1]:sub(a, b)
end

function paste()
    writeToDocument(clipboard)
end

local function wrapCursor(npage, nline)
    if nline < 1 then
        npage = npage - 1
        if npage < 1 then
            npage = 1
            nline = 1
        else
            nline = #document.pages[npage]
        end
    elseif nline > #document.pages[npage] then
        npage = npage + 1
        if npage > #document.pages then
            npage = #document.pages
            nline = #document.pages[npage]
        else
            nline = 1
        end
    end
    return npage, nline
end

---@param dlines number?
---@param dpages number?
local function scrollCursor(dlines, dpages)
    dpages = dpages or 0
    dlines = dlines or 0
    local info = document.indicies[cursor]
    local npage = info.page + dpages
    local nline = info.line + dlines
    npage, nline = wrapCursor(npage, nline)
    if not document.pages[npage][nline] then
        error(("%d %d"):format(npage, nline))
    end
    if document.pages[npage][nline][1] == "" then
        nline = nline + dlines
        npage, nline = wrapCursor(npage, nline)
    end
    cursor = document.indexlut[npage][nline][info.col]
    moveScreenToFitCursor()
end

local function selectWord(idx)
    -- search backwards for a
    local content = document.editable.content[1]
    for i = idx, 1, -1 do
        if content:sub(i, i):match("%s") then
            break
        end
        a = i
    end
    for i = idx, #content do
        if content:sub(i, i):match("%s") then
            break
        end
        b = i
    end
end

local lastClick = 0
local function onEvent(e)
    -- event not consumed, do something with it
    if e[1] == "mouse_scroll" then
        scrollOffset = scrollOffset + e[2]
    elseif e[1] == "mouse_click" then
        local idx = screenToDocumentIndex(e[3], e[4])
        a, b = nil, nil
        local thisClick = os.epoch("utc")
        if thisClick - lastClick < 200 and idx == cursor then
            -- double click
            selectWord(idx)
        end
        lastClick = thisClick
        moveCursor(idx or cursor)
        documentRenderUpdate()
    elseif e[1] == "mouse_drag" then
        local idx = screenToDocumentIndex(e[3], e[4])
        a = cursor
        b = idx or b or cursor
        documentRenderUpdate()
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
        elseif e[2] == keys.delete then
            if not (a or b) then
                a = cursor
                b = cursor
            end
            deleteSelection()
        elseif e[2] == keys.left then
            moveCursor(cursor - 1)
        elseif e[2] == keys.right then
            moveCursor(cursor + 1)
        elseif e[2] == keys.enter then
            deleteSelection()
            -- moveCursor(cursor - 1)
            writeToDocument("\n")
            -- moveCursor(cursor + 1)
        elseif e[2] == keys.up then
            scrollCursor(-1)
        elseif e[2] == keys.down then
            scrollCursor(1)
        elseif e[2] == keys.pageUp then
            scrollCursor(-document.pageHeight)
        elseif e[2] == keys.pageDown then
            scrollCursor(document.pageHeight)
        end
    elseif e[1] == "char" then
        deleteSelection()
        -- moveCursor(cursor - 1)
        writeToDocument(e[2])
        -- moveCursor(cursor + 1)
    elseif e[1] == "term_resize" then
        updateTermSize()
    elseif e[1] == "paste" then
        writeToDocument(e[2])
    end
end

local function mainLoop()
    while running do
        render()
        local e = { os.pullEvent() }
        if not bar.onEvent(e) then
            onEvent(e)
        end
    end
end

local function undoTimer()
    local tid = os.startTimer(1)
    while true do
        local _, id = os.pullEvent("timer")
        if id == tid then
            if documentUpdatedSinceSnapshot then
                documentUpdatedSinceSnapshot = false
                table.insert(undoStates, 1, { state = documentString, cursor = cursor })
                saveAsRaw(".autosave.sdoc")
                undoStates[10] = nil
            end
            tid = os.startTimer(1)
        end
    end
end

local function run()
    parallel.waitForAny(
        mainLoop,
        undoTimer
    )
end

local ok, err = xpcall(run, debug.traceback)
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
