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

local dir = ""
local fname = arg[1]
local t = FTM:loadFTM(dir .. fname)

for tr in pairs(t.track) do
  local r = RV:new(t, tr)
  local rowOrder = {} --Sorted:new()
  local arp = {}
  local instmap = {}
  for i = 1, t.param.chcount do arp[i] = 0 end
  while not rowOrder[tostring(r)] do
    for ch = 1, t.param.chcount do
      local row = r:get(ch)
      for j = 1, 4 do
        local v = row.fx[j]
        if v and v.name == FX.ARPEGGIO then
          arp[ch] = v.param
        end
      end
      local inst = t.inst[row.inst + 1]
      if inst and inst.instType ~= INST.VRC7 and inst.seq[2] and inst.seq[2].mode == 3 then
        local key = (row.inst + 1) .. ":" .. arp[ch]
        local newId = nil
        if not instmap[key] then for i = 1, 0x40 do if not t.inst[i] then
          t.inst[i] = {seq = {}, instType = inst.instType}
          t.inst[i].name = inst.name .. string.format(" 0%02X", arp[ch])
          if inst.instType == INST.APU then    -- move this to luaFTM later
            t.inst[i].dpcm = inst.dpcm
          end
          for j in pairs {1, 3, 4, 5} do
            t.inst[i].seq[j] = inst.seq[j]
          end
          local s = clone(inst.seq[2])
          s.mode = 0
          for k, v in ipairs(s) do
            local trsp, m = v % 0x40, math.floor(v / 0x40)
            if trsp > 0x24 then trsp = trsp - 0x40 end
            if m == 1 then m = arp[ch] >> 4
            elseif m == -2 then m = arp[ch] & 0xF
            elseif m == -1 then m = -(arp[ch] & 0xF)
            end
            s[k] = trsp + m
          end
          for id = 1, 0x80 do if not t.seqAPU[2][i] then
            t.seqAPU[2][i] = s
            s.id = i
            break
          end end
          t.inst[i].seq[2] = s
          instmap[key] = i - 1
          break
        end end end
        row.inst = instmap[key]
        r:set(ch, row)
      end
    end
    rowOrder[tostring(r)] = true
    r:step(true)
  end
end

t:saveFTM("0CC_" .. fname)
