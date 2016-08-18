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

local dir = "C:/Dropbox/!fcp2/"
local fname = "black.ftm"
local t = FTM:loadFTM(dir .. fname)
local CH = t:getTrackChs()
for _, v in ipairs(CH) do if v.chip == CHIP.MMC5 then v.chip = CHIP.APU end end

local convertible; do
  local match = {
    [CHIP.APU] = {[INST.VRC6] = true, [INST.N163] = true, [INST.S5B] = true},
    [CHIP.VRC6] = {[INST.APU] = true, [INST.N163] = true, [INST.S5B] = true},
    [CHIP.S5B] = {[INST.APU] = true, [INST.VRC6] = true, [INST.N163] = true},
  }
convertible = function (chip, insttype)
  return match[chip] and match[chip][insttype]
end; end

local instset = {}
for k in pairs(t.inst) do instset[k] = true end

local rep = {}
for tr in pairs(t.track) do
  local r = RV:new(t, tr)
  local rowOrder = {} --Sorted:new()
  while not rowOrder[tostring(r)] do
    for ch = 1, t.param.chcount do
      local n = r:get(ch)
      local inst = t.inst[n.inst + 1]
      if inst and convertible(CH[ch].chip, inst.instType) then
        if not rep[n.inst + 1] then rep[n.inst + 1] = {} end
        if not rep[n.inst + 1][CH[ch].chip] then
          local index = 1
           while instset[index] do index = index + 1 end
          if index > MAX.INSTRUMENT then error("") end
          rep[n.inst + 1][CH[ch].chip] = index
          instset[index] = true
        end
        n = clone(n)
        n.inst = rep[n.inst + 1][CH[ch].chip] - 1
        r:set(ch, n)
      end
    end
    rowOrder[tostring(r)] = true
    r:step(true)
  end
end

local CHIP2INST = {
  [CHIP.APU]  = INST.APU,
  [CHIP.VRC6] = INST.VRC6,
  [CHIP.VRC7] = INST.VRC7,
  [CHIP.FDS]  = INST.FDS,
  [CHIP.MMC5] = INST.APU,
  [CHIP.N163] = INST.N163,
  [CHIP.S5B]  = INST.S5B,
}

local convertDuty; do
  local APU2VRC6 = {[0] = 1, 3, 7, 3}
  local VRC62APU = {[0] = 0, 0, 1, 1, 1, 1, 2, 2}
convertDuty = function (old, new, x)
  if old == INST.APU then
    if new == INST.VRC6 then return APU2VRC6[x % 4] end
    if new == INST.S5B then return 0x40 end
  end
  if old == INST.VRC6 then
    if new == INST.APU then return VRC62APU[x % 8] end
    if new == INST.S5B then return 0x40 end
  end
  if old == INST.S5B then
    if new == INST.APU then return 2 end
    if new == INST.VRC6 then return 7 end
  end
  return x
end; end

for k, l in pairs(rep) do
  local old = t.inst[k]
  for chip, v in pairs(l) do
    local inst = t:newInst(chip, old.name, v)
    for i = 1, 5 do if old.seq[i] then
      local seq = t:newSeq(chip, i)
      for x, y in ipairs(old.seq[i]) do seq[x] = y end
      if i == 5 then for x, y in ipairs(seq) do seq[x] = convertDuty(old.instType, inst.instType, y) end end
      for _, key in ipairs {"loop", "release", "mode"} do seq[key] = old.seq[i][key] end
      inst.seq[i] = seq
      print(chip, i, seq.id)
    end end
  end
end

t:saveFTM("inst_" .. fname)
