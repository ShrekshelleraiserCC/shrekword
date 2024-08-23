local scolors = {}

---@type table<string,string>
scolors.contrastBlitLut = {}
---@type table<color,color>
scolors.contrastColorLut = {}
---@type table<color|string,number>
scolors.brightnessLut = {}
---@type color
scolors.brightestColor = colors.white
scolors.brightestBlit = "0"
scolors.darkestBlit = "f"
scolors.darkestColor = colors.black

function scolors.calculate()
    local brightest = 0
    local darkest = 1000
    for i = 0, 15 do
        local color = 2 ^ i
        local ch = colors.toBlit(color)
        local r, g, b = term.getPaletteColor(color)
        local brightness = math.sqrt(r ^ 2 + g ^ 2 + b ^ 2)
        scolors.brightnessLut[ch] = brightness
        scolors.brightnessLut[color] = brightness
        if brightness > brightest then
            brightest = brightness
            scolors.brightestColor = color
            scolors.brightestBlit = ch
        elseif brightness < darkest then
            darkest = brightness
            scolors.darkestColor = color
            scolors.darkestBlit = ch
        end
    end
    for i = 0, 15 do
        local color = 2 ^ i
        local ch = colors.toBlit(color)
        local brightness = scolors.brightnessLut[ch]
        if brightest - brightness > brightness - darkest then
            scolors.contrastBlitLut[ch] = scolors.brightestBlit
            scolors.contrastColorLut[color] = scolors.brightestColor
        else
            scolors.contrastBlitLut[ch] = scolors.darkestBlit
            scolors.contrastColorLut[color] = scolors.darkestColor
        end
    end
end

scolors.calculate()

return scolors
