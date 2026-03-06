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
    local modules_path = get_modules_path()
    local handle = io.popen("luarocks show " .. package .. " --mversion --tree=" .. modules_path .. " 2>/dev/null")
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

function project.restore(force, verbose)
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
            write_toml("rock.lock", new_lock)
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
        print("Restoring dependencies from rock.lock...")
        for name, info in pairs(lock_data.dependencies) do
            if type(info) == "table" then
                table.insert(deps_to_install, { name = name, version = info.version })
            else
                table.insert(deps_to_install, { name = name, version = info })
            end
        end
    end

    if not lock_has_deps then
        print("No dependencies found in rock.lock (or file missing). Checking rock.toml...")
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

        -- Update rock.lock with exact versions after restoration
        local final_lock_data = { lua = data.lua, dependencies = {} }
        for _, dep in ipairs(deps_to_install) do
            local exact = get_installed_version(dep.name)
            final_lock_data.dependencies[dep.name] = { version = exact or dep.version }
        end
        write_toml("rock.lock", final_lock_data)

        print("Done restoring dependencies and updated rock.lock.")
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

    local modules_path = get_modules_path()
    local cmd = "luarocks remove --tree=" .. modules_path .. " " .. package
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

    -- Clean up any existing rock-managed paths to prevent version bleed (e.g., 5.4.7 mixed with 5.4.8)
    local current_lua_path = os.getenv("LUA_PATH") or ""
    current_lua_path = current_lua_path:gsub("[^;]*/%.rock/versions/[^;]*/share/lua/[^;]*/%?.lua;?", "")
    current_lua_path = current_lua_path:gsub("[^;]*/%.rock/versions/[^;]*/share/lua/[^;]*/%?/init.lua;?", "")
    current_lua_path = current_lua_path:gsub("[^;]*/lua_modules/share/lua/[^;]*/%?.lua;?", "")
    current_lua_path = current_lua_path:gsub("[^;]*/lua_modules/share/lua/[^;]*/%?/init.lua;?", "")

    local current_lua_cpath = os.getenv("LUA_CPATH") or ""
    current_lua_cpath = current_lua_cpath:gsub("[^;]*/%.rock/versions/[^;]*/lib/lua/[^;]*/%?.so;?", "")
    current_lua_cpath = current_lua_cpath:gsub("[^;]*/lua_modules/lib/lua/[^;]*/%?.so;?", "")

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
        print("Error: Script '" .. script_name .. "' not found in rock.toml")
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

    local final_lua_path = local_lua_path .. (os.getenv("LUA_PATH") or "")
    if final_lua_path ~= "" and not final_lua_path:match(";;$") then
        if final_lua_path:sub(-1) ~= ";" then final_lua_path = final_lua_path .. ";" end
        final_lua_path = final_lua_path .. ";"
    end
    
    local final_lua_cpath = local_lua_cpath .. (os.getenv("LUA_CPATH") or "")
    if final_lua_cpath ~= "" and not final_lua_cpath:match(";;$") then
        if final_lua_cpath:sub(-1) ~= ";" then final_lua_cpath = final_lua_cpath .. ";" end
        final_lua_cpath = final_lua_cpath .. ";"
    end
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
