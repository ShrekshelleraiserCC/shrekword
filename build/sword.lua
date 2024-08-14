local mbar = {}

local sdoc = {}



---@alias menuCallback fun(entry:Button):boolean?
---@alias shortcut {[number]:number,button:Button} map from last key to modifiers like {s = {"ctrl"}}

---@class Menu
---@field updatePos fun(x:integer?,y:integer?)
---@field click fun(x:integer,y:integer):integer?
---@field updateDepth fun(i:integer)
---@field render fun(depth:integer)
---@field width integer
---@field height integer
---@field x integer
---@field y integer
---@field parent Button

---@class RadialMenu:Menu
---@field options string[]
---@field selected integer
---@field callback fun(self:RadialMenu)?

---@class ColorMenu:Menu
---@field selectedChar string
---@field selectedCol color
---@field selected integer
---@field callback fun(self:ColorMenu)?

---@class CharMenu:Menu
---@field callback fun(self:CharMenu,ch:string)?
---@field color color

---@class Button
---@field label string
---@field callback menuCallback?
---@field submenu Menu?
---@field shortcut shortcut?
---@field entry number
---@field depth number
---@field parent ButtonMenu|Bar

---@class ToggleButton:Button
---@field value boolean

---@class ButtonMenu:Menu
---@field buttons Button[]

---@class Bar
---@field buttons Button[]
---@field buttonEnds integer[] x-pos of last character of each button

---@type Window
local dev

local state = {}

local fg, bg = colors.white, colors.gray
local hfg, hbg = colors.black, colors.white
local mfg, mbg = colors.black, colors.lightGray

---@param fg color?
---@param bg color?
---@return color
---@return color
local function color(fg, bg)
    local ofg = dev.getTextColor()
    local obg = dev.getBackgroundColor()
    dev.setTextColor(fg or ofg)
    dev.setBackgroundColor(bg or obg)
    return ofg, obg
end

local function corner(x, y, w, h)
    dev.setCursorPos(x, y + h)
    local _, _, bgline = dev.getLine(y + h)
    local cfg = dev.getTextColor()
    local cblit = colors.toBlit(cfg)

    dev.blit(("\131"):rep(w), cblit:rep(w), bgline:sub(x, x + w - 1))
    dev.setCursorPos(x + w, y + h)
    dev.blit("\129", cblit, bgline:sub(x + w - 1, x + w - 1))
    for i = 1, h do
        _, _, bgline = dev.getLine(y + i - 1)
        dev.setCursorPos(x + w, y + i - 1)
        dev.blit("\149", cblit, bgline:sub(x + w, x + w))
    end
end

---@param label string
---@param callback menuCallback?
---@param submenu Menu?
---@return Button
function mbar.button(label, callback, submenu)
    ---@class Button
    local button = {
        label = label,
        callback = callback,
        submenu = submenu
    }
    if submenu then
        submenu.parent = button
    end

    function button.click()
        if button.callback then
            button.callback(button)
        end
        state = {}
        if button.submenu then
            state[button.depth] = button.entry
            local searched = button
            for i = button.depth - 1, 1, -1 do
                searched = searched.parent.parent
                state[i] = searched.entry
            end
        end
    end

    return button
end

---@param label string
---@param callback fun(entry:ToggleButton)?
---@return ToggleButton
function mbar.toggleButton(label, callback)
    ---@class ToggleButton
    local button = mbar.button(label, callback) --[[@as ToggleButton]]

    function button.setValue(value)
        button.value = value
        button.label = ("[%1s] %s"):format(value and "*" or " ", label)
        if button.parent then
            button.parent.updateSize()
        end
    end

    button.setValue(false)

    function button.click()
        button.setValue(not button.value)
        if button.callback then
            button.callback(button)
        end
        state[button.depth] = nil
    end

    return button
end

function mbar.absMenu()
    local menu = {
        x = 1,
        y = 2,
        width = 1,
        height = 1,
        depth = 1
    }

    ---@param depth integer
    function menu.render(depth)
        error("Render of abstract menu called!")
    end

    function menu.updatePos(x, y)
        local w, h = dev.getSize()
        x, y = x or menu.x, y or menu.y
        y = math.min(y, h - menu.height)
        local maxx = w - menu.width
        x = math.min(maxx, x)
        menu.x = x
        menu.y = y
    end

    ---@param x integer
    ---@param y integer
    ---@return integer?
    function menu.click(x, y)
        error("Click of abstract menu called!")
    end

    function menu.updateDepth(i)
        menu.depth = i
    end

    return menu
end

