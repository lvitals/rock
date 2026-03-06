-- lua/rock/utils.lua - Shared utilities
local utils = {}

local colors = {
    reset = "\27[0m", bold = "\27[1m", dim = "\27[2m", green = "\27[32m",
    yellow = "\27[33m", blue = "\27[34m", cyan = "\27[36m", red = "\27[31m",
    bold_green = "\27[1;32m", bold_cyan = "\27[1;36m", bold_white = "\27[1;37m"
}

function utils.spinner(cmd, message)
    local frames = {"⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"}
    local i = 1
    
    local tmp_out = os.tmpname()
    local exit_file = tmp_out .. ".exit"
    
    -- Execute command in background and save its exit code
    local full_cmd = "{ (" .. cmd .. "); echo $? > " .. exit_file .. "; } > " .. tmp_out .. " 2>&1 &"
    os.execute(full_cmd)
    
    local success = nil
    while success == nil do
        -- Use io.stderr to bypass the shell wrapper's stdout capture
        io.stderr:write("\r" .. colors.bold_cyan .. frames[i] .. colors.reset .. " " .. message .. "   ")
        io.stderr:flush()
        i = (i % #frames) + 1
        
        -- Check if command finished
        local f_exit = io.open(exit_file, "r")
        if f_exit then
            local code = f_exit:read("*a"):match("(%d+)")
            f_exit:close()
            if code then
                success = (code == "0")
            end
        end
        
        if success == nil then
            os.execute("sleep 0.1")
        end
    end
    
    -- Clear line and show final status on stderr
    io.stderr:write("\r" .. (success and (colors.bold_green .. "✓") or (colors.red .. "✗")) .. " " .. message .. string.rep(" ", 10) .. "\n")
    io.stderr:flush()
    
    if not success then
        local f_out = io.open(tmp_out, "r")
        if f_out then
            local out = f_out:read("*a")
            f_out:close()
            if out ~= "" then io.stderr:write(out .. "\n") end
        end
    end
    
    os.remove(tmp_out)
    os.remove(exit_file)
    
    return success
end

utils.colors = colors

return utils
