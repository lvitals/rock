-- rock/project.lua - Handles rock.toml, rock.lock and project metadata
local toml = require("lua.rock.vendor.toml")
local utils = require("lua.rock.utils")
local colors = utils.colors
local spinner = utils.spinner

local project = {}

local function read_toml(filename)
    local f = io.open(filename, "r")
    if not f then return nil end
    local content = f:read("*a")
    f:close()
    return toml.parse(content)
end

local function write_toml(filename, data)
    local f = io.open(filename, "w")
    if not f then return false end
    f:write(toml.encode(data))
    f:close()
    return true
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

    if read_toml("rock.toml") then
        print("Error: rock.toml already exists in this directory.")
        return
    end

    local f = io.open("rock.toml", "w")
    if not f then
        print("Error: Could not create rock.toml")
        return
    end

    -- Manual formatting: Group top fields together, space only before sections
    f:write(string.format('name = %q\n', default_data.name))
    f:write(string.format('version = %q\n', default_data.version))
    f:write(string.format('main = %q\n', default_data.main))
    f:write(string.format('description = %q\n', default_data.description))
    f:write(string.format('lua = %q\n\n', default_data.lua))
    
    f:write("[scripts]\n\n")
    
    f:write("[dependencies]\n\n")
    
    f:write("[devDependencies]\n")
    f:close()

    print("Created rock.toml successfully with Lua " .. (lua_v or "5.4") .. "!")
end

local function get_installed_version(package)
    local handle = io.popen("luarocks show " .. package .. " --mversion --tree=lua_modules 2>/dev/null")
    if not handle then return nil end
    local version = handle:read("*a")
    handle:close()
    if version then return version:gsub("%s+", "") end
    return nil
end

local function write_project_toml(data)
    local f = io.open("rock.toml", "w")
    if not f then return false end

    -- Group top fields
    f:write(string.format('name = %q\n', data.name or ""))
    f:write(string.format('version = %q\n', data.version or "1.0.0"))
    f:write(string.format('main = %q\n', data.main or "main.lua"))
    f:write(string.format('description = %q\n', data.description or ""))
    f:write(string.format('lua = %q\n\n', data.lua or "5.4"))

    -- Sections
    local function write_section(title, section_data)
        f:write("[" .. title .. "]\n")
        if section_data then
            local keys = {}
            for k in pairs(section_data) do table.insert(keys, k) end
            table.sort(keys)
            for _, k in ipairs(keys) do
                f:write(string.format('%s = %q\n', k, section_data[k]))
            end
        end
        f:write("\n")
    end

    write_section("scripts", data.scripts)
    write_section("dependencies", data.dependencies)
    write_section("devDependencies", data.devDependencies)
    
    f:close()
    return true
end

function project.save(package_arg, is_dev)
    local data = read_toml("rock.toml")
    if not data then
        print("Error: No rock.toml found. Run 'rock init' first.")
        return
    end

    local package = package_arg:match("^([^@]+)")
    local requested_version = package_arg:match("@(.+)$") or "latest"

    print("Installing " .. package .. (requested_version ~= "latest" and (" version " .. requested_version) or "") .. " via LuaRocks...")
    
    local luarocks_ver = ""
    local toml_ver = "latest"

    if requested_version ~= "latest" then
        toml_ver = requested_version
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
            env_prefix = string.format("LUA_INCDIR=%q LUA_LIBDIR=%q LUA_BINDIR=%q LUA_DIR=%q CFLAGS=\"-I%s/include $CFLAGS\" LDFLAGS=\"-L%s/lib -Wl,-E $LDFLAGS\" ",
                ld .. "/include", ld .. "/lib", ld .. "/bin", ld, ld, ld)
        end
    end

    local cmd = env_prefix .. "luarocks" .. lua_ver_flag .. lua_dir_flag .. " install --tree=lua_modules " .. package .. (luarocks_ver ~= "" and (" " .. luarocks_ver) or "")
    local success = spinner(cmd, "Installing " .. package .. (requested_version ~= "latest" and (" (" .. requested_version .. ")") or ""))

    if success then
        local section = is_dev and "devDependencies" or "dependencies"
        data[section] = data[section] or {}
        
        -- Get exact version installed for lockfile
        local exact_version = get_installed_version(package)
        
        -- Update rock.toml preserving format
        data[section][package] = toml_ver
        if write_project_toml(data) then
            print("Successfully saved " .. package .. " (" .. toml_ver .. ") to " .. section)
        else
            print("Error: Could not update rock.toml")
        end

        -- Update rock.lock
        local lock_data = read_toml("rock.lock") or { dependencies = {} }
        lock_data.lua = data.lua -- Sync Lua version to lock
        lock_data.dependencies[package] = {
            version = exact_version or toml_ver,
            section = section
        }
        if write_toml("rock.lock", lock_data) then
            print("Updated rock.lock with exact version and Lua info.")
        else
            print("Error: Could not update rock.lock")
        end
    else
        print("Error: Failed to install " .. package)
    end
