local assert = function (b, msg)
  if not b then error(msg, 0) end; return b
end

local printf = function (fmt, ...)
  io.stdout:write(fmt:format(...))
end

local getnum = function ()
  return tonumber(io.stdin:read("*l"))
end

local param = {
  rate = 16666,
  tempo = 150,
  speed = 6,
  hz = 1e6 / 16666,
}
local getparams = function ()
  printf("Refresh rate: (0 to exit, default is %.3f Hz)\n", 1e6 / param.rate)
  param.hz = getnum()
  if param.hz then
    assert(param.hz ~= 0, "Exiting.")
    param.rate = math.floor(1e6 / param.hz)
  end
  
  printf("Track tempo: (default is %d BPM)\n", param.tempo)
  x = getnum()
  if x then
    assert(x > 0 and x <= 0xFF and x % 1 == 0, "Invalid tempo. Aborting.")
    param.tempo = x
  end
  
  printf("Track speed: (default is %d)\n", param.speed)
  x = getnum()
  if x then
    assert(x > 0 and x <= 0xFF and x % 1 == 0, "Invalid speed. Aborting.")
    param.speed = x
  end
  
  assert(param.rate > 0 and param.rate <= 0xFFFF,
    "Out-of-bound refresh rate. Aborting.")
  if param.hz then
    printf("Refresh rate set to %.3f Hz (error is %+.4e)\n",
      1e6 / param.rate, 1e6 / param.rate - param.hz)
  end
end

local procparams = function ()
  local z = 6e7 / param.rate
  printf("FamiTracker standard tempo: %.6g BPM\n", math.floor(z) / 24)
  printf("True standard tempo: %.6g BPM\n", z / 24)
  printf("FamiTracker track tempo: %.6g BPM\n", math.floor(z) * param.tempo / 600 / param.speed)
  printf("True track tempo: %.6g BPM\n", z * param.tempo / 600 / param.speed)
  printf("Relative error: %+.4g%%\n\n", 100 * (z / math.floor(z) - 1))
  
  z = math.floor(z)
  local dec = math.floor(param.tempo * 24 / param.speed)
  local rem = param.tempo * 24 % param.speed
  printf("NSF tempo base: 0x%04X\n", z)
  printf("NSF tempo count: 0x%04X\n", z - rem)
  printf("NSF tempo remainder: 0x%04X\n", rem)
  printf("NSF tempo decrement: 0x%04X\n", dec)
  printf("Tick count sequence:")
  local cycle = dec / (function (x, y)
    while y ~= 0 do x, y = y, x % y end; return x
  end)(z - rem, dec)
  local ticks = (z - rem) / dec
  for i = 1, cycle do
    if i % 16 == 1 then printf('\n') end
    printf("%3d ", math.ceil(ticks * i) - math.ceil(ticks * (i - 1)))
  end
  printf("\n%.5g ticks per row, %d row%s per cycle.\n\n", ticks, cycle, cycle > 1 and "s" or "")
end

while true do
  local suc, msg = pcall(getparams)
  if not suc then printf(msg); break end
  procparams()
end