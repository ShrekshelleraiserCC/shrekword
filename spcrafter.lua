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

term.clear()
term.setCursorPos(1, 1)
print("ShrekPrint Crafter Online...")

while true do
    local _, side, channel, replyChannel, message, distance = os.pullEvent("modem_message")
    if isValid(message) then
        if message.type == "PING" then
            print("GOT PING")
            modem.transmit(MODEM_PORT, MODEM_PORT, {
                source = os.computerID(),
                destination = message.source,
                type = "PONG",
                protocol = PROTOCOL,
                name = lname
            })
        elseif message.type == "CRAFT" then
            print("Got craft request!")
            turtle.craft()
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
