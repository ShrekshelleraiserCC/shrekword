--- Dumb turtle client that sits and crafts

local modem = assert(peripheral.find("modem", function(name, wrapped)
    return not wrapped.isWireless()
end), "No modem connected.")

local PROTOCOL = "SHREKPRINT"
local MODEM_PORT = 48752
modem.open(MODEM_PORT)

local function isValid(message)
    return type(message) == "table" and message.protocol == PROTOCOL and
        (message.destination == "*" or message.destination == os.getComputerID())
end

local lname = assert(modem.getNameLocal(), "Modem is not activated!")

local velx, vely = 0.5, 0.3
local velxmin, velxmax = 0.5, 0.8
local velxrange = velxmax - velxmin
local velymin, velymax = 0.5, 0.7
local velyrange = velymin - velymax
local px, py = 1, 1
local crafts = 0
local failures = 0
local image = paintutils.parseImage([[fc7c77f
fc7c00f
f00c00f
f00cc0f
fcccccf
fffffff]])
local function sign(n)
    return n >= 0 and 1 or -1
end
local function bounceX()
    velx = -sign(velx) * (math.random() * velxrange + velxmin)
end
local function bounceY()
    vely = -sign(vely) * (math.random() * velyrange + velymin)
end
local iw, ih = #image[1], #image
local tw, th = term.getSize()
local win = window.create(term.current(), 1, 1, tw, th)
local function render()
    win.setVisible(false)
    win.setBackgroundColor(colors.green)
    win.setTextColor(colors.white)
    win.clear()
    win.setCursorPos(1, 1)
    win.write("ShrekPrint Crafter Online...")
    win.setCursorPos(1, 2)
    win.write(("I have crafted %d books!"):format(crafts))
    if failures > 0 then
        win.setCursorPos(1, 3)
        win.setTextColor(colors.red)
        win.setBackgroundColor(colors.black)
        win.write(("I have been lied to %d times..."):format(failures))
    end
    local old = term.redirect(win)
    paintutils.drawImage(image, math.floor(px), math.floor(py))
    px, py = px + velx, py + vely
    if px < 1 then
        bounceX()
        px = 1
    elseif px + iw - 2 > tw then
        bounceX()
        px = tw - iw
    end
    if py < 1 then
        bounceY()
        py = 1
    elseif py + ih - 2 > th then
        bounceY()
        py = th - ih
    end
    term.redirect(old)
    win.setVisible(true)
end
render()

local function renderLoop()
    while true do
        sleep(0.05)
        render()
    end
end

local function mainThread()
    while true do
        local _, side, channel, replyChannel, message, distance = os.pullEvent("modem_message")
        if isValid(message) then
            if message.type == "PING" then
                modem.transmit(MODEM_PORT, MODEM_PORT, {
                    source = os.computerID(),
                    destination = message.source,
                    type = "PONG",
                    protocol = PROTOCOL,
                    name = lname
                })
            elseif message.type == "CRAFT" then
                crafts = crafts + 1
                if not turtle.craft() then
                    failures = failures + 1
                end
                modem.transmit(MODEM_PORT, MODEM_PORT, {
                    source = os.computerID(),
                    destination = message.source,
                    type = "CRAFTED",
                    protocol = PROTOCOL,
                    name = lname
                })
            end
        end
    end
end

parallel.waitForAny(renderLoop, mainThread)
