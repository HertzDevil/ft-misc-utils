local assert = function (b, msg)
  if not b then error(msg, 0) end; return b
end

local printf = function (fmt, ...)
  io.stdout:write(fmt:format(...))
end
 
local getnum = function ()
  return tonumber(io.stdin:read("*l"))
end

local factors = function (x) return coroutine.wrap(function ()
  local n = 1
  for i = 1, x do if x % i == 0 then
    coroutine.yield(n, i)
    n = n + 1
  end end
end) end

local range = function (x) return coroutine.wrap(function ()
  for i = 1, x do coroutine.yield(i, i) end
end) end

local param = {
  tempo = 150,
  rate = 60,
  beat = 4,
  usepattern = true,
  cycle = 16,
}

local getparams = function ()
  printf("BPM value: (0 to exit, default is %d)\n", param.tempo)
  local k = getnum()
  assert(k ~= 0, "Exiting.")
  if k then
    assert(k > 0 and k < 1 / 0, "Invalid tempo. Aborting.")
    param.tempo = k
  end
  
  printf("Refresh rate: (default is %d)\n", param.rate)
  k = getnum()
  if k then
    assert(k > 0 and k < 1 / 0, "Invalid refresh rate. Aborting.")
    param.rate = k
  end
  
  printf("First highlight: (default is %d)\n", param.beat)
  k = getnum()
  if k then
    if k == 0 then k = 4 end -- famitracker default
    assert(k > 0 and k < 1 / 0 and k % 1 == 0, "Invalid highlight. Aborting.")
    param.beat = k
  end
  
  local use = true
  printf("Pattern length: (0 to use maximum cycle length%s)\n",
    param.usepattern and ", default is " .. param.cycle or "")
  k = getnum()
  if k == 0 then
    use = false
    printf("Maximum cycle length:%s\n",
      param.usepattern and "" or " (default is " .. param.cycle .. ")")
    k = getnum()
  end
  if k then
    assert(k % 1 == 0 and k > 0 and k <= 256, "Invalid cycle length. Aborting.")
    param.usepattern = use
    param.cycle = k
  end
end

local makefxx = function ()
  local t = {}
  local ticks = 60 * param.rate / (param.tempo * param.beat)
  if ticks < 1 then
    printf("Ticks-per-row count is below 1.\n"); return {1}
  end
  for i, v in (param.usepattern and factors or range)(param.cycle) do
    local approx = math.floor(ticks * v + .5)
    t[i] = {math.floor(ticks * v + .5) / v, v}
  end
  table.sort(t, function (x, y)
    local a, b = math.abs(x[1] - ticks), math.abs(y[1] - ticks)
    return a < b or a == b and x[2] < y[2]
  end)
  local bpm = 60 * param.rate / param.beat / t[1][1]
  local g = {ticks = t[1][1], bpm = bpm, err = (bpm - param.tempo) / param.tempo}
  local approx = math.floor(ticks * t[1][2] + .5)
  for j = 1, t[1][2] do
    g[j] = math.ceil(approx * j / t[1][2]) - math.ceil(approx * (j - 1) / t[1][2])
  end
  return g
end

local disp = function (t)
  printf("Tick count sequence:")
  for i = 1, #t do
    if i % 16 == 1 then printf('\n') end
    printf("%3d ", t[i])
  end
  printf("\n%.5g ticks per row, %d row%s per cycle.\n", t.ticks, #t, #t > 1 and "s" or "")
  printf("New BPM is %.6g (error %+.4g%%).\n\n", t.bpm, t.err * 100)
end

local main = function ()
  getparams(); disp(makefxx())
end

local suc, msg
repeat suc, msg = pcall(main) until not suc;
io.stderr:write(msg)