local mbar = {}

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

return mbar
