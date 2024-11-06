local utils = {}

function utils.split(inputstr, sep)
  if sep == nil then
    sep = "%s"
  end
  local t = {}
  for str in string.gmatch(inputstr, "([^" .. sep .. "]+)") do
    table.insert(t, str)
  end
  return t
end

function utils.strip_ansi_colors(str)
  return str:gsub("\27%[%d*;*%d*m", "")
end

function utils.strip_quotes(str)
  return str:gsub('"', '')
end

function utils.append_quotes(str)
  return '"' .. str .. '"'
end

function utils.get_extension(str)
  return str:match('.+%.(%w+)$')
end

function utils.get_filename(str)
  if not str then return "" end
  return str:gsub("%.%w+$", "")
end

function utils.match_extension(str, ext)
  return str:match('.+' .. ext .. '$')
end

-- https://github.com/s-walrus/hex2color/blob/master/hex2color.lua
function utils.hex(hex, value)
  return {
    tonumber(string.sub(hex, 2, 3), 16) / 256,
    tonumber(string.sub(hex, 4, 5), 16) / 256,
    tonumber(string.sub(hex, 6, 7), 16) / 256,
    value or 1 }
end

-- http://lua-users.org/wiki/SortedIteration
--[[
Ordered table iterator, allow to iterate on the natural order of the keys of a
table.
]]

local function __genOrderedIndex(t)
  local orderedIndex = {}
  for key in pairs(t) do
    table.insert(orderedIndex, key)
  end
  table.sort(orderedIndex)
  return orderedIndex
end

local function orderedNext(t, state)
  -- Equivalent of the next function, but returns the keys in the alphabetic
  -- order. We use a temporary ordered key table that is stored in the
  -- table being iterated.

  local key = nil
  if state == nil then
    -- the first time, generate the index
    t.__orderedIndex = __genOrderedIndex(t)
    key = t.__orderedIndex[1]
  else
    -- fetch the next value
    for i = 1, #t.__orderedIndex do
      if t.__orderedIndex[i] == state then
        key = t.__orderedIndex[i + 1]
      end
    end
  end

  if key then
    return key, t[key]
  end

  -- no more value to return, cleanup
  t.__orderedIndex = nil
  return
end

function utils.orderedPairs(t)
  -- Equivalent of the pairs() function on tables. Allows to iterate
  -- in order
  return orderedNext, t, nil
end

return utils
