-- for these values the calculated standard tempo in the playback rate
-- dialog is exactly 2.5 times the desired integer refresh rate

local toInterval = function (rate) return math.floor(1e6 / rate) end

local MIN_RATE = math.ceil(1e6 / 0xFFFF)
local MAX_RATE = 1000 -- math.floor(0xFFFF / 60)

local t = {}
for i = MIN_RATE, MAX_RATE do
  t[i] = math.floor(6e7 / toInterval(i)) == i * 60
end

for i = MIN_RATE, MAX_RATE do
  if t[i] then print(("%4d Hz (near %4d µs)"):format(i, toInterval(i))) end
end

local count = 0
for i = MIN_RATE, MAX_RATE do if not t[i] then
  if count % 10 == 0 then io.stdout:write '\n' end
  count = count + 1
  io.stdout:write(("%4d "):format(i))
end end
