local supdate = {}

---@param url string
---@param fn string
---@return {version:string,build:string,save:function}?
---@return string
function supdate.checkUpdate(url, fn)
    local data = {}
    local response, reason = http.get(url)
    if not response then
        return nil, reason
    end

    local content = assert(response.readAll(), "No content?")
    response.close()

    local versionMatchStr = "local version = \"([%d%a%.%-]+)\""
    local version = content:match(versionMatchStr)
    local buildMatchStr = "local buildVersion = '([%d%a/%-]+)'"
    local build = content:match(buildMatchStr)
    if not (version and build) then
        return nil, "No version/build information found!"
    end
    data.version = version
    data.build = build

    function data.save()
        local f = assert(fs.open(fn, "w"))
        f.write(content)
        f.close()
    end

    return data, ""
end

---@param url string
---@param version string
---@param buildVersion string
function supdate.checkUpdatePopup(url, version, buildVersion)
    local mbar = require("libs.mbar")
    local update, reason = supdate.checkUpdate(url, shell.getRunningProgram())
    if not update then
        mbar.popup("Failed", reason, { "Ok" }, 15)
        return
    end
    if version ~= update.version or buildVersion ~= update.build then
        local fstr = "%1s %-8s|%-8s"
        local s = fstr:format("", "Version", "Build") .. "\n"
        s = s .. fstr:format("O", version, buildVersion) .. "\n"
        s = s .. fstr:format("N", update.version, update.build)
        local choice = mbar.popup("Update?", s, { "Cancel", "Update" }, 22)
        if choice == 2 then
            update.save()
            mbar.popup("Updated!", "Restart the program to use the new version.", { "Ok" }, 20)
        end
    end
end

return supdate
