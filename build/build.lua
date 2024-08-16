-- Very simple Lua program packager.
-- This program takes in a single filename, your entry point.
-- Then it will scan that program for all of its requires, and all of its require-es requires.
-- After doing this for all required files it packages them up into a single file.

-- There are a few special rules you MUST follow for this program to work
-- 1) The FIRST line of ALL files you import must be an initialization of your module's table.
--- For example, `local data = {}`
--- 1.a) This variable name MUST be the same variable name used everywhere this module is.
-- 2) The LAST code line of your file MUST be a return, returning this module table.
--- For example, `return data`
-- 3) EVERYWHERE a file is imported it MUST be imported using the same module name AND variable name.

local args = { ... }

local allowed_args = {
    mini = { type = "flag", description = "Remove whitespace + comments" },
    version = { type = "value", description = "Replace any '##VERSION' strings with this" }
}

-- the arguments without - before them
local var_args = {}

-- the recognized arguments passed into the program
local given_args = {}
for i = 1, #args do
    local v = args[i]
    if string.sub(v, 1, 1) == "-" then
        local full_arg_str = string.sub(v, 2)
        for arg_name, arg_info in pairs(allowed_args) do
            if string.sub(full_arg_str, 1, arg_name:len()) == arg_name then
                -- this is an argument that is allowed
                if arg_info.type == "value" then
                    local arg_arg_str = string.sub(full_arg_str, arg_name:len() + 1)
                    assert(arg_arg_str:sub(1, 1) == "=" and arg_arg_str:len() > 1, "Expected =<value> on arg " ..
                        arg_name)
                    given_args[arg_name] = arg_arg_str:sub(2)
                elseif arg_info.type == "flag" then
                    given_args[arg_name] = true
                    break
                end
            end
        end
    else
        table.insert(var_args, v)
    end
end
if given_args.help or #var_args < 2 then
    print("build <input> <output>")
    for k, v in pairs(allowed_args) do
        local arg_label = k
        if v.type == "value" then
            arg_label = arg_label .. "=?"
        end
        print(("%-10s|%s"):format(arg_label, v.description))
    end
    return
end

local inputfn = var_args[1]
local outputfn = var_args[2]

local minifyish = given_args.mini

local matchRequireStr = "local ([%a_%d]+) *= *require%(? *['\"]([%a%d%p]+)['\"]%)?"
local matchReturnStr = "^return ([%a_%d]+)"
local matchCommentStr = "%-%-.-$"
local matchInlineCommentStr = "%-%-%[%[.-%]%]"
local matchWhitespaceStr = "^ +"
local matchVersionString = "'##VERSION'"

---@class RequiredFile
---@field variable string
---@field module string
---@field filename string
---@field content string
---@field firstline string
---@field requires table<string,string> module,module
---@field temporary boolean?
---@field permanant boolean?

---@type RequiredFile[]
local requiredFiles = {}

---@type table<string,RequiredFile>
local moduleLUT = {}

---@type table<string,RequiredFile>
local filenameLUT = {}

local universalModules = {
    ["cc.shell.completion"] = true,
    ["cc.strings"] = true,
    ["cc.audio.dfpwm"] = true,
    ["cc.completion"] = true,
    ["cc.image.nft"] = true,
    ["cc.pretty"] = true,
    ["cc.require"] = true,
}

local function moduleToFilename(module)
    return module:gsub("%.", "/") .. ".lua"
end

---@type string[]
local toProcess = {}

filenameLUT[inputfn] = {
    requires = {},
    filename = inputfn,
    content = "",
    firstline = "",
    module = "",
    variable = "",
}

---@param byfn string
---@param var string
---@param module string
local function requireFile(byfn, var, module)
    if filenameLUT[byfn] then
        filenameLUT[byfn].requires[module] = module
    end
    if moduleLUT[module] then
        assert(moduleLUT[module].variable == var,
            ("Module %s imported by two different names [%s,%s]."):format(module, moduleLUT[module].variable, var))
        return
    end
    local fn = moduleToFilename(module)
    local required = {
        variable = var,
        module = module,
        filename = fn,
        requires = {}
    }
    requiredFiles[#requiredFiles + 1] = required
    moduleLUT[module] = required
    filenameLUT[fn] = required
    toProcess[#toProcess + 1] = fn
end

local function processFile(fn, processFirst)
    local output = ""
    local f = assert(fs.open(fn, "r"))
    local s = f.readLine(true)
    local firstline = nil
    if not processFirst then
        firstline = s
        s = f.readLine(true)
    end
    while s do
        local var, module = s:match(matchRequireStr)
        if var and module and not universalModules[module] then
            requireFile(fn, var, module)
        elseif not s:match(matchReturnStr) then
            local ns = s
            if minifyish then
                ns = s:gsub(matchWhitespaceStr, "")
                    :gsub(matchInlineCommentStr, "")
                    :gsub(matchCommentStr, "")
            end
            if given_args.version then
                ns = ns:gsub(matchVersionString, ("'%s'"):format(given_args.version))
            end
            output = output .. ns
        end
        s = f.readLine(true)
    end
    f.close()
    return firstline, output
end

local moduleIncludeOrder = {}

-- https://en.wikipedia.org/wiki/Topological_sorting#Depth-first_search
---@param module RequiredFile
local function visit(module)
    if module.permanant then
        return
    elseif module.temporary then
        print("Warning: Cyclic dependency tree")
        print("This may or may not be a problem.")
        return
    end
    module.temporary = true

    for mod, info in pairs(module.requires) do
        local depModule = moduleLUT[mod]
        if depModule then
            visit(depModule)
        else
            error(("Module %s requires %s, which is not present."):format(module.filename, depModule.filename))
        end
    end

    module.temporary = nil
    module.permanant = true
    table.insert(moduleIncludeOrder, module)
end

local function getUnmarked()
    for k, v in pairs(requiredFiles) do
        if not v.permanant then
            return v
        end
    end
    return nil
end

local unmarked = getUnmarked()
while unmarked do
    visit(unmarked)
    unmarked = getUnmarked()
end

for k, v in pairs(requiredFiles) do
    v.permanant = nil
end

local function buildFile(fn)
    local _, baseFile = processFile(fn, true)
    while #toProcess > 0 do
        local processingfn = table.remove(toProcess, 1)
        local firstline, content = processFile(processingfn)
        filenameLUT[processingfn].firstline = firstline --[[@as string]]
        filenameLUT[processingfn].content = content
    end
    visit(filenameLUT[fn])
    local f = assert(fs.open(outputfn, "w"))
    for k, v in ipairs(moduleIncludeOrder) do
        f.writeLine(v.firstline)
    end
    for k, v in ipairs(moduleIncludeOrder) do
        f.writeLine(v.content)
    end
    f.writeLine(baseFile)
    f.close()
end

buildFile(inputfn)
