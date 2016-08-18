local FTM = require "luaFTM.FTM"
local RV = require "luaFTM.rowView"

local Sorted = {
  new = function (self)
    local t = {_sort = {}, _back = {}, __index = self}
    setmetatable(t, self)
    return t
  end,
  __metatable = "Sorted Table",
  __len = function (t) return #t._sort end,
  __newindex = function (t, k, v)
    assert(k ~= "_sort" and k ~= "_back")
    rawset(t, k, v)
    rawset(t._back, k, #t._sort + 1)
    rawset(t._sort, #t._sort + 1, k)
  end,
  __pairs = function (self)
    local f = function (t, k)
      if k == nil then return t._sort[1], t[t._sort[1]] end
      local newKey = t._sort[t._back[k] + 1]
      if not newKey then return nil end
      return newKey, t[newKey]
    end
    return f, self, nil
  end,
}

local function clone (t) local z = {}; for k, v in pairs(t) do z[k] = type(v) == "table" and clone(v) or v end; return z end

local proc = function (fname, rowCount, tracks)
  local t = FTM:loadFTM(fname)
  tracks = tracks or {1}

  for tr in pairs(t.track) do
    local r = RV:new(t, tr)
    local rowOrder = Sorted:new()

    while not rowOrder[tostring(r)] do
      local row = {}
      for i = 1, t:getChCount() do
        row[i] = r:get(i)
        for j = 1, 4 do
          local v = row[i].fx[j]
          if v then if v.name == FX.SKIP or v.name == FX.JUMP or v.name == FX.HALT then
            row[i].fx[j] = nil
          end end
        end
      end
      rowOrder[tostring(r)] = row
      r:step(true)
    end
    local loopPoint = rowOrder._back[tostring(r)] - 1
    local maxFrame = math.ceil(#rowOrder / rowCount)

    local shuffle = {}
    for i = 1, maxFrame do
      shuffle[i] = {}
      for j = 1, rowCount do
        table.insert(shuffle[i], math.random(#shuffle[i] + 1), j)
      end
    end
    for i = 1, rowCount do
      if shuffle[1][i] == 1 then
        shuffle[1][1], shuffle[1][i] = shuffle[1][i], shuffle[1][1]
        break
      end
    end
    local lf = loopPoint % maxFrame + 1
    local lr = math.ceil((loopPoint + 1) / maxFrame)
    for i = 1, rowCount do
      if shuffle[lf][i] == 1 then
        shuffle[lf][lr], shuffle[lf][i] = shuffle[lf][i], shuffle[lf][lr]
        break
      end
    end

    local permute = function (x)
      if x > #rowOrder then x = loopPoint + 1 end
      local f, r = (x - 1) % maxFrame + 1, math.ceil(x / maxFrame)
      return f, shuffle[f][r]
    end

    local newFrame = {}
    local newPattern = {}
    for i = 1, t:getChCount() do newPattern[i] = {} end
    for i = 1, maxFrame do
      local f = {}
      for j = 1, t:getChCount() do
        f[j] = i
        newPattern[j][i] = {}
      end
      newFrame[i] = f
    end

    local fxcol = t.track[tr].maxeffect[1] + 1
    local frame, row = permute(1)
    local f2, r2
    local inst = {}
    for i = 1, t:getChCount() do inst[i] = 0x40 end
    for k, v in pairs(rowOrder) do
      f2, r2 = permute(rowOrder._back[k] + 1)
      for i = 1, t:getChCount() do
        newPattern[i][frame][row] = clone(v[i])
        --if newPattern[i][frame][row].inst ~= 0x40 then inst[i] = newPattern[i][frame][row].inst
        --else newPattern[i][frame][row].inst = inst[i] end
      end
      newPattern[1][frame][row].fx[fxcol] = r2 == 1 and {name = FX.JUMP, param = f2 - 1} or {name = FX.SKIP, param = r2 - 1}
      frame, row = f2, r2
    end
    t.track[tr].frame = newFrame
    t.track[tr].pattern = newPattern
    t.track[tr].rows = rowCount
    t.track[tr].maxeffect[1] = fxcol
    t.bookmark = nil
  end
  
  t:clean()
  t:saveFTM("obf_" .. fname)
end

math.randomseed(os.time())
proc(arg[1], tonumber(arg[2]), arg[3])
