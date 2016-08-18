local assert = function (b, msg)
  if not b then error(msg, 0) end; return b
end

local printf = function (fmt, ...)
  io.stdout:write(fmt:format(...))
end

local getnum = function ()
  return tonumber(io.stdin:read("*l"))
end

local binrev = function (x, n)
  local z = 0
  for _ = 1, n do
    x, z = math.floor(x / 2), z * 2 + x % 2
  end
  return z
end

local main = function ()
  printf("Ticks per row:\n")
  local ot = getnum()
  assert(ot, "Exiting.")
  assert(ot > 0 and ot < 1 / 0, "Invalid ticks count. Aborting.")
  
  printf("Row count (must be a power of 2, default is 8):\n")
  local count = getnum() or 8
  local n = math.log(count, 2)
  n = math.floor(n * 1e14 + .5) / 1e14
  assert(n >= 0 and n % 1 == 0, "Invalid row count. Aborting.")
  
  local ticks = math.floor(count * ot + .5)
  if ticks % 2 == 0 and count % 2 == 0 then
    local old = count
    while ticks % 2 == 0 and count % 2 == 0 do
      ticks, count, n = ticks / 2, count / 2, n - 1
    end
    printf("Number of rows reduced from %d to %d.\n", old, count)
  end
  local m = ticks % count
  ticks = ticks / count -- exact float value
  local lv, hv = math.floor(ticks), math.ceil(ticks)

  local t = {}
  printf("Tick count sequence: (forward)")
  for i = 0, count - 1 do
  	if i % 16 == 0 then printf("\n") end
  	local x = binrev(i, n) < m and hv or lv
  	t[count - i] = x
    printf("%3d ", x)
  end
  printf("\nTick count sequence: (backward)")
  for i, v in ipairs(t) do
  	if i % 16 == 1 then printf("\n") end
    printf("%3d ", v)
  end
  printf("\n%.5g ticks per row (error %+.4g%%).\n\n", ticks, 100 * ((ticks - ot) / ot))
end

local suc, msg
repeat suc, msg = pcall(main) until not suc;
io.stderr:write(msg)