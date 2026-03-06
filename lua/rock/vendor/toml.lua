local TOML = {
	-- denotes the current supported TOML version
	version = 0.40,
	strict = true,
}

-- converts TOML data into a lua table
TOML.parse = function(toml, options)
	options = options or {}
	local strict = (options.strict ~= nil and options.strict or TOML.strict)
	local ws = "[\009\032]"
	local nl = "[\10"
	do
		local crlf = "\13\10"
		nl = nl .. crlf
	end
	nl = nl .. "]"
	local buffer = ""
	local cursor = 1
	local out = {}
	local obj = out

	local function char(n)
		n = n or 0
		return toml:sub(cursor + n, cursor + n)
	end

	local function step(n)
		n = n or 1
		cursor = cursor + n
	end

	local function skipWhitespace()
		while(char():match(ws)) do
			step()
		end
	end

	local function trim(str)
		return str:gsub("^%s*(.-)%s*$", "%1")
	end

	local function err(message, strictOnly)
		if not strictOnly or (strictOnly and strict) then
			local line = 1
			local c = 0
			for l in toml:gmatch("(.-)" .. nl) do
				c = c + l:len()
				if c >= cursor then
					break
				end
				line = line + 1
			end
            local current_char = char() or "EOF"
			error("TOML: " .. message .. " on line " .. line .. " (char: '" .. current_char .. "', pos: " .. cursor .. ")", 4)
		end
	end

	local function bounds()
		return cursor <= toml:len()
	end

	local function parseString()
		local quoteType = char()
		local multiline = (char(1) == char(2) and char(1) == char())
		local str = ""
		step(multiline and 3 or 1)

		while(bounds()) do
			if multiline and char():match(nl) and str == "" then
				step()
			end

			if quoteType == '"' and char() == "\\" then
				if multiline and char(1):match(nl) then
					step(1)
					while(bounds()) do
						if not char():match(ws) and not char():match(nl) then
							break
						end
						step()
					end
				else
					local escape = {
						b = "\b", t = "\t", n = "\n", f = "\f", r = "\r",
						['"'] = '"', ["\\"] = "\\",
					}
					local function utf(char)
						local bytemarkers = {{0x7ff, 192}, {0xffff, 224}, {0x1fffff, 240}}
						if char < 128 then return string.char(char) end
						local charbytes = {}
						for bytes, vals in pairs(bytemarkers) do
							if char <= vals[1] then
								for b = bytes + 1, 2, -1 do
									local mod = char % 64
									char = (char - mod) / 64
									charbytes[b] = string.char(128 + mod)
								end
								charbytes[1] = string.char(vals[2] + char)
								break
							end
						end
						return table.concat(charbytes)
					end

					if escape[char(1)] then
						str = str .. escape[char(1)]
						step(2)
					elseif char(1) == "u" then
						step()
						local uni = char(1) .. char(2) .. char(3) .. char(4)
						step(5)
						uni = tonumber(uni, 16)
						str = str .. utf(uni)
					elseif char(1) == "U" then
						step()
						local uni = char(1) .. char(2) .. char(3) .. char(4) .. char(5) .. char(6) .. char(7) .. char(8)
						step(9)
						uni = tonumber(uni, 16)
						str = str .. utf(uni)
					else
						err("Invalid escape")
					end
				end
			elseif char() == quoteType then
				if multiline then
					if char(1) == char(2) and char(1) == quoteType then
						step(3)
						break
					end
				else
					step()
					break
				end
			else
				if char():match(nl) and not multiline then
					err("Single-line string cannot contain line break")
				end
				str = str .. char()
				step()
			end
		end
		return {value = str, type = "string"}
	end

	local function parseNumber()
		local num = ""
		local exp
		local date = false
		while(bounds()) do
			if char():match("[%+%-%.eE_0-9]") then
				if not exp then
					if char():lower() == "e" then
						exp = ""
					elseif char() ~= "_" then
						num = num .. char()
					end
				elseif char():match("[%+%-0-9]") then
					exp = exp .. char()
				else
					err("Invalid exponent")
				end
			elseif char():match(ws) or char() == "#" or char() == ";" or char():match(nl) or char() == "," or char() == "]" or char() == "}" then
				break
			elseif char() == "T" or char() == "Z" then
				date = true
				while(bounds()) do
					if char() == "," or char() == "]" or char() == "#" or char() == ";" or char():match(nl) or char():match(ws) then
						break
					end
					num = num .. char()
					step()
				end
			else
				err("Invalid number")
			end
			step()
		end
		if date then return {value = num, type = "date"} end
		local float = false
		if num:match("%.") then float = true end
		exp = exp and tonumber(exp) or 0
		num = tonumber(num)
		if not float then return { value = math.floor(num * 10^exp), type = "int" } end
		return {value = num * 10^exp, type = "float"}
	end

	local parseArray, getValue
	
	function parseArray()
		step()
		skipWhitespace()
		local arrayType
		local array = {}
		while(bounds()) do
			if char() == "]" then
				break
			elseif char():match(nl) then
				step()
				skipWhitespace()
			elseif char() == "#" or char() == ";" then
				while(bounds() and not char():match(nl)) do step() end
			else
				local v = getValue()
				if not v then break end
				if arrayType == nil then arrayType = v.type
				elseif arrayType ~= v.type then err("Mixed types in array", true) end
				table.insert(array, v.value)
				if char() == "," then step() end
				skipWhitespace()
			end
		end
		step()
		return {value = array, type = "array"}
	end

	local function parseInlineTable()
		step()
		local buffer = ""
		local quoted = false
		local tbl = {}
		while bounds() do
			if char() == "}" then break
			elseif char() == "'" or char() == '"' then
				buffer = parseString().value
				quoted = true
			elseif char() == "=" then
				if not quoted then buffer = trim(buffer) end
				step()
				skipWhitespace()
				local v = getValue().value
				tbl[buffer] = v
				skipWhitespace()
				if char() == "," then step() end
				quoted = false
				buffer = ""
			else
				buffer = buffer .. char()
				step()
			end
		end
		step()
		return {value = tbl, type = "array"}
	end

	local function parseBoolean()
		local v
		if toml:sub(cursor, cursor + 3) == "true" then
			step(4); v = {value = true, type = "boolean"}
		elseif toml:sub(cursor, cursor + 4) == "false" then
			step(5); v = {value = false, type = "boolean"}
		else err("Invalid primitive") end
		skipWhitespace()
		if char() == "#" or char() == ";" then
			while(not char():match(nl)) do step() end
		end
		return v
	end

	function getValue()
		if char() == '"' or char() == "'" then return parseString()
		elseif char():match("[%+%-0-9]") then return parseNumber()
		elseif char() == "[" then return parseArray()
		elseif char() == "{" then return parseInlineTable()
		else return parseBoolean() end
	end

	local quotedKey = false
	while(cursor <= toml:len()) do
		if char() == "#" or char() == ";" then
			while(not char():match(nl)) do step() end
		end
		if char() == "=" then
			step()
			skipWhitespace()
			buffer = trim(buffer)
			if buffer:match("^[0-9]*$") and not quotedKey then buffer = tonumber(buffer) end
			local v = getValue()
			if v then obj[buffer] = v.value end
			buffer = ""
			quotedKey = false
			skipWhitespace()
			if char() == "#" or char() == ";" then
				while(bounds() and not char():match(nl)) do step() end
			end
		elseif char() == "[" then
			buffer = ""
			step()
			local tableArray = false
			if char() == "[" then tableArray = true; step() end
			obj = out
			local function processKey(isLast)
				buffer = trim(buffer)
				if tableArray then
					if obj[buffer] then
						obj = obj[buffer]
						if isLast then table.insert(obj, {}) end
						obj = obj[#obj]
					else
						obj[buffer] = {}; obj = obj[buffer]
						if isLast then table.insert(obj, {}); obj = obj[1] end
					end
				else
					obj[buffer] = obj[buffer] or {}; obj = obj[buffer]
				end
			end
			while(bounds()) do
				if char() == "]" then
					if tableArray then step() end
					step()
					processKey(true)
					buffer = ""
					break
				elseif char() == '"' or char() == "'" then
					buffer = parseString().value; quotedKey = true
				elseif char() == "." then
					step(); processKey(); buffer = ""
				else buffer = buffer .. char(); step() end
			end
			buffer = ""
			quotedKey = false
		elseif (char() == '"' or char() == "'") then
			buffer = parseString().value; quotedKey = true
		else
			if not char():match(ws) and not char():match(nl) then buffer = buffer .. char() end
			step()
		end
	end
	return out
end

TOML.encode = function(tbl)
	local toml = ""
	local cache = {}

	local function encode_internal(tbl)
        -- First pass: Non-tables (simple keys)
        for k, v in pairs(tbl) do
            if type(v) ~= "table" then
                if type(v) == "boolean" then toml = toml .. k .. " = " .. tostring(v) .. "\n"
                elseif type(v) == "number" then toml = toml .. k .. " = " .. tostring(v) .. "\n"
                elseif type(v) == "string" then
                    local quote = '"'
                    local escaped = v:gsub("\\", "\\\\"):gsub("\b", "\\b"):gsub("\t", "\\t"):gsub("\n", "\\n"):gsub("\f", "\\f"):gsub("\r", "\\r"):gsub('"', '\\"')
                    toml = toml .. k .. " = " .. quote .. escaped .. quote .. "\n"
                end
            end
        end
        -- Second pass: Tables (sections)
		for k, v in pairs(tbl) do
			if type(v) == "table" then
				local is_array = true
                local has_table = false
				for kk, vv in pairs(v) do
					if type(kk) ~= "number" then is_array = false end
					if type(vv) == "table" then has_table = true end
				end
				if is_array then
					if has_table then
						table.insert(cache, k)
						for _, vv in ipairs(v) do
							toml = toml .. "[[" .. table.concat(cache, ".") .. "]]\n"
							encode_internal(vv)
						end
						table.remove(cache)
					else
						toml = toml .. k .. " = [\n"
						for _, vv in ipairs(v) do
                            local val = (type(vv) == "string") and ('"' .. vv:gsub('"', '\\"') .. '"') or tostring(vv)
							toml = toml .. "  " .. val .. ",\n"
						end
						toml = toml .. "]\n"
					end
				else
					table.insert(cache, k)
					toml = toml .. "[" .. table.concat(cache, ".") .. "]\n"
					encode_internal(v)
					table.remove(cache)
				end
			end
		end
	end
	encode_internal(tbl)
	return toml
end

return TOML
