-- rock/project.lua - Handles rock.json, rock.lock.json and project metadata
local json = require("lua.rock.vendor.dkjson")
local utils = require("lua.rock.utils")
local colors = utils.colors
local spinner = utils.spinner

local project = {}

local PROJECT_FILE = "rock.json"
local LOCK_FILE = "rock.lock.json"
local JSON_OBJECT_META = { __jsontype = "object" }

local function file_exists(filename)
    local f = io.open(filename, "r")
    if f then f:close(); return true end
    return false
end

local function read_json(filename)
    local f = io.open(filename, "r")
    if not f then return nil end
    local content = f:read("*a")
    f:close()
    return json.decode(content)
end

local function mark_empty_tables_as_objects(value)
    if type(value) ~= "table" then return end
    if next(value) == nil then
        setmetatable(value, JSON_OBJECT_META)
        return
    end
    for _, child in pairs(value) do
        mark_empty_tables_as_objects(child)
    end
end

local function write_json(filename, data)
    local f = io.open(filename, "w")
    if not f then return false end
    mark_empty_tables_as_objects(data)
    f:write(json.encode(data, { indent = true }))
    f:write("\n")
    f:close()
    return true
end

local function read_project()
    return read_json(PROJECT_FILE)
end

local function read_lock()
    return read_json(LOCK_FILE)
end

local function project_exists()
    return file_exists(PROJECT_FILE)
end

local function read_rockrc()
    local f = io.open(".rockrc", "r")
    if not f then return { configs = {}, pkg_flags = {} } end
    local configs = {}
    local pkg_flags = {}
    for line in f:lines() do
        -- Check for global configs like modules_path = "vendor"
        local key, val = line:match("^%s*([^%s:]+)%s*=%s*\"?([^\"]+)\"?$")
        if key then
            configs[key] = val
        else
            -- Check for package flags like rio: MYSQL_INCDIR=...
            local pkg, args = line:match("^([^:]+):%s*(.*)$")
            if pkg then pkg_flags[pkg] = args end
        end
    end
    f:close()
    return { configs = configs, pkg_flags = pkg_flags }
end

local function write_rockrc(data)
    local f = io.open(".rockrc", "w")
    if not f then return end
    -- Write global configs first
    if data.configs then
        for k, v in pairs(data.configs) do
            f:write(k .. " = " .. string.format("%q", v) .. "\n")
        end
    end
    -- Write package flags
    if data.pkg_flags then
        for pkg, args in pairs(data.pkg_flags) do
            f:write(pkg .. ": " .. args .. "\n")
        end
    end
    f:close()
end

local function get_modules_path()
    local rc = read_rockrc()
    return rc.configs.modules_path or "lua_modules"
end

