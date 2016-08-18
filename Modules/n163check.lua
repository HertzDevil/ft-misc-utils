local FTM = require "luaFTM.FTM"
local RV = require "luaFTM.rowView"

local fname = arg[1]
local f = FTM:loadFTM(fname)
local chan = f:getTrackChs()
local n163ch = {}
for i, v in ipairs(chan) do
  if v.chip == CHIP.N163 then n163ch[#n163ch + 1] = i end
end
 
for k, tr in ipairs(f.track) do
  print("Scanning track " .. k .. "...")
  local rv = RV:new(f, k)
  local visited = {}
  local inst = {}
  local instms = {}
  for _ in ipairs(n163ch) do inst[#inst + 1] = MAX.INSTRUMENT end
  
  repeat
    visited[tostring(rv)] = true
    for i, v in ipairs(n163ch) do
      local id = rv:get(v).inst
      if id ~= MAX.INSTRUMENT then inst[i] = id end
    end
    local set = {}
    for i, v in ipairs(inst) do set[i] = ("%02X"):format(v) end
    table.sort(set)
    instms[table.concat(set, ",")] = true
    rv:step(true)
  until visited[tostring(rv)]
  
  local instms_list = {}
  for k in pairs(instms) do instms_list[#instms_list + 1] = k end
  table.sort(instms_list)
  local o = io.open(fname .. "_n163scan.txt", "w")
  for _, v in ipairs(instms_list) do o:write(v, "\n") end
  o:close()
  print("Track " .. k .. " done.")
end
 
