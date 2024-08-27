local sdoc = require "libs.sdoc"

local args = { ... }
if #args < 1 then
    print("sview <fn>")
    return
end

local f = assert(fs.open(args[1], "r"))
local str = f.readAll()
f.close()

local document = sdoc.decode(sdoc.decode(str):remove(5, 6))
local blit = sdoc.render(document)

local page = 1

local win = window.create(term.current(), 1, 1, term.getSize())

local function centerWrite(y, s)
    local w, h = win.getSize()
    win.setCursorPos(math.floor((w - #s) / 2), y)
    win.write(s)
end

local function draw()
    local w, h = win.getSize()
    win.setVisible(false)
    win.clear()
    if document.editable.title then
        centerWrite(1, document.editable.title)
    end
    centerWrite(h, ("Page %d of %d"):format(page, #document.pages))
    sdoc.blitOn(blit, page, nil, nil, win)
    win.setVisible(true)
end

while true do
    draw()
    local e, key = os.pullEvent()
    if e == "key" then
        if key == keys.up then
            page = math.max(1, page - 1)
        elseif key == keys.down then
            page = math.min(#document.pages, page + 1)
        end
    elseif e == "mouse_scroll" then
        page = math.max(1, math.min(#document.pages, page + key))
    elseif e == "term_resize" then
        win.reposition(1, 1, term.getSize())
    end
end
