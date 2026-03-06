-- rock/init.lua - Core dispatcher for the rock CLI
local ROCK_VERSION = "0.1.1"

local function setup_path()
    local rock_path = os.getenv("ROCK_PATH")
    if not rock_path then
        local src = debug.getinfo(1, "S").source
        if src:sub(1,1) == "@" then
            rock_path = src:sub(2)
        else
            local home = os.getenv("HOME")
            if home then rock_path = home .. "/.rock/lua/rock/init.lua" end
        end
    end
    
    if rock_path then
        local base = rock_path:match("(.*)/lua/rock/init.lua")
        if base then package.path = base .. "/?.lua;" .. base .. "/?/init.lua;" .. package.path end
    end
end
setup_path()

local utils = require("lua.rock.utils")
local colors = utils.colors
local spinner = utils.spinner

local project = require("lua.rock.project")
local remote = require("lua.rock.remote")
local dkjson = require("lua.rock.vendor.dkjson")

local function q(s) return "\"" .. s .. "\"" end

local commands = {}

-- Utility: Robust version comparison (SemVer style)
local function compare_versions(v1, v2)
    if not v1 or not v2 then return false end
    local function parse(v)
        local parts = {}
        for p in v:gsub("^v", ""):gmatch("%d+") do table.insert(parts, tonumber(p)) end
        return parts
    end
    local p1, p2 = parse(v1), parse(v2)
    for i = 1, math.max(#p1, #p2) do
        local n1, n2 = p1[i] or 0, p2[i] or 0
        if n1 > n2 then return true elseif n1 < n2 then return false end
    end
    return false
end

-- Utility: Paths and DB
local function get_versions_db_path() return os.getenv("HOME") .. "/.rock/versions_db.json" end
local function load_versions_db()
    local f = io.open(get_versions_db_path(), "r")
    if not f then return { sources = {}, manuals = {}, luarocks = {} } end
    local content = f:read("*a"); f:close()
    return dkjson.decode(content) or { sources = {}, manuals = {}, luarocks = {} }
end
local function save_versions_db(db)
    local f = io.open(get_versions_db_path(), "w")
    if not f then return false end
    f:write(dkjson.encode(db, { indent = true })); f:close()
    return true
end

local function get_real_path(path)
    if not path or path == "" then return nil end
    local handle = io.popen("readlink -f " .. path .. " 2>/dev/null")
    local real = handle:read("*a"); handle:close()
    return real and real:gsub("%s+", "") or path:gsub("%s+", "")
end

-- Utility: System detection
local function get_all_system_luas()
    local luas = {}
    local paths = {"/usr/bin", "/usr/local/bin"}
    for _, dir in ipairs(paths) do
        local handle = io.popen("ls " .. dir .. "/lua* 2>/dev/null")
        if handle then
            for line in handle:lines() do
                local bin_name = line:match("([^/]+)$")
                if bin_name:match("^lua%d*%.?%d*$") and not bin_name:match("luac") then
                    local v_h = io.popen(line .. " -v 2>&1")
                    local v_s = v_h:read("*a"); v_h:close()
                    local version = v_s:match("Lua (%d+%.%d+%.?%d*)")
                    if version then luas[version] = { path = line, real_path = get_real_path(line), bin = bin_name } end
                end
            end
            handle:close()
        end
    end
    return luas
end

local function get_active_info()
    local handle = io.popen("which lua 2>/dev/null")
    local path = handle:read("*a")
    handle:close()
    if not path or path == "" then return nil end
    return get_real_path(path)
end

local function get_internal_lr_version()
    local lr_bin = os.getenv("HOME") .. "/.rock/bin/luarocks"
    local h = io.popen(lr_bin .. " --version 2>/dev/null")
    if not h then return nil end
    local out = h:read("*a"); h:close()
    return out:match("luarocks (%d+%.%d+%.?%d*)")
end

local function get_latest_lr_tag(db)
    local latest = nil
    for tag in pairs(db.luarocks or {}) do
        if not latest or compare_versions(tag, latest) then latest = tag end
    end
    return latest
end

-- UI: Help screen (detailed)
local function help()
    print(colors.bold_cyan .. "\nrock " .. ROCK_VERSION .. colors.reset .. " - Lua environment and package manager")
    print("\nUsage: " .. colors.yellow .. "rock <command> [arguments]" .. colors.reset)

    print("\n" .. colors.bold_white .. "Environment Commands:" .. colors.reset)
    print(string.format("  %-25s %s", colors.green .. "about" .. colors.reset, "Show details about current stack (Lua, LuaRocks, Rock)"))
    print(string.format("  %-25s %s", colors.green .. "update" .. colors.reset, "Sync versions from lua.org and LuaRocks GitHub"))
    print(string.format("  %-25s %s", colors.green .. "upgrade-rocks" .. colors.reset, "Upgrade internal LuaRocks to the latest version"))
    print(string.format("  %-25s %s", colors.red .. "implode" .. colors.reset, "Uninstall Rock and remove all managed files"))

    print("\n" .. colors.bold_white .. "Version Management:" .. colors.reset)
    print(string.format("  %-25s %s", colors.green .. "list" .. colors.reset, "List installed and available Lua versions"))
    print(string.format("  %-25s %s", colors.green .. "install <v>" .. colors.reset, "Download and compile a specific Lua version"))
    print(string.format("  %-25s %s", colors.green .. "use <v>" .. colors.reset, "Switch Lua version (Rock or System)"))

    print("\n" .. colors.bold_white .. "Project Management:" .. colors.reset)
    print(string.format("  %-25s %s", colors.green .. "init" .. colors.reset, "Create a new rock.toml project file"))
    print(string.format("  %-25s %s", colors.green .. "save <p>[@ver]" .. colors.reset, "Install and record a dependency (supports @^1.2)"))
    print(string.format("  %-25s %s", colors.green .. "save-dev <p>[@ver]" .. colors.reset, "Install and record a dev-dependency"))
    print(string.format("  %-25s %s", colors.green .. "remove <p>" .. colors.reset, "Uninstall a package and remove from rock.toml"))
    print(string.format("  %-25s %s", colors.green .. "restore" .. colors.reset, "Install all dependencies from rock.lock/toml"))
    print(string.format("  %-25s %s", colors.green .. "run <s>" .. colors.reset, "Run a script defined in rock.toml"))
    print(string.format("  %-25s %s", colors.green .. "path" .. colors.reset, "Show environment exports for the local project"))

    print("\n" .. colors.bold_white .. "Global Options:" .. colors.reset)
    print(string.format("  %-25s %s", colors.green .. "help, --help, -h" .. colors.reset, "Show this informative screen"))
    print(string.format("  %-25s %s", colors.green .. "--version, -v" .. colors.reset, "Show current rock CLI version"))

    print("\n" .. colors.bold_white .. "Examples:" .. colors.reset)
    print(colors.dim .. "  $ rock update && rock upgrade-rocks" .. colors.reset)
    print(colors.dim .. "  $ rock install 5.4.7" .. colors.reset)
    print(colors.dim .. "  $ rock use 5.4.7" .. colors.reset)
    print(colors.dim .. "  $ rock init && rock run start" .. colors.reset)
    print("")
end

-- Commands implementation
function commands.version() print("rock version " .. ROCK_VERSION) end

function commands.update()
    io.stderr:write("Updating versions database...\n")
    local data, rocks
    
    spinner("echo 'fetching'", "Syncing with lua.org and GitHub")
    data = remote.fetch_versions()
    rocks = remote.fetch_luarocks_releases()
    
    if data then
        data.luarocks = rocks or {}
        save_versions_db(data)
        print(colors.green .. "✓ Successfully updated versions database." .. colors.reset)
    else
        print(colors.red .. "Error: Failed to fetch versions." .. colors.reset)
    end
end


function commands.about()
    local db = load_versions_db()
    print(colors.bold_cyan .. "\n--- Rock Environment ---" .. colors.reset)
    print(string.format("%-25s %s", "rock CLI", colors.bold_white .. ROCK_VERSION .. colors.reset))
    
    local active_lua_p = get_active_info()
    local lua_v = nil
    if active_lua_p then
        local lua_v_h = io.popen("lua -v 2>&1")
        if lua_v_h then
            lua_v = lua_v_h:read("*a"):match("Lua (%d+%.%d+%.?%d*)")
            lua_v_h:close()
        end
    end

    local origin = ""
    local managed_versions = {}
    local h = io.popen("ls " .. os.getenv("HOME") .. "/.rock/versions 2>/dev/null")
    if h then
        for line in h:lines() do
            local v = line:match("^lua%-(%d+%.%d+%.?%d*)$")
            if v then table.insert(managed_versions, v) end
        end
        h:close()
    end

    if active_lua_p then
        origin = active_lua_p:match("%.rock") and (colors.bold_green .. "(Rock)") or (colors.yellow .. "(System)")
    else
        if #managed_versions > 0 then
            origin = colors.yellow .. "(Inactive: " .. table.concat(managed_versions, ", ") .. " available)"
        else
            origin = colors.red .. "(None installed)"
        end
    end

    print(string.format("%-25s %s %s %s", "Lua", colors.bold_white .. (lua_v or "N/A") .. colors.reset, origin, colors.dim .. (active_lua_p or "") .. colors.reset))
    
    if not active_lua_p and #managed_versions > 0 then
        print(colors.dim .. "  (Run 'rock use " .. managed_versions[1] .. "' to activate the latest installed version)" .. colors.reset)
    elseif not active_lua_p then
        print(colors.dim .. "  (Try 'rock install <version>' to get started)" .. colors.reset)
    end

    local lr_v = get_internal_lr_version(); local latest_tag = get_latest_lr_tag(db)
    local lr_status = ""
    if lr_v and latest_tag and (latest_tag:match(lr_v) or lr_v == latest_tag:gsub("^v", "")) then lr_status = colors.green .. "(Latest)" .. colors.reset
    elseif lr_v then lr_status = colors.yellow .. "(Update available: " .. latest_tag .. ")" .. colors.reset end
    print(string.format("%-25s %s %s", "LuaRocks (Internal)", colors.bold_white .. (lr_v or "Not installed") .. colors.reset, lr_status))
    local sys_lr_h = io.popen("/usr/bin/luarocks --version 2>/dev/null")
    local sys_lr_v = sys_lr_h and sys_lr_h:read("*a"):match("luarocks (%d+%.%d+%.?%d*)") or "None"; if sys_lr_h then sys_lr_h:close() end
    print(string.format("%-25s %s %s", "LuaRocks (System)", colors.dim .. sys_lr_v .. colors.reset, colors.dim .. "[shadowed by rock]" .. colors.reset))
    print("")
end

function commands.list()
    local db = load_versions_db()
    local active_path = get_active_info()
    local sys_luas = get_all_system_luas()
    local rock_lua_installed = {}
    local h = io.popen("ls " .. os.getenv("HOME") .. "/.rock/versions 2>/dev/null")
    if h then
        for f in h:lines() do
            local v = f:match("^lua%-(%d+%.%d+%.?%d*)$")
            if v and io.open(os.getenv("HOME") .. "/.rock/versions/" .. f .. "/bin/lua", "r") then rock_lua_installed[v] = true end
        end
        h:close()
    end
    print(colors.bold_cyan .. "Installed Lua (System & Rock):" .. colors.reset)
    local all_lua = {}
    for v, d in pairs(sys_luas) do table.insert(all_lua, {v=v, p=d.real_path, t="system", raw=d.path}) end
    for v in pairs(rock_lua_installed) do table.insert(all_lua, {v=v, p=get_real_path(os.getenv("HOME").."/.rock/versions/lua-"..v.."/bin/lua"), t="rock"}) end
    table.sort(all_lua, function(a,b) return compare_versions(a.v, b.v) end)
    for _, item in ipairs(all_lua) do
        local is_active = (active_path == item.p)
        local pointer = is_active and colors.bold_green .. "->" or "  "
        local status = is_active and colors.bold_green .. "*active*" .. colors.reset or ""
        local v_str = is_active and colors.bold_green .. item.v .. colors.reset or colors.bold_white .. item.v .. colors.reset
        print(string.format("   %s %-10s %s %s", pointer, v_str, colors.dim .. "[" .. item.t .. "]" .. colors.reset, status))
    end
    print("\n" .. colors.bold_cyan .. "Available Lua (lua.org):" .. colors.reset)
    local sorted = {}
    for k in pairs(db.sources) do table.insert(sorted, k) end
    table.sort(sorted, function(a,b) return a > b end)
    local line = "   "
    for i, v in ipairs(sorted) do
        local has = (sys_luas[v] or rock_lua_installed[v]) and colors.green or ""
        line = line .. has .. string.format("%-10s", v) .. colors.reset
        if i % 6 == 0 then print(line); line = "   " end
    end
    if line ~= "   " then print(line) end
    local lr_v = get_internal_lr_version(); local latest = get_latest_lr_tag(db)
    print("\n" .. colors.bold_cyan .. "LuaRocks Status:" .. colors.reset)
    if not lr_v then print("   " .. colors.red .. "Internal LuaRocks not installed." .. colors.reset .. " Run 'rock upgrade-rocks'")
    elseif latest and not (latest:match(lr_v) or lr_v == latest:gsub("^v", "")) then print("   " .. colors.yellow .. "Update available: " .. lr_v .. " -> " .. latest .. colors.reset .. " Run 'rock upgrade-rocks'")
    else print("   " .. colors.green .. "Internal LuaRocks is up to date (" .. (lr_v or "???") .. ")" .. colors.reset) end
    print("")
end

commands["upgrade-rocks"] = function()
    local db = load_versions_db()
    local latest = get_latest_lr_tag(db)
    
    if not latest or not db.luarocks or not db.luarocks[latest] then 
        print(colors.red .. "Error: No LuaRocks version info found." .. colors.reset)
        print("Please run " .. colors.bold_white .. "rock update" .. colors.reset .. " first to sync with GitHub.")
        return 
    end

    local rel = db.luarocks[latest]
    local active_lua_p = get_active_info()
    
    if not active_lua_p then
        print(colors.red .. "Error: No active Lua environment found." .. colors.reset)
        print("Please use " .. colors.bold_white .. "rock use <version>" .. colors.reset .. " to activate a Lua version before upgrading LuaRocks.")
        return
    end

    print("Upgrading LuaRocks to " .. colors.bold_white .. latest .. colors.reset .. "...")
    local build_dir = os.getenv("HOME") .. "/.rock/luarocks/build-latest"
    os.execute("rm -rf " .. build_dir .. " && mkdir -p " .. build_dir)
    
    local tarball_path = build_dir .. "/src.tar.gz"
    print("Downloading: " .. rel.tarball)
    local download_success = os.execute("curl -L -o " .. tarball_path .. " " .. rel.tarball)
    
    if not download_success then
        print(colors.red .. "Error: Failed to download LuaRocks source." .. colors.reset)
        return
    end

    local inst_path = os.getenv("HOME") .. "/.rock/luarocks/" .. latest
    local lua_prefix = active_lua_p:match("(.*)/bin/lua")
    
    print("Configuring with Lua at: " .. (lua_prefix or "system default"))
    local cmd = "cd " .. build_dir .. " && tar -xzf src.tar.gz --strip-components=1 && ./configure --prefix=" .. inst_path
    if lua_prefix then cmd = cmd .. " --with-lua=" .. lua_prefix end
    cmd = cmd .. " && make build && make install"
    
    print("Building and installing...")
    if os.execute(cmd) then 
        os.execute("mkdir -p " .. os.getenv("HOME") .. "/.rock/bin")
        os.execute("ln -sf " .. inst_path .. "/bin/luarocks " .. os.getenv("HOME") .. "/.rock/bin/luarocks")
        print(colors.bold_green .. "✓ LuaRocks successfully upgraded to " .. latest .. "." .. colors.reset) 
    else
        print(colors.red .. "Error: Failed to build/install LuaRocks." .. colors.reset)
    end
end

function commands.use(v, sv)
    if not v then print(colors.red .. "Error: Specify version" .. colors.reset) os.exit(1) end
    local found_path = nil; local rock_bin = os.getenv("HOME") .. "/.rock/bin"
    os.execute("mkdir -p " .. rock_bin)
    
    local function set_links(target_l)
        os.execute("ln -sf " .. target_l .. " " .. rock_bin .. "/lua")
        os.execute("ln -sf " .. target_l:gsub("lua$", "luac") .. " " .. rock_bin .. "/luac")
    end

    -- 1. Check Rock
    local r_v_p = os.getenv("HOME") .. "/.rock/versions/lua-" .. v .. "/bin"
    if io.open(r_v_p .. "/lua", "r") then
        io.open(r_v_p .. "/lua", "r"):close(); found_path = r_v_p; set_links(r_v_p .. "/lua")
    else
        -- 2. Check System
        local sys = get_all_system_luas(); local target = (v == "system") and sv or v
        for version, data in pairs(sys) do if version == target or version:match("^" .. target) then found_path = data.path:match("(.*)/"); set_links(data.path); break end end
    end

    if found_path then
        local cleaned = os.getenv("PATH"):gsub("[^:]*/%.rock/versions/[^:]*/bin:?", ""):gsub("[^:]*/%.rock/bin:?", "")
        local new_path = found_path .. ":" .. rock_bin .. ":" .. cleaned
        
        local lv = v:match("^(%d+%.%d+)")
        local version_root = found_path:match("(.*)/bin")
        
        -- Use luarocks to get the perfect paths for this version
        local lr_cmd = "command luarocks --lua-dir=" .. version_root .. " --lua-version=" .. lv .. " --tree=" .. version_root .. " path"
        local lr_h = io.popen(lr_cmd .. " 2>/dev/null")
        local lr_out = lr_h and lr_h:read("*a") or ""
        if lr_h then lr_h:close() end
        
        local base_lua_path = lr_out:match('export LUA_PATH="([^"]+)"')
        local base_lua_cpath = lr_out:match('export LUA_CPATH="([^"]+)"')
        
        -- Fallback if luarocks path fails
        if not base_lua_path then
            base_lua_path = version_root .. "/share/lua/" .. lv .. "/?.lua;" .. version_root .. "/share/lua/" .. lv .. "/?/init.lua;;"
        end

        local version_share = version_root .. "/share/lua/" .. lv
        local version_lib = version_root .. "/lib/lua/" .. lv
        
        local final_global_lua_path = base_lua_path or ""
        if not final_global_lua_path:match(version_share) then
            final_global_lua_path = version_share .. "/?.lua;" .. version_share .. "/?/init.lua;" .. final_global_lua_path
        end
        if not final_global_lua_path:match(";;$") then final_global_lua_path = final_global_lua_path .. ";;" end

        local final_global_lua_cpath = base_lua_cpath or ""
        if not final_global_lua_cpath:match(version_lib) then
            final_global_lua_cpath = version_lib .. "/?.so;" .. final_global_lua_cpath
        end
        if not final_global_lua_cpath:match(";;$") then final_global_lua_cpath = final_global_lua_cpath .. ";;" end

        -- Export project-specific paths if in a project
        if io.open("rock.toml", "r") then
            io.open("rock.toml", "r"):close()
            project.path(new_path, final_global_lua_path, final_global_lua_cpath) 
        else
            print("eval: export LUA_PATH=\"" .. final_global_lua_path .. "\"")
            print("eval: export LUA_CPATH=\"" .. final_global_lua_cpath .. "\"")
            print("eval: export PATH=\"" .. new_path .. "\"")
            print("eval: export MANPATH=\"" .. version_root .. "/share/man:" .. (os.getenv("MANPATH") or "") .. "\"")
        end
        
        print("eval: export LUA_VERSION=\"" .. v .. "\"")
        print("eval: echo \"" .. colors.bold_green .. "Now using Lua " .. v .. colors.reset .. "\"")
    else
        io.stderr:write(colors.red .. "Error: Lua version " .. v .. " not found." .. colors.reset .. "\n")
        io.stderr:write(colors.yellow .. "Try running: rock install" .. colors.reset .. " to install it.\n")
        os.exit(1)
    end
end

function commands.init(mode)
    if mode == "--path" then
        local rock_root = os.getenv("HOME") .. "/.rock"
        local rock_path = os.getenv("ROCK_PATH") or (rock_root .. "/lua/rock/init.lua")
        print("export ROCK_PATH=" .. q(rock_path))
        print("export ROCK_ROOT=" .. q(rock_root))
        
        -- If there's an active version link, export its paths
        local bin_lua = rock_root .. "/bin/lua"
        local handle = io.popen("readlink -f " .. bin_lua .. " 2>/dev/null")
        local real_lua = handle and handle:read("*a"):gsub("%s+", "") or ""
        if handle then handle:close() end
        
        if real_lua ~= "" and real_lua ~= bin_lua then
            local version_root = real_lua:match("(.*)/bin/lua")
            local v = real_lua:match("lua%-(%d+%.%d+%.?%d*)")
            if version_root and v then
                local lv = v:match("^(%d+%.%d+)")
                print("export LUA_VERSION=" .. q(v))
                print(string.format("export LUA_PATH=%q", version_root .. "/share/lua/" .. lv .. "/?.lua;" .. version_root .. "/share/lua/" .. lv .. "/?/init.lua;;"))
                print(string.format("export LUA_CPATH=%q", version_root .. "/lib/lua/" .. lv .. "/?.so;;"))
                
                -- Construct path by stripping old version paths and prepending new one
                local current_path = os.getenv("PATH") or ""
                local cleaned_path = current_path:gsub("[^:]*/%.rock/versions/[^:]*/bin:?", "")
                print(string.format("export PATH=%q", version_root .. "/bin:" .. cleaned_path))
            end
        end
    elseif mode == "-" then
        local bin_path = os.getenv("HOME") .. "/.rock/bin/rock-bin"
        
        -- Hook directory changes for auto-switch
        print("cd() {")
        print("    command cd \"$@\"")
        print("    if [ -f \"rock.toml\" ]; then")
        print("        eval \"$(\"" .. bin_path .. "\" auto-switch | grep '^eval: ' | sed 's/^eval: //')\"")
        print("    fi")
        print("}")

        print("rock() {")
        print("    if [ -f \"rock.toml\" ] && [ \"$1\" != \"use\" ] && [ \"$1\" != \"auto-switch\" ] && [ \"$1\" != \"install\" ]; then")
        print("        local sw_out=$(\"" .. bin_path .. "\" auto-switch 2>&1)")
        print("        local sw_ret=$?")
        print("        if [ $sw_ret -ne 0 ]; then")
        print("            echo \"$sw_out\" | grep -v '^eval: ' >&2")
        print("            return $sw_ret")
        print("        fi")
        print("        eval \"$(echo \"$sw_out\" | grep '^eval: ' | sed 's/^eval: //')\"")
        print("    fi")
        print("    local out=$(\"" .. bin_path .. "\" \"$@\")")
        print("    while IFS= read -r line; do")
        print("        if [[ \"$line\" == eval:* ]]; then")
        print("            eval \"${line#eval: }\"")
        print("        else")
        print("            echo \"$line\"")
        print("        fi")
        print("    done <<< \"$out\"")
        print("}")
        
        print("lua() {")
        print("    if [ -f \"rock.toml\" ]; then")
        print("        local out=$(\"" .. bin_path .. "\" auto-switch)")
        print("        while IFS= read -r line; do [[ \"$line\" == eval:* ]] && eval \"${line#eval: }\"; done <<< \"$out\"")
        print("    fi")
        print("    command lua \"$@\"")
        print("}")

        print("luarocks() {")
        print("    if [ -f \"rock.toml\" ]; then")
        print("        local out=$(\"" .. bin_path .. "\" auto-switch)")
        print("        while IFS= read -r line; do [[ \"$line\" == eval:* ]] && eval \"${line#eval: }\"; done <<< \"$out\"")
        print("    fi")
        print("    if [ -n \"$LUA_VERSION\" ]; then")
        print("        local lv=$(echo $LUA_VERSION | cut -d. -f1,2)")
        print("        local ld=\"$HOME/.rock/versions/lua-$LUA_VERSION\"")
        print("        if [ -d \"$ld\" ]; then")
        print("            export LUA_INCDIR=\"$ld/include\"")
        print("            export LUA_LIBDIR=\"$ld/lib\"")
        print("            export LUA_BINDIR=\"$ld/bin\"")
        print("            export LUA_DIR=\"$ld\"")
        print("            export CFLAGS=\"-I$ld/include $CFLAGS\"")
        print("            export LDFLAGS=\"-L$ld/lib -Wl,-E $LDFLAGS\"")
        print("            export LIBS=\"-llua -lm -ldl\"")
        print("            command luarocks --lua-version=\"$lv\" --lua-dir=\"$ld\" --tree=\"$ld\" \"$@\"")
        print("            return")
        print("        fi")
        print("    fi")
        print("    command luarocks \"$@\"")
        print("}")
    else
        project.init()
    end
end

function commands.install(v, v2)
    local force = (v == "--force" or v2 == "--force")
    local version = (v and v:sub(1,1) ~= "-") and v or nil
    
    if not version then
        -- No version provided, check for rock.toml and restore project
        project.restore(force)
        return
    end

    local db = load_versions_db()
    local v_clean = version:gsub("^refman%-", "")
    local is_refman = version:match("^refman%-")
    
    local has_versions = false
    for _ in pairs(db.sources) do has_versions = true; break end
    if not has_versions then
        print(colors.red .. "Error: Local versions database is empty." .. colors.reset)
        print("Please prepare your environment by running:\n")
        print("  " .. colors.bold_white .. "$ rock update && rock upgrade-rocks" .. colors.reset)
        print("  " .. colors.bold_white .. "$ rock install " .. (version or "5.4.7") .. colors.reset)
        print("  " .. colors.bold_white .. "$ rock use " .. (version or "5.4.7") .. colors.reset .. "\n")
        os.exit(1)
    end

    local expected_sum = is_refman and db.manuals[v_clean] or db.sources[v_clean]
    
    if not expected_sum then 
        -- If it's not a known Lua version, try to install it as a global package via LuaRocks
        local lua_v = os.getenv("LUA_VERSION")
        if not lua_v then
            print(colors.red .. "Error: '" .. version .. "' is not a known Lua version, and no active Lua environment found to install as a package." .. colors.reset) 
            os.exit(1)
        end
        
        print("Installing global package '" .. version .. "' for Lua " .. lua_v .. "...")
        local lv = lua_v:match("^(%d+%.%d+)")
        local ld = os.getenv("HOME") .. "/.rock/versions/lua-" .. lua_v
        local env_prefix = string.format("LUA_INCDIR=%q LUA_LIBDIR=%q LUA_BINDIR=%q LUA_DIR=%q CFLAGS=\"-I%s/include $CFLAGS\" LDFLAGS=\"-L%s/lib -Wl,-E $LDFLAGS\" ",
            ld .. "/include", ld .. "/lib", ld .. "/bin", ld, ld, ld)
            
        local force_flag = force and " --force" or ""
        local lr_cmd = env_prefix .. "luarocks --lua-version=" .. lv .. " --lua-dir=" .. ld .. " --tree=" .. ld .. " install " .. version .. force_flag
        
        os.execute(lr_cmd)
        return
    end
    
    local v_dir = os.getenv("HOME") .. "/.rock/versions"
    local prefix = is_refman and "refman-" or "lua-"
    local tarball = v_dir .. "/" .. prefix .. v_clean .. ".tar.gz"
    local inst_path = v_dir .. "/" .. prefix .. v_clean
    
    print("Starting Lua installation process...")
    os.execute("mkdir -p " .. v_dir)
    
    if spinner("curl -L -o " .. tarball .. " https://www.lua.org/ftp/" .. prefix .. v_clean .. ".tar.gz", "Downloading Lua " .. v_clean) then
        local check_sum_cmd = "echo '" .. expected_sum .. "  " .. tarball .. "' | sha256sum --check"
        if os.execute(check_sum_cmd .. " > /dev/null 2>&1") then
            if not is_refman then 
                local build_cmd = "cd " .. v_dir .. " && tar -xzf " .. tarball .. " && cd lua-" .. v_clean .. " && make linux && make install INSTALL_TOP=" .. inst_path
                if spinner(build_cmd, "Building and Installing Lua " .. v_clean) then
                    print(colors.bold_green .. "✓ Successfully installed Lua " .. v_clean .. " at " .. inst_path .. colors.reset) 
                else
                    print(colors.red .. "Error: Failed to build Lua " .. v_clean .. colors.reset)
                end
            end
        else
            print(colors.red .. "Error: Checksum mismatch for downloaded file." .. colors.reset)
        end
    else
        print(colors.red .. "Error: Failed to download Lua " .. v_clean .. colors.reset)
    end
end

function commands.implode()
    io.stderr:write(colors.yellow .. "WARNING: This will remove Rock and all its managed files." .. colors.reset .. "\n")
    io.stderr:write("Are you sure? (y/N): ")
    local answer = io.read()
    if not answer or answer:lower() ~= "y" then
        io.stderr:write("Aborted.\n")
        return
    end

    local home = os.getenv("HOME")
    if not home then
        io.stderr:write(colors.red .. "Error: HOME environment variable not set." .. colors.reset .. "\n")
        return
    end
    
    -- 1. Remove shell profile entries
    local profiles = { home .. "/.bashrc", home .. "/.zshrc", home .. "/.profile" }
    for _, profile in ipairs(profiles) do
        local f = io.open(profile, "r")
        if f then
            local content = f:read("*a")
            f:close()
            -- Remove block between # rock configuration and # end rock configuration
            -- Using [%s%S]- to match across newlines and handling potential double newlines
            local new_content = content:gsub("\n?# rock configuration[%s%S]-# end rock configuration\n?", "")
            
            if new_content ~= content then
                local fw = io.open(profile, "w")
                if fw then
                    fw:write(new_content)
                    fw:close()
                    io.stderr:write(colors.green .. "✓ Cleaned up " .. profile .. colors.reset .. "\n")
                end
            end
        end
    end

    -- 2. Remove ROCK_ROOT
    os.execute("rm -rf " .. home .. "/.rock")

    io.stderr:write(colors.bold_green .. "Rock has been successfully uninstalled." .. colors.reset .. "\n")
    print("eval: unset -f rock")
end

commands["auto-switch"] = function()
    local v = project.get_lua_version()
    if v then
        local r_v_p = os.getenv("HOME") .. "/.rock/versions/lua-" .. v .. "/bin/lua"
        local f = io.open(r_v_p, "r")
        if f then
            f:close()
            if v ~= os.getenv("LUA_VERSION") then
                commands.use(v)
            end
        else
            io.stderr:write(colors.red .. "Error: Lua version " .. v .. " (required by rock.toml) is not installed.\n" .. colors.reset)
            io.stderr:write(colors.yellow .. "To set up your environment, please run:\n" .. colors.reset)
            io.stderr:write("  " .. colors.bold_white .. "$ rock update && rock upgrade-rocks\n" .. colors.reset)
            io.stderr:write("  " .. colors.bold_white .. "$ rock install " .. v .. "\n" .. colors.reset)
            io.stderr:write("  " .. colors.bold_white .. "$ rock install\n" .. colors.reset)
            os.exit(1)
        end
    end
end

function commands.path() project.path() end
function commands.save(p, dev) project.save(p, dev) end
function commands.remove(p) project.remove(p) end
function commands.restore(force) project.restore(force) end
function commands.run(s) project.run(s) end

-- Main entry
local cmd = arg[1]
if not cmd or cmd == "help" or cmd == "--help" or cmd == "-h" then help()
elseif cmd == "about" then commands.about()
elseif cmd == "restore" then commands.restore(arg[2] == "--force")
elseif cmd == "remove" then commands.remove(arg[2])
elseif cmd == "implode" then commands.implode()

elseif cmd == "run" then commands.run(arg[2])
elseif commands[cmd] then commands[cmd](arg[2], arg[3])
elseif cmd == "save-dev" then commands.save(arg[2], true)
elseif cmd == "--version" or cmd == "-v" then commands.version()
else print(colors.red .. "Unknown command: " .. cmd .. colors.reset); help(); os.exit(1) end
