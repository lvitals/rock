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
    
    local output = {}
    local handle = io.popen(cmd .. " 2>&1; echo $?")
    if not handle then return false end

    for line in handle:lines() do
        io.stderr:write("\r" .. colors.bold_cyan .. frames[i] .. colors.reset .. " " .. message)
        i = (i % #frames) + 1
        table.insert(output, line)
    end
    handle:close()
    
    local last_line = table.remove(output)
    local success = (last_line == "0")
    
    io.stderr:write("\r" .. (success and (colors.bold_green .. "✓") or (colors.red .. "✗")) .. " " .. message .. string.rep(" ", 20) .. "\n")
    
    if not success then
        for _, line in ipairs(output) do
            print(line)
        end
    end
    
    return success
end

utils.colors = colors

return utils
