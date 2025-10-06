--[[----------------------------------------------------------------------------
JSON.lua
Simple JSON encoder/decoder for Lua

Based on public domain JSON library
------------------------------------------------------------------------------]]

local JSON = {}

-- Decode JSON string to Lua table
function JSON.decode(str)
  if type(str) ~= 'string' then
    return nil
  end
  
  local pos = 1
  local strlen = #str
  
  local function skip_whitespace()
    while pos <= strlen do
      local c = str:sub(pos, pos)
      if c ~= ' ' and c ~= '\t' and c ~= '\n' and c ~= '\r' then
        break
      end
      pos = pos + 1
    end
  end
  
  local function decode_value()
    skip_whitespace()
    local c = str:sub(pos, pos)
    
    if c == '"' then
      -- String
      pos = pos + 1
      local start = pos
      while pos <= strlen do
        c = str:sub(pos, pos)
        if c == '"' then
          local result = str:sub(start, pos - 1)
          pos = pos + 1
          return result
        elseif c == '\\' then
          pos = pos + 2
        else
          pos = pos + 1
        end
      end
      return nil
      
    elseif c == '{' then
      -- Object
      pos = pos + 1
      local obj = {}
      skip_whitespace()
      
      if str:sub(pos, pos) == '}' then
        pos = pos + 1
        return obj
      end
      
      while true do
        skip_whitespace()
        local key = decode_value()
        if not key then return nil end
        
        skip_whitespace()
        if str:sub(pos, pos) ~= ':' then return nil end
        pos = pos + 1
        
        local value = decode_value()
        obj[key] = value
        
        skip_whitespace()
        c = str:sub(pos, pos)
        if c == '}' then
          pos = pos + 1
          return obj
        elseif c == ',' then
          pos = pos + 1
        else
          return nil
        end
      end
      
    elseif c == '[' then
      -- Array
      pos = pos + 1
      local arr = {}
      skip_whitespace()
      
      if str:sub(pos, pos) == ']' then
        pos = pos + 1
        return arr
      end
      
      local index = 1
      while true do
        local value = decode_value()
        arr[index] = value
        index = index + 1
        
        skip_whitespace()
        c = str:sub(pos, pos)
        if c == ']' then
          pos = pos + 1
          return arr
        elseif c == ',' then
          pos = pos + 1
        else
          return nil
        end
      end
      
    elseif c == 't' then
      -- true
      if str:sub(pos, pos + 3) == 'true' then
        pos = pos + 4
        return true
      end
      return nil
      
    elseif c == 'f' then
      -- false
      if str:sub(pos, pos + 4) == 'false' then
        pos = pos + 5
        return false
      end
      return nil
      
    elseif c == 'n' then
      -- null
      if str:sub(pos, pos + 3) == 'null' then
        pos = pos + 4
        return nil
      end
      return nil
      
    else
      -- Number
      local start = pos
      while pos <= strlen do
        c = str:sub(pos, pos)
        if c:match('[0-9%.%-%+eE]') then
          pos = pos + 1
        else
          break
        end
      end
      local numstr = str:sub(start, pos - 1)
      return tonumber(numstr)
    end
  end
  
  return decode_value()
end

-- Encode Lua table to JSON string
function JSON.encode(val)
  local function encode_value(v)
    local t = type(v)
    
    if t == 'nil' then
      return 'null'
    elseif t == 'boolean' then
      return v and 'true' or 'false'
    elseif t == 'number' then
      return tostring(v)
    elseif t == 'string' then
      return '"' .. v:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n') .. '"'
    elseif t == 'table' then
      -- Check if array or object
      local is_array = true
      local count = 0
      for k, _ in pairs(v) do
        count = count + 1
        if type(k) ~= 'number' or k ~= count then
          is_array = false
          break
        end
      end
      
      if is_array and count > 0 then
        local parts = {}
        for i = 1, count do
          parts[i] = encode_value(v[i])
        end
        return '[' .. table.concat(parts, ',') .. ']'
      else
        local parts = {}
        for k, val in pairs(v) do
          table.insert(parts, encode_value(tostring(k)) .. ':' .. encode_value(val))
        end
        return '{' .. table.concat(parts, ',') .. '}'
      end
    else
      return 'null'
    end
  end
  
  return encode_value(val)
end

return JSON

