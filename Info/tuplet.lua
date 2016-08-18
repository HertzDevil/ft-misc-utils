local REFRESH = 60
local SPEED = {6}
local TEMPO = 150

local tick = function (row) return REFRESH * SPEED[(row - 1) % #SPEED + 1] * 2.5 / TEMPO end

local tuplet = function (R, T)
  local count = {0}
  local final = {}
  for i = 1, R do count[i + 1] = count[i] + tick(i) end
  for i = 1, T do
    local p = 1
    local Offset = count[R + 1] * (i - 1) / T
    while count[p + 1] and Offset - count[p + 1] + .5 >= 0 do p = p + 1 end
    local z = {Row = p, Gxx = Offset - count[p]}
    z.Length = math.floor(Offset + count[R + 1] / T + .5) - math.floor(Offset + .5)
    z.Error = math.floor(z.Gxx + .5) - z.Gxx
    final[i] = z
  end
  for i = 1, T - 1 do if final[i].Row == final[i + 1].Row then
    if final[i].Gxx < .5 then
      final[i].Row = final[i].Row - 1
      final[i].Gxx = final[i].Gxx + tick(final[i].Row)
      if i > 1 and final[i - 1].Row == final[i].Row then return false end
    else return false end
  end end
  for i = 1, T do if final[i].Gxx > 0xFF then return false end end
  return final
end

local test = function (R, T)
  print("Refresh rate: " .. REFRESH .. " Hz")
  print("Tempo: " .. TEMPO .. " BPM")
  print((#SPEED > 1 and "Groove: " or "Speed: ") .. table.concat(SPEED, " "))
  local x = tuplet(R, T)
  if not x then
    print("No possible Gxx sequences for " .. T .. "-tuplet in " .. R .. " rows")
  else
    local offset = 1 - math.min(x[1].Row, 1)
    local pat = {}
    for _, v in ipairs(x) do
      assert(pat[v.Row + offset] == nil)
      pat[v.Row + offset] = v
    end
    local str = {}
    for i = 1, R + offset do
      local note = pat[i] and "C-3 00 ." or "... .. ."
      local f = SPEED[(i - offset - 1) % #SPEED + 1]
      local speed = (i == 1 or f ~= SPEED[(i - offset - 2) % #SPEED + 1]) and string.format("F%02X", f) or "..."
      local g = math.floor((pat[i] and pat[i].Gxx or 0) + .5)
      local delay = g > 0 and string.format("G%02X", g) or "..."
      local com = pat[i] and string.format("    # length = %d; error = %+.2f", pat[i].Length, pat[i].Error) or ""
      str[#str + 1] = string.format("ROW %02X : ... .. . %s : %s %s%s", i - 1, speed, note, delay, com)
    end
    print("Closest Gxx sequence for " .. T .. "-tuplet in " .. R .. " rows:")
    if offset ~= 0 then print("Warning: First note occurs one row before") end
    print(table.concat(str, "\n"))
  end
end

local desc = [[
Tracker tuplet calculator
Usage: lua tuplet.lua [rows] [notes] {option}
Options:
  -Tx: Set tempo to x (default 150)
  -Sx{,y}: Set speed to x, use multiple values for groove (default 6)
  -Rx: Set refresh rate to x (default 60)]]

local split = function (str, delim)
  str = str .. delim
  local b, e = 0, 0
  local pos = 1
  local out = {}
  repeat
    b, e = string.find(str, delim, pos, true)
    out[#out + 1] = str:sub(pos, b - 1)
    pos = e + 1
  until e == #str
  return out
end

local main = function (arg)
  local kill = function (str) print(str); os.exit(1) end

  for i = 3, #arg do
    local type, param = string.sub(arg[i], 1, 2), string.sub(arg[i], 3)
    if param then
      if type == "-T" then TEMPO = tonumber(param)
      elseif type == "-S" then
        SPEED = split(param, ",")
        for k in ipairs(SPEED) do SPEED[k] = tonumber(SPEED[k]) end
      elseif type == "-R" then REFRESH = tonumber(param)
      end
    end
  end

  if #arg < 2 then kill(desc) end
  local R, T = tonumber(arg[1]), tonumber(arg[2])
  local natural = function (x) return x and x % 1 == 0 and x > 0 end
  for _, v in pairs {R, T, TEMPO, REFRESH} do
    if not natural(v) then kill("Invalid argument") end
  end
  for _, v in pairs(SPEED) do
    if not natural(v) then kill("Invalid argument") end
  end
  if #SPEED == 0 then kill("Invalid argument") end

  test(R, T)
  os.exit(0)
end

main(arg)