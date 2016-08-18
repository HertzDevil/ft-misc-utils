local loop = false

function bit(x, d)
  return (x >> d) & 1
end

if #arg < 2 then print("Usage: lua dpcm.lua [sample1] [sample2] [output]") os.exit() end
input = {io.open(arg[1], "rb"), io.open(arg[2], "rb")}
if not input[1] then print(arg[1] .. " not found") os.exit() end
if not input[2] then print(arg[2] .. " not found") os.exit() end
output = io.open(arg[3] or "out.dmc", "wb")
if input[1]:seek("end") < input[2]:seek("end") then input[1], input[2] = input[2], input[1] end
input[1]:seek("set", 0)
input[2]:seek("set", 0)

local alt = false
while true do
  local a = input[1]:read(1)
  if not a then break end
  a = string.byte(a)

  local b = input[2]:read(1)
  if b then
    b = string.byte(b)
  elseif loop then
    input[2]:seek("set", 0)
    b = string.byte(input[2]:read(1))
  else
    b = 0xAA
  end
  
  local out = 0
--  if avg then
--    for i = 0, 7 do
--      local delta = (bit(a, i) + bit(b, i) - 1) / 2
--      
--    end
--  else
    for i = 0, 6, 2 do
      local delta = bit(a, i) + bit(a, i + 1) + bit(b, i) + bit(b, i + 1) - 2
      if delta >= 0 then out = out + (1 << i) end
      if delta > 0 then out = out + (1 << i + 1) end
    end
--  end
  output:write(string.char(out))
end

input[1]:close()
input[2]:close()
output:close()