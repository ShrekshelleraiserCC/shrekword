local network = {}

network.wiredModem = assert(peripheral.find("modem", function(name, wrapped)
    return not wrapped.isWireless()
end), "This printer needs a wired modem attached.") --[[@as Modem]]

network.MODEM_PORT = 48752
network.PROTOCOL = "SHREKPRINT"
network.wiredModem.open(network.MODEM_PORT)

function network.isValid(message)
    return type(message) == "table" and message.protocol == network.PROTOCOL and
        (message.destination == "*" or message.destination == os.getComputerID())
end

return network