end

function project.restore(force)
    local lock_data = read_toml("rock.lock")
    local data = read_toml("rock.toml")
    
    if not data then
        print("Error: No rock.toml found.")
        return
    end

    -- 1. Check for Lua version in rock.toml
    if data.lua then
        local active_v = os.getenv("LUA_VERSION")
        if active_v and active_v ~= data.lua and not force then
            io.stderr:write(colors.red .. "Error: Version mismatch.\n" .. colors.reset)
            io.stderr:write("Project requires Lua " .. colors.bold_white .. data.lua .. colors.reset .. " but you are using " .. colors.bold_white .. active_v .. colors.reset .. ".\n")
            io.stderr:write(colors.yellow .. "Please run: rock use " .. data.lua .. " first.\n" .. colors.reset)
            io.stderr:write(colors.dim .. "(Or use --force to install anyway)\n" .. colors.reset)
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
            write_toml("rock.lock", new_lock)
            lock_data = new_lock
        end

        -- Emit activation command for the shell wrapper
        print("eval: rock use " .. data.lua)
    end

    -- 2. Restore packages
    local deps_to_install = {}
    if lock_data and lock_data.dependencies then
        print("Restoring dependencies from rock.lock...")
        for name, info in pairs(lock_data.dependencies) do
            table.insert(deps_to_install, { name = name, version = info.version })
        end
    else
        print("No rock.lock found. Installing from rock.toml...")
        local sections = {"dependencies", "devDependencies"}
        for _, section in ipairs(sections) do
            if data[section] then
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
            env_prefix = string.format("LUA_INCDIR=%q LUA_LIBDIR=%q LUA_BINDIR=%q LUA_DIR=%q CFLAGS=\"-I%s/include $CFLAGS\" LDFLAGS=\"-L%s/lib -Wl,-E $LDFLAGS\" ",
                ld .. "/include", ld .. "/lib", ld .. "/bin", ld, ld, ld)
        end
    end

    if #deps_to_install == 0 then        print("No dependencies to install.")
    else
        print(string.format("Installing %d dependencies...", #deps_to_install))
        for _, dep in ipairs(deps_to_install) do
            local ver_cmd = ""
            if dep.version ~= "latest" then
                ver_cmd = dep.version:gsub("^%^", ""):gsub("^~", "")
            end
            local force_flag = force and "--force " or ""
            local cmd = env_prefix .. "luarocks" .. lua_ver_flag .. lua_dir_flag .. " install --tree=lua_modules " .. force_flag .. dep.name .. " " .. ver_cmd

            spinner(cmd, "  Installing " .. dep.name .. (dep.version ~= "latest" and (" (" .. dep.version .. ")") or ""))        end
        print("Done restoring dependencies.")
    end
end

local function get_env_paths()
    local h = io.popen("luarocks path --tree=lua_modules 2>/dev/null")
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
    local data = read_toml("rock.toml")
    if not data then
        print("Error: No rock.toml found.")
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
        print(colors.red .. "Error: Package '" .. package .. "' not found in rock.toml" .. colors.reset)
        return
    end

    local cmd = "luarocks remove --tree=lua_modules " .. package
    if spinner(cmd, "Removing " .. package) then
        -- Update rock.toml
        if write_project_toml(data) then
            print("Successfully removed " .. package .. " from rock.toml")
        end

        -- Update rock.lock
        local lock_data = read_toml("rock.lock")
        if lock_data and lock_data.dependencies and lock_data.dependencies[package] then
            lock_data.dependencies[package] = nil
            write_toml("rock.lock", lock_data)
            print("Updated rock.lock.")
        end
    else
        print(colors.red .. "Error: Failed to remove package via LuaRocks." .. colors.reset)
    end
end

function project.get_lua_version()
    local data = read_toml("rock.toml")
    return data and data.lua
end

function project.path(base_path, global_lua_path, global_lua_cpath)
    local pwd = os.getenv("PWD")
    local local_bin_dir = pwd .. "/lua_modules/bin"
    
    local local_lua_path = ""
    local local_lua_cpath = ""
    
    local share_h = io.popen("ls " .. pwd .. "/lua_modules/share/lua 2>/dev/null")
    if share_h then
        for v in share_h:lines() do
            if v:match("^%d+%.%d+$") then
                local_lua_path = local_lua_path .. pwd .. "/lua_modules/share/lua/" .. v .. "/?.lua;" .. pwd .. "/lua_modules/share/lua/" .. v .. "/?/init.lua;"
            end
        end
        share_h:close()
    end
    
    local lib_h = io.popen("ls " .. pwd .. "/lua_modules/lib/lua 2>/dev/null")
    if lib_h then
        for v in lib_h:lines() do
            if v:match("^%d+%.%d+$") then
                local_lua_cpath = local_lua_cpath .. pwd .. "/lua_modules/lib/lua/" .. v .. "/?.so;"
            end
        end
        lib_h:close()
    end

    local final_lua_path = local_lua_path .. (global_lua_path or os.getenv("LUA_PATH") or "")
    if not final_lua_path:match(";;$") then final_lua_path = final_lua_path .. ";;" end
    
    local final_lua_cpath = local_lua_cpath .. (global_lua_cpath or os.getenv("LUA_CPATH") or "")
    if not final_lua_cpath:match(";;$") then final_lua_cpath = final_lua_cpath .. ";;" end
    
    local final_path = local_bin_dir .. ":" .. (base_path or os.getenv("PATH") or "")

    print(string.format("eval: export LUA_PATH=%q", final_lua_path))
    print(string.format("eval: export LUA_CPATH=%q", final_lua_cpath))
    print(string.format("eval: export PATH=%q", final_path))
end

function project.run(script_name)
    local data = read_toml("rock.toml")
    if not data or not data.scripts then
        print("Error: No scripts defined in rock.toml")
        return
    end

    -- 1. PRE-CHECK: Ensure required Lua version is installed
    if data.lua then
        local home = os.getenv("HOME")
        local lua_bin = home .. "/.rock/versions/lua-" .. data.lua .. "/bin/lua"
        local f_lua = io.open(lua_bin, "r")
        if not f_lua then
            io.stderr:write(colors.red .. "Error: Lua version " .. data.lua .. " (required by rock.toml) is not installed.\n" .. colors.reset)
            io.stderr:write(colors.yellow .. "Run 'rock install' to fix this.\n" .. colors.reset)
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
        print("Error: Script '" .. script_name .. "' not found in rock.toml")
        return
    end

    -- Setup local environment
    local pwd = os.getenv("PWD")
    local local_bin_dir = pwd .. "/lua_modules/bin"
    
    -- Dynamic Path Construction
    local local_lua_path = ""
    local local_lua_cpath = ""
    local share_h = io.popen("ls " .. pwd .. "/lua_modules/share/lua 2>/dev/null")
    if share_h then
        for v in share_h:lines() do
            if v:match("^%d+%.%d+$") then
                local_lua_path = local_lua_path .. pwd .. "/lua_modules/share/lua/" .. v .. "/?.lua;" .. pwd .. "/lua_modules/share/lua/" .. v .. "/?/init.lua;"
            end
        end
        share_h:close()
    end
    local lib_h = io.popen("ls " .. pwd .. "/lua_modules/lib/lua 2>/dev/null")
    if lib_h then
        for v in lib_h:lines() do
            if v:match("^%d+%.%d+$") then
                local_lua_cpath = local_lua_cpath .. pwd .. "/lua_modules/lib/lua/" .. v .. "/?.so;"
            end
        end
        lib_h:close()
    end

    local final_lua_path = local_lua_path .. (os.getenv("LUA_PATH") or "")
    if not final_lua_path:match(";;$") then final_lua_path = final_lua_path .. ";;" end
    local final_lua_cpath = local_lua_cpath .. (os.getenv("LUA_CPATH") or "")
    if not final_lua_cpath:match(";;$") then final_lua_cpath = final_lua_cpath .. ";;" end
    local final_path = local_bin_dir .. ":" .. (os.getenv("PATH") or "")

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

return project
