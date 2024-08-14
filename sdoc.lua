local sdoc = {}

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


return sdoc
