local FTM = require "luaFTM.FTM"
local RV = require "luaFTM.rowView"

local dir = ""
local fname = arg[1]
local t = FTM:loadFTM(dir .. fname)

for tr in pairs(t.track) do
  local r = RV:new(t, tr)
  local rowOrder = {}
  local release = {}
  local count = 0
  local groove = t.track[tr].groove and t.groove[t.track[tr].speed + 1] or {t.track[tr].speed}
  while not rowOrder[tostring(r)] do
    for ch = 1, t.param.chcount do
      local row = r:get(ch)
      local delay = 0
      for _, v in pairs(row.fx) do if v.name == FX.DELAY then delay = v.param end end
      for i = 1, 4 do
        local fx = row.fx[i]
        if fx and fx.name == FX.NOTE_RELEASE then
          release[ch] = fx.param + delay
          row.fx[i] = nil
          r:set(ch, row)
        end
      end
      if release[ch] then
        local ticks = groove[count % #groove + 1]
        if release[ch] >= ticks then
          release[ch] = release[ch] - ticks
        else
          if row.note ~= 0 or row.vol ~= 0x10 or row.inst ~= 0x40 then print(r, ch); goto finally end
          for i = 1, 4 do if row.fx[i] and row.fx[i] ~= 0 then print(r, ch); goto finally end end
          row.note = 0x0D
          if release[ch] > 0 then row.fx[1] = {name = FX.DELAY, param = release[ch]} end
          r:set(ch, row)
          ::finally::
          release[ch] = nil
        end
      end
    end
    rowOrder[tostring(r)] = true
    r:step(true)
    count = count + 1
  end
end

t:saveFTM("Lxx_" .. fname)