local function starts_with(value, prefix)
    return prefix and value:sub(1, #prefix) == prefix
end

local function clean_separated_paths(value, separator, should_remove)
    local cleaned = {}
    for segment in (value or ""):gmatch("([^" .. separator .. "]+)") do
        if segment ~= "" and not should_remove(segment) then
            table.insert(cleaned, segment)
        end
    end
    return table.concat(cleaned, separator)
end

local function is_project_bin_path(segment, project_root, modules_path)
    if project_root and modules_path and segment == project_root .. "/" .. modules_path .. "/bin" then
        return true
    end

    local active_root = os.getenv("ROCK_PROJECT_ROOT")
    local active_modules = os.getenv("ROCK_PROJECT_MODULES")
    if active_root and active_modules and segment == active_root .. "/" .. active_modules .. "/bin" then
        return true
    end

    return segment:match("/lua_modules/bin$") ~= nil
end

local function is_project_lua_path(segment, project_root, modules_path)
    if project_root and modules_path and starts_with(segment, project_root .. "/" .. modules_path .. "/") then
        return true
    end

    local active_root = os.getenv("ROCK_PROJECT_ROOT")
    local active_modules = os.getenv("ROCK_PROJECT_MODULES")
    if active_root and active_modules and starts_with(segment, active_root .. "/" .. active_modules .. "/") then
        return true
    end

    return segment:match("/lua_modules/share/lua/") ~= nil or segment:match("/lua_modules/lib/lua/") ~= nil
end

local function clean_project_path(value, project_root, modules_path)
    return clean_separated_paths(value, ":", function(segment)
        return is_project_bin_path(segment, project_root, modules_path)
    end)
end

local function clean_project_lua_paths(value, project_root, modules_path)
    return clean_separated_paths(value, ";", function(segment)
        return is_project_lua_path(segment, project_root, modules_path)
    end)
end

function project.init()
    local name = os.getenv("PWD"):match("([^/]+)$") or "my-lua-project"
    
    -- Detect current active Lua version (Full version like 5.1.5)
    local lua_v = nil
    local handle = io.popen("lua -v 2>&1")
    if handle then
        lua_v = handle:read("*a"):match("Lua (%d+%.%d+%.?%d*)")
        handle:close()
    end

    local default_data = {
        name = name,
        version = "1.0.0",
        main = "main.lua",
        description = "",
        lua = lua_v or "5.4"
    }

    if project_exists() then
        print("Error: rock.json already exists in this directory.")
        return
    end

    default_data.scripts = {}
    default_data.dependencies = {}
    default_data.devDependencies = {}

    if not write_json(PROJECT_FILE, default_data) then
        print("Error: Could not create rock.json")
        return
    end

    print("Created rock.json successfully with Lua " .. (lua_v or "5.4") .. "!")
end

local function get_installed_version(package)
    local modules_path = get_modules_path()
    local handle = io.popen("luarocks show " .. package .. " --mversion --tree=" .. modules_path .. " 2>/dev/null")
    if not handle then return nil end
    local version = handle:read("*a")
    handle:close()
    if version then return version:gsub("%s+", "") end
    return nil
end

local function write_project_json(data)
    data.name = data.name or ""
    data.version = data.version or "1.0.0"
    data.main = data.main or "main.lua"
    data.description = data.description or ""
    data.lua = data.lua or "5.4"
    data.scripts = data.scripts or {}
    data.dependencies = data.dependencies or {}
    data.devDependencies = data.devDependencies or {}
    return write_json(PROJECT_FILE, data)
end

function project.save(package_arg, ...)
    local args = {...}
    local is_dev = false
    local extra_flags = ""
    
    for _, a in ipairs(args) do
        if a == true or a == "--dev" then
            is_dev = true
        elseif type(a) == "string" then
            extra_flags = extra_flags .. " " .. a
        end
    end

    local data = read_project()
    if not data then
        print("Error: No rock.json found. Run 'rock init' first.")
        return
    end

    local package = package_arg:match("^([^@]+)")
    local requested_version = package_arg:match("@(.+)$") or "latest"

    print("Installing " .. package .. (requested_version ~= "latest" and (" version " .. requested_version) or "") .. " via LuaRocks...")
    
    local luarocks_ver = ""
    local manifest_ver = "latest"

    if requested_version ~= "latest" then
        manifest_ver = requested_version
        luarocks_ver = requested_version:gsub("^%^", ""):gsub("^~", "")
    end

    local env_prefix = ""
    local lua_ver_flag = ""
    local lua_dir_flag = ""
    if data.lua then
        local major_minor = data.lua:match("^(%d+%.%d+)")
        if major_minor then lua_ver_flag = " --lua-version=" .. major_minor end

        local home = os.getenv("HOME")
        local ld = home .. "/.rock/versions/lua-" .. data.lua
        if io.open(ld .. "/bin/lua", "r") then
            io.open(ld .. "/bin/lua", "r"):close()
            lua_dir_flag = " --lua-dir=" .. ld
            local pc_path = ld .. "/lib/pkgconfig"
            local old_pc = os.getenv("PKG_CONFIG_PATH") or ""
            env_prefix = string.format("LUA_INCDIR=%q LUA_LIBDIR=%q LUA_BINDIR=%q LUA_DIR=%q PKG_CONFIG_PATH=%q CFLAGS=\"-I%s/include $CFLAGS\" LDFLAGS=\"-L%s/lib -Wl,-E -llua $LDFLAGS\" LIBS=\"-llua -lm -ldl\" LUA_LIBS=\"-llua -lm -ldl\" LUA_LIB=\"-llua\" ",
                ld .. "/include", ld .. "/lib", ld .. "/bin", ld, pc_path .. (old_pc ~= "" and (":" .. old_pc) or ""), ld, ld)
        end
    end

    local modules_path = get_modules_path()
    local cmd = env_prefix .. "luarocks" .. lua_ver_flag .. lua_dir_flag .. " install --tree=" .. modules_path .. " " .. package .. (luarocks_ver ~= "" and (" " .. luarocks_ver) or "") .. extra_flags
    local success = spinner(cmd, "Installing " .. package .. (requested_version ~= "latest" and (" (" .. requested_version .. ")") or ""))

    if success then
        -- Persist flags if they were provided
        if extra_flags ~= "" then
            local rc = read_rockrc()
            rc.pkg_flags[package] = extra_flags:gsub("^%s*", "")
            write_rockrc(rc)
        end

        local section = is_dev and "devDependencies" or "dependencies"
        data[section] = data[section] or {}
        
        -- Get exact version installed for lockfile
        local exact_version = get_installed_version(package)
        
        -- Update rock.json.
        data[section][package] = manifest_ver
        if write_project_json(data) then
            print("Successfully saved " .. package .. " (" .. manifest_ver .. ") to " .. section)
        else
            print("Error: Could not update rock.json")
        end

        -- Update rock.lock.json
        local lock_data = read_lock() or { dependencies = {} }
        lock_data.lua = data.lua -- Sync Lua version to lock
        lock_data.dependencies[package] = {
            version = exact_version or manifest_ver,
            section = section
        }
        if write_json(LOCK_FILE, lock_data) then
            print("Updated rock.lock.json with exact version and Lua info.")
        else
            print("Error: Could not update rock.lock.json")
        end
    else
        print("Error: Failed to install " .. package)
    end
end

function project.restore(force, verbose)
    local lock_data = read_lock()
    local data = read_project()
    
    if not data then
        print("Error: No rock.json found.")
        return
    end

    -- 1. Check for Lua version in rock.json
    if data.lua then
        local active_v = os.getenv("LUA_VERSION")
        if active_v and active_v ~= data.lua and not force then
            io.stderr:write(colors.red .. "Error: Version mismatch.\n" .. colors.reset)
            io.stderr:write("Project requires Lua " .. colors.bold_white .. data.lua .. colors.reset .. " but you are using " .. colors.bold_white .. active_v .. colors.reset .. ".\n")
            io.stderr:write(colors.yellow .. "To set up your environment, please run:\n" .. colors.reset)
            io.stderr:write("  " .. colors.bold_white .. "$ rock update && rock upgrade-rocks\n" .. colors.reset)
            io.stderr:write("  " .. colors.bold_white .. "$ rock install " .. data.lua .. "\n" .. colors.reset)
            io.stderr:write("  " .. colors.bold_white .. "$ rock use " .. data.lua .. "\n" .. colors.reset)
            io.stderr:write(colors.dim .. "(Or use --force to bypass this check)\n" .. colors.reset)
            os.exit(1)
        end

        print("Project requires Lua " .. data.lua)
        local home = os.getenv("HOME")
        local lua_path = home .. "/.rock/versions/lua-" .. data.lua
        if not io.open(lua_path .. "/bin/lua", "r") then
            print("Lua " .. data.lua .. " not installed. Installing now...")
            os.execute("rock-bin install " .. data.lua)
        else
            io.open(lua_path .. "/bin/lua", "r"):close()
            print("✓ Lua " .. data.lua .. " is already installed.")
        end

        -- Ensure Lua version is in the lockfile
        if not lock_data or lock_data.lua ~= data.lua then
            local new_lock = lock_data or { dependencies = {} }
            new_lock.lua = data.lua
            write_json(LOCK_FILE, new_lock)
            lock_data = new_lock
        end

        -- Emit activation command for the shell wrapper
        print("eval: rock use " .. data.lua)
    end

    -- 2. Restore packages
    local deps_to_install = {}
    local lock_has_deps = false
    if lock_data and lock_data.dependencies and next(lock_data.dependencies) then
        lock_has_deps = true
        print("Restoring dependencies from rock.lock.json...")
        for name, info in pairs(lock_data.dependencies) do
            if type(info) == "table" then
                table.insert(deps_to_install, { name = name, version = info.version })
            else
                table.insert(deps_to_install, { name = name, version = info })
            end
        end
    end

    if not lock_has_deps then
        print("No dependencies found in rock.lock.json (or file missing). Checking project manifest...")
        local sections = {"dependencies", "devDependencies"}
        for _, section in ipairs(sections) do
            if data[section] and type(data[section]) == "table" then
                for name, ver in pairs(data[section]) do
                    table.insert(deps_to_install, { name = name, version = ver })
                end
            end
        end
    end

    local env_prefix = ""
    local lua_ver_flag = ""
    local lua_dir_flag = ""
    if data.lua then
        local major_minor = data.lua:match("^(%d+%.%d+)")
        if major_minor then lua_ver_flag = " --lua-version=" .. major_minor end

        local home = os.getenv("HOME")
        local ld = home .. "/.rock/versions/lua-" .. data.lua
        if io.open(ld .. "/bin/lua", "r") then
            io.open(ld .. "/bin/lua", "r"):close()
            lua_dir_flag = " --lua-dir=" .. ld
            local pc_path = ld .. "/lib/pkgconfig"
            local old_pc = os.getenv("PKG_CONFIG_PATH") or ""
            env_prefix = string.format("LUA_INCDIR=%q LUA_LIBDIR=%q LUA_BINDIR=%q LUA_DIR=%q PKG_CONFIG_PATH=%q CFLAGS=\"-I%s/include $CFLAGS\" LDFLAGS=\"-L%s/lib -Wl,-E -llua $LDFLAGS\" LIBS=\"-llua -lm -ldl\" LUA_LIBS=\"-llua -lm -ldl\" LUA_LIB=\"-llua\" ",
                ld .. "/include", ld .. "/lib", ld .. "/bin", ld, pc_path .. (old_pc ~= "" and (":" .. old_pc) or ""), ld, ld)
        end
    end

    if #deps_to_install == 0 then
        print("No dependencies to install.")
    else
        local modules_path = get_modules_path()
        local rc = read_rockrc()
        print(string.format("Installing %d dependencies...", #deps_to_install))
        
        -- Use internal luarocks if available
        local lr_bin = "luarocks"
        local internal_lr = os.getenv("HOME") .. "/.rock/bin/luarocks"
        local f_lr = io.open(internal_lr, "r")
        if f_lr then f_lr:close(); lr_bin = internal_lr end

        for _, dep in ipairs(deps_to_install) do
            local ver_cmd = ""
            if dep.version ~= "latest" then
                ver_cmd = dep.version:gsub("^%^", ""):gsub("^~", "")
            end
            local force_flag = force and "--force " or ""
            local extra_args = rc.pkg_flags[dep.name] or ""
            if extra_args ~= "" then extra_args = " " .. extra_args end

            -- Optimized command with better dependency handling
            local cmd = env_prefix .. lr_bin .. lua_ver_flag .. lua_dir_flag .. " install --tree=" .. modules_path .. " " .. force_flag .. "--deps-mode=all " .. dep.name .. " " .. ver_cmd .. extra_args
            if verbose then cmd = cmd .. " --verbose" end

            spinner(cmd, "  Installing " .. dep.name .. (dep.version ~= "latest" and (" (" .. dep.version .. ")") or ""), verbose)
        end

        -- Update rock.lock.json with exact versions after restoration
        local final_lock_data = { lua = data.lua, dependencies = {} }
        for _, dep in ipairs(deps_to_install) do
            local exact = get_installed_version(dep.name)
            final_lock_data.dependencies[dep.name] = { version = exact or dep.version }
        end
        write_json(LOCK_FILE, final_lock_data)

        print("Done restoring dependencies and updated rock.lock.json.")
        print("eval: hash -r 2>/dev/null || true")
    end
end

local function get_env_paths()
    local modules_path = get_modules_path()
    local h = io.popen("luarocks path --tree=" .. modules_path .. " 2>/dev/null")
    if not h then return {} end
    local out = h:read("*a")
    h:close()
    
    local env = {}
    for var, val in out:gmatch("export ([^=]+)=\"([^\"]+)\"") do
        env[var] = val
    end
    return env
end

function project.remove(package)
    local data = read_project()
    if not data then
        print("Error: No rock.json found.")
        return
    end

    local found = false
    local sections = {"dependencies", "devDependencies"}
    for _, section in ipairs(sections) do
        if data[section] and data[section][package] then
            data[section][package] = nil
            found = true
            break
        end
    end

    if not found then
        print(colors.red .. "Error: Package '" .. package .. "' not found in rock.json" .. colors.reset)
        return
    end

    local modules_path = get_modules_path()
    local cmd = "luarocks remove --tree=" .. modules_path .. " " .. package
    if spinner(cmd, "Removing " .. package) then
        -- Update rock.json
        if write_project_json(data) then
            print("Successfully removed " .. package .. " from rock.json")
        end

        -- Update rock.lock.json
        local lock_data = read_lock()
        if lock_data and lock_data.dependencies and lock_data.dependencies[package] then
            lock_data.dependencies[package] = nil
            write_json(LOCK_FILE, lock_data)
            print("Updated rock.lock.json.")
        end
    else
        print(colors.red .. "Error: Failed to remove package via LuaRocks." .. colors.reset)
    end
end

function project.get_lua_version()
    local data = read_project()
    return data and data.lua
end

function project.path(base_path, global_lua_path, global_lua_cpath)
    local pwd = os.getenv("PWD")
    local modules_path = get_modules_path()
    local local_bin_dir = pwd .. "/" .. modules_path .. "/bin"
    
    local local_lua_path = ""
    local local_lua_cpath = ""
    
    local share_h = io.popen("ls " .. pwd .. "/" .. modules_path .. "/share/lua 2>/dev/null")
    if share_h then
        for v in share_h:lines() do
            if v:match("^%d+%.%d+$") then
                local_lua_path = local_lua_path .. pwd .. "/" .. modules_path .. "/share/lua/" .. v .. "/?.lua;" .. pwd .. "/" .. modules_path .. "/share/lua/" .. v .. "/?/init.lua;"
            end
        end
        share_h:close()
    end
    
    local lib_h = io.popen("ls " .. pwd .. "/" .. modules_path .. "/lib/lua 2>/dev/null")
    if lib_h then
        for v in lib_h:lines() do
            if v:match("^%d+%.%d+$") then
                local_lua_cpath = local_lua_cpath .. pwd .. "/" .. modules_path .. "/lib/lua/" .. v .. "/?.so;"
            end
        end
        lib_h:close()
    end

    -- Clean up any existing rock-managed paths to prevent version bleed.
    local current_lua_path = os.getenv("LUA_PATH") or ""
    current_lua_path = current_lua_path:gsub("[^;]*/%.rock/versions/[^;]*/share/lua/[^;]*/%?.lua;?", "")
    current_lua_path = current_lua_path:gsub("[^;]*/%.rock/versions/[^;]*/share/lua/[^;]*/%?/init.lua;?", "")
    current_lua_path = clean_project_lua_paths(current_lua_path, pwd, modules_path)

    local current_lua_cpath = os.getenv("LUA_CPATH") or ""
    current_lua_cpath = current_lua_cpath:gsub("[^;]*/%.rock/versions/[^;]*/lib/lua/[^;]*/%?.so;?", "")
    current_lua_cpath = clean_project_lua_paths(current_lua_cpath, pwd, modules_path)

    local final_lua_path = local_lua_path .. (global_lua_path or current_lua_path)
    if final_lua_path ~= "" and not final_lua_path:match(";;$") then
        if final_lua_path:sub(-1) ~= ";" then final_lua_path = final_lua_path .. ";" end
        final_lua_path = final_lua_path .. ";"
    end
    
    local final_lua_cpath = local_lua_cpath .. (global_lua_cpath or current_lua_cpath)
    if final_lua_cpath ~= "" and not final_lua_cpath:match(";;$") then
        if final_lua_cpath:sub(-1) ~= ";" then final_lua_cpath = final_lua_cpath .. ";" end
        final_lua_cpath = final_lua_cpath .. ";"
    end
    
    local clean_path = clean_project_path(base_path or os.getenv("PATH") or "", pwd, modules_path)
    local final_path = local_bin_dir .. ":" .. clean_path

    print(string.format("eval: export LUA_PATH=%q", final_lua_path))
    print(string.format("eval: export LUA_CPATH=%q", final_lua_cpath))
    print(string.format("eval: export PATH=%q", final_path))
    print(string.format("eval: export ROCK_PROJECT_ROOT=%q", pwd))
    print(string.format("eval: export ROCK_PROJECT_MODULES=%q", modules_path))
end

function project.deactivate()
    local clean_lua_path = clean_project_lua_paths(os.getenv("LUA_PATH") or "")
    local clean_lua_cpath = clean_project_lua_paths(os.getenv("LUA_CPATH") or "")
    local clean_path = clean_project_path(os.getenv("PATH") or "")

    print(string.format("eval: export LUA_PATH=%q", clean_lua_path))
    print(string.format("eval: export LUA_CPATH=%q", clean_lua_cpath))
    print(string.format("eval: export PATH=%q", clean_path))
    print("eval: unset ROCK_PROJECT_ROOT")
    print("eval: unset ROCK_PROJECT_MODULES")
end

function project.run(script_name)
    local data = read_project()
    if not data or not data.scripts then
        print("Error: No scripts defined in rock.json")
        return
    end

    -- 1. PRE-CHECK: Ensure required Lua version is installed
    if data.lua then
        local home = os.getenv("HOME")
        local lua_bin = home .. "/.rock/versions/lua-" .. data.lua .. "/bin/lua"
        local f_lua = io.open(lua_bin, "r")
        if not f_lua then
            io.stderr:write(colors.red .. "Error: Lua version " .. data.lua .. " (required by rock.json) is not installed.\n" .. colors.reset)
            io.stderr:write(colors.yellow .. "To set up your environment, please run:\n" .. colors.reset)
            io.stderr:write("  " .. colors.bold_white .. "$ rock update && rock upgrade-rocks\n" .. colors.reset)
            io.stderr:write("  " .. colors.bold_white .. "$ rock install " .. data.lua .. "\n" .. colors.reset)
            io.stderr:write("  " .. colors.bold_white .. "$ rock install\n" .. colors.reset)
            os.exit(1)
        else
            f_lua:close()
        end
    end

    if not script_name then
        print("Available scripts:")
        local sorted_names = {}
        for name in pairs(data.scripts) do table.insert(sorted_names, name) end
        table.sort(sorted_names)
        for _, name in ipairs(sorted_names) do
            print(string.format("  - %-15s %s", name, data.scripts[name]))
        end
        return
    end

    local command = data.scripts[script_name]
    if not command then
        print("Error: Script '" .. script_name .. "' not found in rock.json")
        return
    end

    -- Setup local environment
    local pwd = os.getenv("PWD")
    local modules_path = get_modules_path()
    local local_bin_dir = pwd .. "/" .. modules_path .. "/bin"
    
    -- Dynamic Path Construction
    local local_lua_path = ""
    local local_lua_cpath = ""
    local share_h = io.popen("ls " .. pwd .. "/" .. modules_path .. "/share/lua 2>/dev/null")
    if share_h then
        for v in share_h:lines() do
            if v:match("^%d+%.%d+$") then
                local_lua_path = local_lua_path .. pwd .. "/" .. modules_path .. "/share/lua/" .. v .. "/?.lua;" .. pwd .. "/" .. modules_path .. "/share/lua/" .. v .. "/?/init.lua;"
            end
        end
        share_h:close()
    end
    local lib_h = io.popen("ls " .. pwd .. "/" .. modules_path .. "/lib/lua 2>/dev/null")
    if lib_h then
        for v in lib_h:lines() do
            if v:match("^%d+%.%d+$") then
                local_lua_cpath = local_lua_cpath .. pwd .. "/" .. modules_path .. "/lib/lua/" .. v .. "/?.so;"
            end
        end
        lib_h:close()
    end

    local final_lua_path = local_lua_path .. clean_project_lua_paths(os.getenv("LUA_PATH") or "", pwd, modules_path)
    if final_lua_path ~= "" and not final_lua_path:match(";;$") then
        if final_lua_path:sub(-1) ~= ";" then final_lua_path = final_lua_path .. ";" end
        final_lua_path = final_lua_path .. ";"
    end
    
    local final_lua_cpath = local_lua_cpath .. clean_project_lua_paths(os.getenv("LUA_CPATH") or "", pwd, modules_path)
    if final_lua_cpath ~= "" and not final_lua_cpath:match(";;$") then
        if final_lua_cpath:sub(-1) ~= ";" then final_lua_cpath = final_lua_cpath .. ";" end
        final_lua_cpath = final_lua_cpath .. ";"
    end
    local final_path = local_bin_dir .. ":" .. clean_project_path(os.getenv("PATH") or "", pwd, modules_path)

    -- SMART EXECUTION: Determine if we should prefix with 'lua'
    local bin_name = command:match("^([^%s]+)")
    local rest = command:match("^[^%s]+(.*)") or ""
    local local_bin_path = local_bin_dir .. "/" .. bin_name
    
    local f_bin = io.open(local_bin_path, "r")
    if f_bin then
        local first_line = f_bin:read("*l")
        f_bin:close()
        if first_line and not first_line:match("^#!") then
            command = "lua " .. local_bin_path .. rest
        end
    end

    -- Execute with environment capturing stderr
    print("> " .. command)
    local tmp_err = os.tmpname() or "/tmp/rock.err"
    local full_cmd = string.format("LUA_PATH=%q LUA_CPATH=%q PATH=%q sh -c %q 2>%s", 
                                    final_lua_path, final_lua_cpath, final_path, command, tmp_err)
    
    local res = os.execute(full_cmd)
    local success = (res == 0 or res == true)
    
    if not success then
        local fe = io.open(tmp_err, "r")
        local err_msg = fe and fe:read("*a") or ""
        if fe then fe:close() end
        os.remove(tmp_err)

        if err_msg:match("No such file") or err_msg:match("module '.-' not found") or err_msg:match("requires LuaFileSystem") then
            io.stderr:write(err_msg .. "\n")
            io.stderr:write("\n" .. colors.yellow .. "[Rock Tip] The command '" .. (bin_name or command) .. "' failed due to broken environment paths.\n")
            io.stderr:write(colors.bold_white .. "Try running: rock install --force" .. colors.reset .. " to rebuild your project environment.\n\n")
        else
            io.stderr:write(err_msg)
        end
        os.exit(1)
    end
    os.remove(tmp_err)
end

function project.config(key, val)
    local rc = read_rockrc()
    if not key then
        print("Current configuration:")
        for k, v in pairs(rc.configs) do
            print(string.format("  %s = %q", k, v))
        end
        return
    end

    if not val then
        print(string.format("%s = %q", key, rc.configs[key] or ""))
        return
    end

    rc.configs[key] = val
    write_rockrc(rc)
    print(string.format("✓ Set %s to %q in .rockrc", key, val))
    
    if key == "modules_path" then
        print(colors.yellow .. "Note: You may need to run 'rock install' to move dependencies to the new path." .. colors.reset)
    end
end

return project
