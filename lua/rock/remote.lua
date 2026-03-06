-- lua/rock/remote.lua - Fetches data from lua.org and GitHub
local dkjson = require("lua.rock.vendor.dkjson")
local remote = {}

function remote.fetch_versions()
    print("Fetching available Lua versions from lua.org...")
    local handle = io.popen("curl -s https://www.lua.org/ftp/")
    if not handle then return nil end
    local html = handle:read("*a")
    handle:close()

    local data = { sources = {}, manuals = {} }
    for version, checksum in html:gmatch('HREF="lua%-(%d+%.%d+%.?%d*)%.tar%.gz".-CLASS="sum">(%x+)</TD>') do
        data.sources[version] = checksum
    end
    for type, version, checksum in html:gmatch('HREF="(refman)%-(%d+%.%d+)%.tar%.gz".-CLASS="sum">(%x+)</TD>') do
        data.manuals[version] = checksum
    end
    return data
end

function remote.fetch_luarocks_releases()
    print("Fetching LuaRocks releases from GitHub...")
    local url = "https://api.github.com/repos/luarocks/luarocks/releases?per_page=30"
    local handle = io.popen("curl -s " .. url)
    if not handle then return nil end
    local response = handle:read("*a")
    handle:close()

    local json = dkjson.decode(response)
    if not json then return nil end

    local releases = {}
    for _, rel in ipairs(json) do
        local tag = rel.tag_name
        local asc_url = nil
        local tar_url = rel.tarball_url
        
        -- Look for .asc in assets
        if rel.assets then
            for _, asset in ipairs(rel.assets) do
                if asset.name:match("%.asc$") then
                    asc_url = asset.browser_download_url
                end
                if asset.name:match("%.tar%.gz$") and not asset.name:match("win32") then
                    tar_url = asset.browser_download_url
                end
            end
        end
        
        releases[tag] = {
            tag = tag,
            tarball = tar_url,
            asc = asc_url
        }
    end
    return releases
end

return remote