---@param callback fun(self:CharMenu,ch:string)?
---@return CharMenu
function mbar.charMenu(callback)
    local menu = mbar.absMenu() --[[@as CharMenu]]
    menu.callback = callback
    menu.color = colors.black
    menu.width, menu.height = 16, 16

    function menu.render(depth)
        local ofg, obg = color()
        for y = 1, menu.height do
            local str = ""
            for x = 1, menu.width do
                str = str .. string.char((y - 1) * menu.width + x - 1)
            end
            dev.setCursorPos(menu.x, menu.y + y - 1)
            dev.blit(str, colors.toBlit(menu.color):rep(#str), ("0"):rep(#str))
        end
        color(bg, obg)
        corner(menu.x, menu.y, menu.width, menu.height)
        color(ofg, obg)
    end

    function menu.click(x, y)
        local i = (y - 1) * menu.width + x - 1
        local ch = string.char(i)
        if menu.callback then
            menu.callback(menu, ch)
        end
        return i
    end

    return menu
end

---@alias colorLUTEntry {index:number,color:color,char:string}

local colorMenuLUTs = {}
---@typep table<integer,colorLUTEntry>
colorMenuLUTs.byIndex = {}
---@typep table<color,colorLUTEntry>
colorMenuLUTs.byColor = {}
---@typep table<string,colorLUTEntry>
colorMenuLUTs.byChar = {}

for i = 0, 15 do
    ---@type colorLUTEntry
    local entry = {}
    entry.index = i
    entry.color = 2 ^ i
    entry.char = ("%x"):format(i)
    colorMenuLUTs.byIndex[entry.index] = entry
    colorMenuLUTs.byColor[entry.color] = entry
    colorMenuLUTs.byChar[entry.char] = entry
end

---@param callback fun(self:ColorMenu)?
---@return ColorMenu
function mbar.colorMenu(callback)
    ---@class ColorMenu
    local menu = mbar.absMenu()
    menu.selected = 15
    menu.selectedCol = colors.black
    menu.selectedChar = "f"
    menu.width, menu.height = 4, 4
    menu.callback = callback

    ---@param i integer|color|string blit character
    function menu.setSelected(i)
        ---@type colorLUTEntry?
        local info = colorMenuLUTs.byIndex[i] or
            colorMenuLUTs.byChar[i] or
            colorMenuLUTs.byColor[i]
        assert(info, ("Invalid color selector %s"):format(tostring(i)))
        menu.selected = info.index
        menu.selectedCol = info.color
        menu.selectedChar = info.char
    end

    function menu.render(depth)
        local ofg, obg = color()
        for x = 1, 4 do
            for y = 1, 4 do
                dev.setCursorPos(x + menu.x - 1, y + menu.y - 1)
                local i = x + ((y - 1) * 4) - 1
                -- dev.blit(i == menu.selected and "\8" or "\7", ("%x"):format(i), "0")
                -- dev.blit("\7", ("%x"):format(i), menu.selectedChar)
                dev.blit("\7", ("%x"):format(i), menu.selected == i and menu.selectedChar or "0")
            end
        end
        color(menu.selectedCol, obg)
        corner(menu.x, menu.y, menu.height, menu.width)
        color(ofg, obg)
    end

    function menu.click(x, y)
        menu.setSelected(x + ((y - 1) * 4) - 1)
        if menu.callback then
            menu.callback(menu)
        end
        return menu.selected
    end

    return menu
end

---@param options string[]
---@param callback fun(self:RadialMenu)?
---@return RadialMenu
function mbar.radialMenu(options, callback)
    ---@type RadialMenu
    local menu = mbar.absMenu()
    menu.options = options
    menu.selected = 1
    menu.callback = callback

    local width = 1
    menu.height = #menu.options
    for _, v in ipairs(menu.options) do
        width = math.max(width, #v + 3)
    end
    menu.width = width

    function menu.render(depth)
        local ofg, obg = color()
        local s = (" %%1s%%-%ds"):format(menu.width - 2)
        for i, v in ipairs(menu.options) do
            if menu.selected == i then
                color(hfg, hbg)
            else
                color(mfg, mbg)
            end
            dev.setCursorPos(menu.x, menu.y + i - 1)
            dev.write(s:format(i == menu.selected and "\7" or "\186", v))
        end
        color(bg, obg)
        corner(menu.x, menu.y, menu.width, menu.height)
        color(ofg, obg)
    end

    function menu.click(x, y)
        menu.selected = y
        if menu.callback then
            menu.callback(menu)
        end
        return y
    end

    return menu
end

---@param buttons Button[]
---@return ButtonMenu
function mbar.buttonMenu(buttons)
    ---@class ButtonMenu
    local menu = mbar.absMenu()
    menu.buttons = buttons

    for i, v in ipairs(menu.buttons) do
        v.entry = i
        v.parent = menu
    end

    function menu.updateSize()
        local width = 1
        menu.height = #menu.buttons
        for _, v in ipairs(menu.buttons) do
            width = math.max(width, #v.label + 3)
        end
        menu.width = width
        for i, v in ipairs(menu.buttons) do
            if v.submenu then
                v.submenu.updatePos(menu.x + menu.width, menu.y + i - 1)
            end
        end
    end

    menu.updateSize()

    ---@param depth integer
    function menu.render(depth)
        local ofg, obg = color()
        local s = (" %%-%ds%%1s"):format(menu.width - 2)
        for i, v in ipairs(menu.buttons) do
            if state[depth] == i then
                color(hfg, hbg)
            else
                color(mfg, mbg)
            end
            dev.setCursorPos(menu.x, menu.y + i - 1)
            dev.write(s:format(v.label, v.submenu and ">" or " "))
        end
        local selected = menu.buttons[state[depth]]
        color(bg, obg)
        corner(menu.x, menu.y, menu.width, menu.height)
        color(ofg, obg)
        if selected and selected.submenu then
            selected.submenu.render(depth + 1)
        end
    end

    local oldupdate = menu.updatePos
    function menu.updatePos(x, y)
        oldupdate(x, y)
        for i, v in ipairs(menu.buttons) do
            if v.submenu then
                v.submenu.updatePos(menu.x + menu.width, menu.y + i - 1)
            end
        end
    end

    ---@param x integer
    ---@param y integer
    ---@return integer?
    function menu.click(x, y)
        local button = menu.buttons[y]
        button.click()
        return y
    end

    function menu.updateDepth(i)
        for _, v in ipairs(menu.buttons) do
            v.depth = i
            if v.submenu then
                v.submenu.updateDepth(i + 1)
            end
        end
    end

    return menu
end

---@param buttons Button[]
---@return Bar
function mbar.bar(buttons)
    ---@class Bar
    local bar = {
        buttons = buttons,
        buttonEnds = {}
    }
    local x = 1
    for i, v in ipairs(bar.buttons) do
        v.depth = 1
        v.entry = i
        v.parent = bar
        if v.submenu then
            v.submenu.updatePos(x)
            v.submenu.updateDepth(2)
        end
        x = x + #v.label + 2
        bar.buttonEnds[i] = x
    end

    function bar.render()
        dev.setCursorPos(1, 1)
        local ofg, obg = color(fg, bg)
        dev.clearLine()
        for i, v in ipairs(bar.buttons) do
            if state[1] == i then
                color(mfg, mbg)
            else
                color(fg, bg)
            end
            dev.write(" " .. v.label .. " ")
        end
        local selected = bar.buttons[state[1]]
        color(ofg, obg)
        if selected and selected.submenu then
            selected.submenu.render(2)
        end
        -- dev.setCursorPos(1, 10)
        -- dev.write(textutils.serialise(state))
    end

    ---@param x integer
    ---@param y integer
    ---@return boolean? consumed
    function bar.click(x, y)
        if y == 1 then
            -- on the bar
            local entry
            for i, v in ipairs(bar.buttonEnds) do
                if x < v then
                    entry = i
                    break
                end
            end
            if entry then
                local button = bar.buttons[entry]
                button.click()
            else
                state = {}
            end
            return true
        end
        local menu = bar
        -- not on the bar, check open menus
        ---@type Menu[]
        local menus = {}
        for depth = 1, #state do
            local v = state[depth]
            if not (menu and menu.buttons) then break end
            menu = menu.buttons[v].submenu
            menus[#menus + 1] = menu
        end
        for depth = 1, #menus, 1 do
            local menu = menus[depth]
            if x >= menu.x and x < menu.x + menu.width and y >= menu.y and y < menu.y + menu.height then
                local clicked = menu.click(x - menu.x + 1, y - menu.y + 1)
                if clicked then
                    return true
                end
            end
        end
        if #state > 0 then
            -- not in an open menu, close all menus
            state = {}
            return true
        end
        return false
    end

    ---@type table<string,shortcut>
    local shortcuts = {}
    local heldKeys = {}

    ---@param button Button
    ---@param key number
    ---@param control boolean?
    ---@param shift boolean?
    ---@param alt boolean?
    ---@return shortcut
    function bar.shortcut(button, key, control, shift, alt)
        local shortcut = {}
        local label = {}
        if alt then
            shortcut[#shortcut + 1] = keys.leftAlt
            label[#label + 1] = "alt+"
        end
        if control then
            shortcut[#shortcut + 1] = keys.leftCtrl
            label[#label + 1] = "^"
        end
        if shift then
            shortcut[#shortcut + 1] = keys.leftShift
            label[#label + 1] = keys.getName(key):upper()
        else
            label[#label + 1] = keys.getName(key)
        end
        shortcut[#shortcut + 1] = key
        shortcut.button = button
        button.label = ("%s (%s)"):format(button.label, table.concat(label))
        button.parent.updateSize()
        assert(shortcuts[key] == nil, ("Attempt to register repeated shortcut (%s)"):format(table.concat(label)))
        shortcuts[key] = shortcut
        return shortcut
    end

    ---Call when some function that consumes events is called between calls to bar.onEvent
    function bar.resetKeys()
        heldKeys = {}
    end

    ---Call to pass an event to this
    ---@param e any[]
    ---@return boolean? consumed
    function bar.onEvent(e)
        local menuOpen = #state > 0
        if e[1] == "mouse_click" then
            return bar.click(e[3], e[4])
        elseif e[1] == "key" then
            heldKeys[e[2]] = true
            local shortcut = shortcuts[e[2]]
            if shortcut then
                for _, v in ipairs(shortcut) do
                    if not heldKeys[v] then
                        return
                    end
                end
                -- all keys are held for this shortcut
                shortcut.button.click()
                return true
            end
        elseif e[1] == "key_up" then
            heldKeys[e[2]] = nil
        elseif menuOpen and (e[1] == "mouse_drag" or e[1] == "mouse_up") then
            return true
        end
    end

    return bar
end

function mbar.setWindow(win)
    dev = win
end

local function fill(x, y, w, h)
    local s = (" "):rep(w)
    for i = 0, h - 1 do
        dev.setCursorPos(x, y + i)
        dev.write(s)
    end
end

---Show a popup
---@param title string
---@param text string
---@param options string[]
---@param w integer?
---@return integer
function mbar.popup(title, text, options, w)
    dev.setCursorBlink(false)
    local tw, th = dev.getSize()
    local ofg, obg = color(mfg, mbg)

    local optionWidth = 0
    for _, v in ipairs(options) do
        optionWidth = optionWidth + #v + 3
    end
    w = math.max(optionWidth, w or 0)

    local optionX = math.floor((tw - optionWidth) / 2)
    local optionPos = {}

    local s = require("cc.strings").wrap(text, w - 2)
    local h = #s + 5
    local x, y = math.floor((tw - w) / 2), math.floor((th - h) / 2)
    local optionY = y + h - 2
    fill(x, y, w, h)
    for i, v in ipairs(s) do
        dev.setCursorPos(x + 1, y + i + 1)
        dev.write(v)
    end
    color(fg, bg)
    fill(x, y, w, 1)
    local tx = math.floor((tw - #title) / 2)
    dev.setCursorPos(tx, y)
    dev.write(title)
    for i, v in ipairs(options) do
        color(hfg, hbg)
        dev.setCursorPos(optionX, optionY)
        dev.write(" " .. v .. " ")
        color(bg, fg)
        corner(optionX, optionY, #v + 2, 1)
        optionPos[i] = optionX
        optionX = optionX + #v + 3
    end
    color(bg, obg)
    corner(x, y, w, h)
    color(ofg, obg)
    while true do
        local _, _, x, y = os.pullEvent("mouse_click")
        if y == optionY and x < optionX then
            for i = #options, 1, -1 do
                if x >= optionPos[i] then
                    return i
                end
            end
        end
    end
end

---@param title string
---@param w integer
---@param text string?
---@param completion function?
---@return string?
function mbar.popupRead(title, w, text, completion)
    dev.setCursorBlink(false)
    local tw, th = dev.getSize()
    local ofg, obg = color(mfg, mbg)
    local h = 6
    local x, y
    if text then
        local s = require("cc.strings").wrap(text, w - 2)
        h = #s + 7
        x, y = math.floor((tw - w) / 2), math.floor((th - h) / 2)
        fill(x, y, w, h)
        for i, v in ipairs(s) do
            dev.setCursorPos(x + 1, y + i + 1)
            dev.write(v)
        end
    else
        x, y = math.floor((tw - w) / 2), math.floor((th - h) / 2)
        fill(x, y, w, h)
    end

    color(fg, bg)
    fill(x, y, w, 1)
    local tx = math.floor((tw - #title) / 2)
    dev.setCursorPos(tx, y)
    dev.write(title)
    color(bg, obg)
    corner(x, y, w, h)
    local readY = y + h - 4
    local readWindow = window.create(dev, x + 1, readY, w - 2, 1)
    readWindow.setTextColor(hfg)
    readWindow.setBackgroundColor(hbg)
    readWindow.clear()
    readWindow.setCursorPos(1, 1)

    local cancelX = x + 1
    local cancelY = y + h - 2
    local cancelW = 8
    color(hfg, hbg)
    dev.setCursorPos(cancelX, cancelY)
    dev.write(" Cancel ")
    color(bg, fg)
    corner(cancelX, cancelY, cancelW, 1)

    local oldWin = term.redirect(readWindow)

    local value
    parallel.waitForAny(function()
        value = read(nil, nil, completion)
    end, function()
        while true do
            local _, _, x, y = os.pullEvent("mouse_click")
            if x >= cancelX and x < cancelX + cancelW and y == cancelY then
                return
            end
        end
    end)

    term.redirect(oldWin)
    color(ofg, obg)
    return value
end

local ESCAPE_CHAR = "\160"

---@alias BLIT string[][]

local escapeCharWidth = { c = 3, r = 2, a = 3, p = 2 }

---@param s string
---@return string[] characterMap char[]
---@return table<integer,string[]> escapeCharMap char# in string -> escape code
function sdoc.extractEscapeCodes(s)
    local escapeCharMap = {}
    local output = {}
    local oidx = 1
    local sidx = 1
    while sidx <= #s do
        local ch = s:sub(sidx, sidx)
        if ch == ESCAPE_CHAR then
            local esch = s:sub(sidx + 1, sidx + 1)
            local w = assert(escapeCharWidth[esch], ("Invalid escape code %s"):format(esch))
            escapeCharMap[oidx] = escapeCharMap[oidx] or {}
            local code = s:sub(sidx + 1, sidx + w - 1)
            table.insert(escapeCharMap[oidx], code)
            sidx = sidx + w
        else
            output[oidx] = ch
            oidx = oidx + 1
            sidx = sidx + 1
        end
    end
    return output, escapeCharMap
end

---@param s string
---@param width integer
---@return string[]
---@return table<integer,string[]> escapeCharMap char# in string -> escape code
function sdoc.wrapString(s, width)
    local str, map = sdoc.extractEscapeCodes(s)
    local ccstr = table.concat(str, "")
    local idx = 1
    local row, col = 1, 1
    local output = {}
    local function writeChar(ch)
        if col > width then
            col = 1
            row = row + 1
        end
        output[row] = output[row] or {}
        output[row][col] = ch
        col = col + 1
    end
    local function handleEscapeCodes(codes)
    end
    while idx <= #str do
        local ch = str[idx]
        if ch:match("%S") then
            -- not whitespace
            local length = 1
            while str[idx + length - 1]:match("%S") do
                length = length + 1
                if idx + length - 1 > #str then
                    break
                end
            end
            if width - col < length and length < width then
                row = row + 1
                col = 1
            end
            for i = 1, length - 1 do
                handleEscapeCodes(map[idx + i - 1])
                writeChar(str[idx + i - 1])
            end
            idx = idx + length - 1
        elseif ch == "\n" then
            handleEscapeCodes(map[idx])
            writeChar("\n")
            col = 1
            row = row + 1
            idx = idx + 1
        else
            handleEscapeCodes(map[idx])
            writeChar(ch)
            idx = idx + 1
        end
    end
    for i, v in ipairs(output) do
        output[i] = table.concat(v, "")
    end
    return output, map
end

---@alias Alignment "l"|"c"|"r"
---@alias DocumentLine {[integer]:string,alignment:Alignment,lineX:integer}

---@class Document
---@field pageWidth integer
---@field pageHeight integer
---@field pages table<integer,DocumentLine[]>
---@field indicies {page:number,line:number,col:number}[]
---@field indexlut table<integer,table<integer,table<integer,integer>>> [page][line][col]
---@field editable EditableDocument
---@field blit BLIT[]

---@class EditableDocument
---@field pageWidth integer
---@field pageHeight integer
---@field content string[]
---@field linestart table<integer,{alignment:Alignment}>
---@field pages table<integer,integer> inserted page markers

local headerMatch = "^shrekdoc%-v(%d%d)w(%d%d)h(%d%d)m([RS]):"
local headerExample = "shrekdoc-v00w00h00mR:"

---@param str string
---@return string
---@return number w
---@return number h
local function decodeHeader(str)
    local version, w, h, mode = str:match(headerMatch)
    assert(version, "Invalid document (missing header!)")
    assert(version == "01", ("Unsupported document version v%s"):format(version))
    w, h = tonumber(w), tonumber(h)
    assert(w and h, "Invalid document dimensions.")
    if mode == "R" then
        str = str:sub(#headerExample + 1)
    elseif mode == "S" then
        local s = textutils.unserialise(str:sub(#headerExample + 1))
        assert(type(s) == "string", "Invalid serialized document.")
        str = s
    end
    return str, w, h
end

---@param editable EditableDocument
---@return string
local function encode(editable)
    local color = "f"
    local alignment = "l"
    local str = {}
    str[1] = ("shrekdoc-v01w%02dh%02dmR:"):format(editable.pageWidth, editable.pageHeight)
    for i = 1, #editable.content[1] do
        local fg, bg = editable.content[1]:sub(i, i), editable.content[2]:sub(i, i)
        local line = editable.linestart[i]
        if fg == ESCAPE_CHAR then
            str[#str + 1] = ESCAPE_CHAR -- escape escape characters
        end
        if bg ~= color then
            color = bg
            str[#str + 1] = ESCAPE_CHAR .. "c" .. color
        end
        if editable.pages[i] then
            for n = 1, editable.pages[i] do
                str[#str + 1] = ESCAPE_CHAR .. "p"
            end
        end
        if line and line.alignment ~= alignment then
            alignment = line.alignment
            -- table.insert(str, math.max(2, #str), ESCAPE_CHAR .. "a" .. alignment)
            str[#str + 1] = ESCAPE_CHAR .. "a" .. alignment
        end
        str[#str + 1] = fg
    end
    return table.concat(str, "")
end

---@class Document
local docmeta__index = {}
local docmeta = { __index = docmeta__index }

---@generic T:any
---@param t T
---@return T
local function deepClone(t)
    if type(t) == "table" then
        local nt = {}
        for k, v in pairs(t) do
            nt[k] = deepClone(v)
        end
        return nt
    end
    return t
end

---@param self Document
---@param a integer
---@param b integer
---@return string document
function docmeta__index:remove(a, b)
    a, b = math.min(a, b), math.max(a, b)
    local sectionWidth = b - a + 1
    local editable = deepClone(self.editable)

    for i = a, b do
        editable.linestart[i] = nil
        editable.pages[i] = nil
    end

    for i = a, #editable.content[1] do
        if editable.linestart[i] then
            editable.linestart[i - sectionWidth] = editable.linestart[i]
            editable.linestart[i] = nil
        end
        if editable.pages[i] then
            editable.pages[i - sectionWidth] = editable.pages[i]
            editable.pages[i] = nil
        end
    end
    editable.content[1] = editable.content[1]:sub(1, a - 1) .. editable.content[1]:sub(b + 1)
    editable.content[2] = editable.content[2]:sub(1, a - 1) .. editable.content[2]:sub(b + 1)
    return encode(editable)
end

---@param self Document
---@param idx integer
---@param alignment Alignment
function docmeta__index:setAlignment(idx, alignment)
    local editable = deepClone(self.editable)

    for i = idx, 1, -1 do
        local nl = editable.linestart[i]
        if nl then
            nl.alignment = alignment
            break
        end
    end

    return encode(editable)
end

---@param self Document
---@param color string
---@param a integer
---@param b integer
---@return string document
function docmeta__index:setColor(color, a, b)
    a, b = math.min(a, b), math.max(a, b)
    local size = b - a + 1
    local editable = deepClone(self.editable)
    local s = editable.content[2]
    editable.content[2] = s:sub(1, a - 1) .. color:rep(size) .. s:sub(b + 1, -1)

    return encode(editable)
end

---@param self Document
---@param idx integer
---@param str string
---@param color string
---@return string document
function docmeta__index:insertAt(idx, str, color)
    local sectionWidth = #str
    local editable = deepClone(self.editable)
    for i = #editable.content[1], idx, -1 do
        if editable.linestart[i] then
            editable.linestart[i + sectionWidth] = editable.linestart[i]
            editable.linestart[i] = nil
        end
        if editable.pages[i] then
            editable.pages[i + sectionWidth] = editable.pages[i]
            editable.pages[i] = nil
        end
    end
    editable.content[1] = editable.content[1]:sub(1, idx - 1) .. str .. editable.content[1]:sub(idx)
    editable.content[2] = editable.content[2]:sub(1, idx - 1) .. (color):rep(#str) .. editable.content[2]:sub(idx)
    return encode(editable)
end

function docmeta__index:insertPage(idx)
    local editable = deepClone(self.editable)
    editable.pages[idx] = (editable.pages[idx] or 0) + 1
    return encode(editable)
end

---@param str string
---@return Document
function sdoc.decode(str)
    local str, w, h = decodeHeader(str)
    local s, m = sdoc.wrapString(str, w)
    ---@class Document
    local doc = {
        pages = { {} },
        indicies = {},
        indexlut = {},
        pageWidth = w,
        pageHeight = h,
        editable = { content = {}, linestart = {}, pages = {}, pageHeight = h, pageWidth = w }
    }
    local color = "f"
    local alignment = "l"
    local idx = 1
    local page = 1
    local ln = 1
    local chn = 1
    local lineColor = {}
    local lineText = {}

    local function writeLine()
        doc.pages[page] = doc.pages[page] or {}
        doc.pages[page][ln] = {}
        doc.pages[page][ln][1] = table.concat(lineText, "")
        doc.pages[page][ln][2] = table.concat(lineColor, "")
        doc.pages[page][ln].alignment = alignment
        lineColor, lineText = {}, {}
        ln = ln + 1
        chn = 1
    end

    ---@param code string[]
    local function parseEscapeCode(code, y)
        for _, s in ipairs(code) do
            if s:sub(1, 1) == "r" then
                color, alignment = "f", "l"
            elseif s:sub(1, 1) == "c" then
                color = s:sub(2, 2)
            elseif s:sub(1, 1) == "a" then
                alignment = s:sub(2, 2)
            elseif s:sub(1, 1) == "p" then
                writeLine()
                page = page + 1
                ln = 1
                doc.editable.pages[idx] = (doc.editable.pages[idx] or 0) + 1
                -- doc.indexlut[page] = doc.indexlut[page] or {}
                -- doc.indexlut[page][ln] = doc.indexlut[page][ln] or {}
            else
                error(("Invalid escape code %s"):format(s))
            end
        end
    end

    for i, line in ipairs(s) do
        if ln - 1 == h then
            page = page + 1
            doc.editable.pages[idx] = (doc.editable.pages[idx] or 0) + 1
            ln = 1
        end
        for x = 1, #line do
            local ch = line:sub(x, x)
            if m[idx] then
                parseEscapeCode(m[idx], i)
            end
            doc.indicies[idx] = { line = ln, col = chn, page = page }
            doc.indexlut[page] = doc.indexlut[page] or {}
            doc.indexlut[page][ln] = doc.indexlut[page][ln] or {}
            doc.indexlut[page][ln][chn] = idx
            lineColor[chn] = color
            lineText[chn] = ch
            idx = idx + 1
            chn = chn + 1
        end
        writeLine()
    end
    -- error(("%d %d, %d, %d"):format(idx, ln, chn, page))
    local last = doc.indicies[idx - 1] or { line = 1, col = 1, page = 1 }
    doc.indicies[idx] = { line = last.line, col = last.col + 1, page = last.page }

    -- fill out the rest of the indexlut
    local lastSeenIdx = 1
    local lastPage = page

    for page = 1, lastPage do
        doc.indexlut[page] = doc.indexlut[page] or {}
        local pageHeight = #doc.indexlut[page]
        for line = 1, doc.pageHeight do
            local lineLength = #(doc.indexlut[page][line] or {})
            doc.indexlut[page][line] = doc.indexlut[page][line] or {}
            for chn = 1, doc.pageWidth do
                if doc.indexlut[page][line][chn] then
                    lastSeenIdx = doc.indexlut[page][line][chn]
                else
                    doc.indexlut[page][line][chn] = lastSeenIdx
                end
                if page == lastPage and line == pageHeight and chn == lineLength then
                    lastSeenIdx = lastSeenIdx + 1
                end
            end
        end
    end
    doc.pages[1][1] = doc.pages[1][1] or { "", "", alignment = "l", lineX = 1 }

    local fgstring = {}
    local bgstring = {}
    -- reconsolidate into an easily editable form
    local lastLineHadNewline = true
    for pn, page in ipairs(doc.pages) do
        for ln, line in ipairs(page) do
            fgstring[#fgstring + 1] = line[1]
            bgstring[#bgstring + 1] = line[2]
            if lastLineHadNewline then
                local index = doc.indexlut[pn][ln][1]
                doc.editable.linestart[index] = { alignment = line.alignment }
                lastLineHadNewline = false
            end
            local chn = line[1]:find("\n")
            lastLineHadNewline = not not chn
        end
        if #page < doc.pageHeight then
            -- there is a newpage inserted here
            lastLineHadNewline = true
        end
    end
    doc.editable.content[1] = table.concat(fgstring, "")
    doc.editable.content[2] = table.concat(bgstring, "")

    doc.blit = sdoc.render(doc)

    return setmetatable(doc, docmeta)
end

---@param doc Document
---@return string
function sdoc.encode(doc)
    return encode(doc.editable)
end

local highlightColor = "8"
local newpageColor = "1"

---@param doc Document
---@param a integer?
---@param b integer?
---@param renderNewlines boolean?
---@param renderNewpages boolean?
---@param renderControl boolean?
---@return BLIT[]
function sdoc.render(doc, a, b, renderNewlines, renderNewpages, renderControl)
    b = b or a
    if a and b then
        a, b = math.min(a, b), math.max(a, b)
    end
    local blit = {}
    local lastSeenColor = "0"
    local lineEndsInHighlight = false
    local lineStartsInHighlight = false
    local y = 1
    for pn, page in ipairs(doc.pages) do
        local pblit = {}
        y = 1
        for ln = 1, doc.pageHeight do
            local line = page[ln] or { "", "", "", alignment = "l" }
            line[3] = ""
            local sx = 1
            for i = 1, #line[1] do
                local idx = doc.indexlut[pn][ln][i]
                if a and b and idx >= a and idx <= b then
                    lineEndsInHighlight = true
                else
                    lineEndsInHighlight = false
                end
                if renderNewpages and (doc.editable.pages[idx] or 0) > 0 then
                    line[3] = line[3] .. newpageColor
                else
                    line[3] = line[3] .. (lineEndsInHighlight and highlightColor or "0")
                end
            end
            local alignment = line.alignment
            if alignment == "c" then
                sx = math.floor((doc.pageWidth - #line[1]) / 2) + 1
            elseif alignment == "r" then
                sx = doc.pageWidth - #line[1] + 1
            end
            local colorStart = line[2]:sub(1, 1)
            local colorEnd = line[2]:sub(#line[2], #line[2])
            if #line[2] == 0 then
                colorStart, colorEnd = lastSeenColor, lastSeenColor
            else
                lastSeenColor = colorEnd
            end
            if page[ln] then
                page[ln].lineX = sx
            end
            pblit[y] = {}
            pblit[y][1] = (" "):rep(sx - 1) .. line[1] .. (" "):rep(doc.pageWidth - sx + 1 - #line[1])
            if renderNewlines then
                pblit[y][1] = pblit[y][1]:gsub("\n", "\182")
            end
            pblit[y][2] = (colorStart):rep(sx - 1) .. line[2] .. (colorEnd):rep(doc.pageWidth - sx + 1 - #line[2])
            local sbg = (lineStartsInHighlight and highlightColor or "0")
            local ebg = (lineEndsInHighlight and highlightColor or "0")
            pblit[y][3] = sbg:rep(sx - 1) .. line[3] .. ebg:rep(doc.pageWidth - sx + 1 - #line[3])
            y = y + 1
            lineStartsInHighlight = lineEndsInHighlight
        end
        blit[pn] = pblit
    end
    return blit
end

---@param dev Window|term
---@param fg color?
---@param bg color?
---@return color
---@return color
local function setColor(dev, fg, bg)
    local obg, ofg = dev.getBackgroundColor(), dev.getTextColor()
    if bg then dev.setBackgroundColor(bg) end
    if fg then dev.setTextColor(fg) end
    return ofg, obg
end

---@param doc BLIT[]
---@param x integer?
---@param y integer?
---@param dev Window|term?
---@param border boolean?
function sdoc.blitOn(doc, page, x, y, dev, border)
    local pageWidth = #doc[1][1][1]
    local pageHeight = #doc[1]
    dev = dev or term
    if border == nil then border = true end
    local w, h = dev.getSize()
    x = x or math.ceil((w - pageWidth) / 2)
    y = y or math.ceil((h - pageHeight) / 2)
    local ofg, obg = setColor(dev, colors.black, colors.white)
    if border then
        dev.setCursorPos(x - 1, y - 1)
        dev.write("\159")
        dev.write(("\143"):rep(pageWidth))
        setColor(dev, colors.white, colors.black)
        dev.setCursorPos(x - 1, y + pageHeight)
        dev.write("\130")
        for i = 1, pageHeight do
            setColor(dev, colors.black, colors.white)
            dev.setCursorPos(x - 1, y + i - 1)
            dev.write("\149")
            setColor(dev, colors.white, colors.lightGray)
            dev.setCursorPos(x + pageWidth, y + i - 1)
            dev.write("\149")
        end
        setColor(dev, colors.white, colors.black)
        dev.setCursorPos(x + pageWidth, y - 1)
        dev.write("\144")
        setColor(dev, colors.white, colors.lightGray)
        dev.setCursorPos(x, y + pageHeight)
        dev.write(("\131"):rep(pageWidth))
        dev.write("\129")
    end

    for i, line in ipairs(doc[page]) do
        dev.setCursorPos(x, y + i - 1)
        dev.blit(table.unpack(line))
    end
    setColor(dev, ofg, obg)
end

function sdoc.dump(fn, t)
    local s = textutils.serialise(t)
    local f = assert(fs.open(fn, "w"))
    f.write(s)
    f.close()
end

-- local function draw(blit)
--     for pn, page in ipairs(blit) do
--         print(pn)
--         for i, line in ipairs(page) do
--             term.blit(table.unpack(line))
--             print()
--         end
--     end
--     print()
-- end
-- draw(s)





local version = "PREV-0"

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

local WIDTH, HEIGHT
local PHEIGHT
local pageX

local tw, th = term.getSize()
local win = window.create(term.current(), 1, 1, tw, th)
mbar.setWindow(win)

local function updateDocumentSize(w, h)
    WIDTH, HEIGHT = w, h
    PHEIGHT = HEIGHT + 2
    pageX = math.floor((tw - WIDTH) / 2)
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
        return false
    end
    if fs.isDir(fn) then
        mbar.popup("Error", "Directories are not documents!", { "Ok" }, 15)
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
        documentRenderUpdate()
        cursor = 1
        a, b = nil, nil
        updateDocumentSize(document.pageWidth, document.pageHeight)
        return true
    end
    mbar.popup("Error", err --[[@as string]], { "Ok :)", "Ok :(" }, 20)
    return false
end
---@return boolean continue
local function unsavedDocumentPopup()
    if documentUpdatedSinceSave then
        local option = mbar.popup("Warning", "You have unsaved changes. Discard these?", { "Yes", "No" },
            20)
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
    if fn then
        openDocument(fn)
    end
end)
local function saveAs(fn)
    local f = assert(fs.open(fn, "w"))
    f.write(documentString)
    f.close()
    documentUpdatedSinceSave = false
end
local saveAsButton = mbar.button("Save As", function(entry)
    local fn = mbar.popupRead("Save As", 15)
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

local filesm = mbar.buttonMenu({ newButton, openButton, saveButton, saveAsButton, quitButton })

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
    documentString = document:setAlignment(cursor, value)
    document = sdoc.decode(documentString)
    documentContentUpdate()
end)
local colorButton = mbar.button("Color", nil, colorMenu)
local insertMenu = mbar.buttonMenu {
    mbar.button("New Page", function(entry)
        documentString = document:insertPage(cursor)
        document = sdoc.decode(documentString)
        documentContentUpdate()
    end),
    mbar.button("Character", nil, charMenu)
}
local undoButton = mbar.button("Undo", function(entry)
    local str = table.remove(undoStates, 2)
    if str then
        documentString = str.state
        document = sdoc.decode(documentString)
        documentContentUpdate()
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

-- VIEW MENU

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
local viewMenu = mbar.buttonMenu({ renderNewlineButton, renderNewpageButton })
local viewButton = mbar.button("View", nil, viewMenu)
local bar
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

local function onEvent(e)
    -- event not consumed, do something with it
    if e[1] == "mouse_scroll" then
        scrollOffset = scrollOffset + e[2]
    elseif e[1] == "mouse_click" then
        local idx = screenToDocumentIndex(e[3], e[4])
        a, b = nil, nil
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
