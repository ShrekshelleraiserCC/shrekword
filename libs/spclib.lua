local spclib = {}

-- ShrekPrint Client Library
spclib.PROTOCOL = "SHREKPRINT"

---@param host integer
---@param document string
---@param copies integer?
---@return boolean
---@return string
function spclib.aboutDocument(host, document, copies, book)
    rednet.send(host, {
        type = "DOCINFO",
        document = document,
        copies = copies,
        asBook = book
    }, spclib.PROTOCOL)
    local id, msg = rednet.receive(spclib.PROTOCOL, 1)
    if not (id and msg) then
        return false, "Connection timed out."
    end
    return msg.result, msg.reason
end

---@param host integer
---@param document string
---@param copies integer?
---@param book boolean?
---@return boolean
---@return string
function spclib.printDocument(host, document, copies, book)
    rednet.send(host, {
        type = "PRINT",
        document = document,
        copies = copies,
        asBook = book
    }, spclib.PROTOCOL)
    local id, msg = rednet.receive(spclib.PROTOCOL, 1)
    if not (id and msg) then
        return false, "Connection timed out."
    end
    return msg.result, msg.reason
end

---@param host integer
---@return string? name
---@return table<string,integer> levels
---@return integer paper
---@return integer string
---@return integer leather
function spclib.printerInfo(host)
    rednet.send(host, {
        type = "INFO"
    }, spclib.PROTOCOL)
    local id, msg = rednet.receive(spclib.PROTOCOL, 1)
    if not (id and msg) then
        return nil, {}, 0, 0, 0
    end
    return msg.name, msg.inkLevels, msg.paper, msg.string, msg.leather
end

return spclib
