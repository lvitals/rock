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
    io.stderr:write(message .. "  ")
    
    local handle = io.popen(cmd .. " 2>&1; echo $?")
    if not handle then return false end

    local last_line = ""
    for line in handle:lines() do
        io.stderr:write("\r" .. colors.bold_cyan .. frames[i] .. colors.reset .. " " .. message)
        i = (i % #frames) + 1
        last_line = line
    end
    handle:close()
    
    local success = (last_line == "0")
    io.stderr:write("\r" .. (success and (colors.bold_green .. "✓") or (colors.red .. "✗")) .. " " .. message .. string.rep(" ", 20) .. "\n")
    return success
end

utils.colors = colors

return utils
