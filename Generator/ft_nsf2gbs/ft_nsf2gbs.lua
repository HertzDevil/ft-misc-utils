assert = function (pr, msg) if not pr then error(msg, 0) end end -- suppress code position
local disp, alert; do
  local dump = function (f, header, cont) return function (...)
    local s = header; for i, v in ipairs {...} do f:write(s, v, '\n'); s = cont end
  end end
disp = dump(io.stdout, "Message: ", "         ")
alert = dump(io.stderr, "  Error: ", "         ")
end

local make; do
  local byte, word, sbyte
  local fixgetters = function (file)
    byte = function () return (("<I1"):unpack(file:read(1))) end
    word = function () return (("<I2"):unpack(file:read(2))) end
    sbyte = function () return (("<i1"):unpack(file:read(1))) end
  end

  local DRV_BAD = 0
  local DRV_046 = 1
  local DRV_0CC = 2
  local DRV_050 = 3
  local VERSION_INFO = {
    [DRV_046] = {
      size = 0x19B0,
      ident = "FTDRV \x02\x0A",
      gb = {fname = "GB_046.bin", adr = {tma = 0x616, tac = 0x61A, divider = 0x88A}},
      gbs = {fname = "GBS_046.bin", adr = {tma = 0x0E, tac = 0x0F, divider = 0x2CC}}
    },
    [DRV_0CC] = {
      size = 0x1B81,
      ident = "0CCFT \x02\x0C",
      gb = {fname = "GB_0CC.bin", adr = {tma = 0x6F7, tac = 0x6FB, divider = 0x973}},
      gbs = {fname = "GBS_0CC.bin", adr = {tma = 0x0E, tac = 0x0F, divider = 0x2D4}}
    },
    --[DRV_050] = {size = 0,},
  }
  local ROM_SIZE = {
    {val = 0x00, size =   0x8000},
    {val = 0x01, size =  0x10000},
    {val = 0x02, size =  0x20000},
    {val = 0x03, size =  0x40000},
    {val = 0x04, size =  0x80000},
    {val = 0x05, size = 0x100000},
-- NSF does not support file sizes > 1 MB
--    {val = 0x52, size = 0x120000},
--    {val = 0x53, size = 0x140000},
--    {val = 0x54, size = 0x180000},
--    {val = 0x06, size = 0x200000},
--    {val = 0x07, size = 0x400000},
  }
  local TIMER_RATE = {
    {val = 0x04, rate =  0x1000},
    {val = 0x05, rate = 0x40000},
    {val = 0x06, rate = 0x10000},
    {val = 0x07, rate =  0x4000},
  }

  local getinfo = function (file)
    local INFO = {}
    file:seek("set", 0x00)
    assert(file:read(5) == "NESM\x1A", "Not a NSF file")
    INFO.VERSION = byte()
    assert(INFO.VERSION == 0x01, "Invalid NSF version")
    INFO.COUNT = byte()
    INFO.TRACK = byte()
    INFO.LOAD = word()
    INFO.INIT = word()
    INFO.PLAY = word()
    INFO.TITLE = file:read(0x20)
    INFO.AUTHOR = file:read(0x20)
    INFO.COPYRIGHT = file:read(0x20)
    INFO.RATE_NTSC = word()
    INFO.BANK = {}
    for i = 1, 8 do INFO.BANK[i - 1] = byte() end
    INFO.RATE_PAL = word()
    INFO.REGION = byte()
    INFO.CHIP = byte()
    return INFO
  end

  local detect = function (file)
    local info = getinfo(file)
    assert(info.CHIP == 0x10, "NSF does not use N163 only")
    local driverbegin = info.INIT - info.LOAD + 0x80
    file:seek("set", driverbegin)
    local driversize, databegin, datasize
    local version = DRV_BAD
    if info.LOAD ~= 0x8000 then
      for i, v in ipairs(VERSION_INFO) do
        file:seek("cur", -#v.ident)
        if file:read(#v.ident) == v.ident then
          version = i; break
        end
      end
      driversize = 0xC000 - info.INIT
      databegin = 0x80
      file:seek("cur", driversize - 2)
      assert(word() + 0x80 - info.LOAD == databegin, "Music data pointer mismatch")
      datasize = driverbegin - databegin - #VERSION_INFO[version].ident
    else
      for i, v in ipairs(VERSION_INFO) do
        file:seek("set", driverbegin - #v.ident)
        if file:read(#v.ident) == v.ident then
          file:seek("cur", v.size - 6)
          local vibtable = file:read(4)
          assert(vibtable == "\x76\x7A\x7D\x7F" or vibtable == "\xC0\xD0\xE0\xF0",
            "Failed to detect NSF by vibrato table")
          databegin = word() + 0x80 - info.LOAD
          assert(file:seek() == databegin, "Music data pointer mismatch")
          driversize = file:seek() - driverbegin
          datasize = file:seek("end") - databegin
          if info.BANK[4] ~= 0 then -- remove DPCM data
            datasize = math.min(datasize, info.BANK[4] * 0x1000 + 0x80 - databegin)
          end
          version = i; break
        end
      end
    end
    assert(version ~= DRV_BAD, "Unknown NSF driver version")

    file:seek("set", databegin + (version == DRV_0CC and 0xF or 0xD))
    assert(byte() == 1, "NSF uses more than one N163 channel")
    file:seek("set", databegin)
    local chunk = file:read(datasize)
    
    local periodtable = {}
    file:seek("set", driverbegin + driversize - 0x282)
    if version ~= DRV_0CC then file:seek("cur", -0xC0) end -- skip PAL
    for i = 1, 96 do
      local reg = 2048 - 131072 / (236250000 / 132 / 16 / (word() + 1))
      periodtable[i] = ("<I2"):pack(math.max(0, math.min(0x7FF, math.floor(reg + .5))))
    end
    file:seek("cur", 0xC0)
    table.insert(periodtable, file:read(0x100))

    return version, chunk, table.concat(periodtable)
  end

  local _make_ = function (file, fname)
    assert(file, "Cannot open file")
    fixgetters(file)
    local drv, bin, periods = detect(file)
    local info = getinfo(file) -- can be returned from above
    
    local rate = {tma = 256 - 91, tac = 7, divider = 3} -- default values at 60.015 Hz
    do
      local hz = 1000000 / info[info.REGION % 2 == 1 and "RATE_PAL" or "RATE_NTSC"]
      local values = {}
      for i = 1, 16 do for _, v in ipairs(TIMER_RATE) do
        local x = math.floor(256.5 - v.rate / hz / i)
        if x >= 0 and x <= 255 then
          table.insert(values, {
            real = math.floor(v.rate / (256 - x) / i * 1e6) / 1e6,
            rate = {tma = x, tac = v.val, divider = i}
          })
        end
      end end
      table.sort(values, function (a, b)
        local x, y
        x, y = math.abs(a.real - hz), math.abs(b.real - hz)
        if x ~= y then return x < y end
        x, y = a.rate.divider, b.rate.divider
        if x ~= y then return x < y end
        x, y = a.rate.tma, b.rate.tma
        if x ~= y then return x < y end
      end)
      if #values > 0 then
        rate = values[1].rate
        disp(("Refresh rate from NSF is %.3f Hz"):format(hz),
          ("New refresh rate from GBS is %.3f Hz"):format(values[1].real))
      end
    end
    
    disp("Creating GBS sound file...")
    local out = io.open(fname .. ".gbs", "wb")
    local gb = io.open("inc/" .. VERSION_INFO[drv].gbs.fname, "rb")
    out:write(gb:read("*a"))
    gb:close()
    out:seek("end", -0x1C2)
    out:write(periods)
    out:seek("end")
    out:write(bin)
    out:seek("set", 0x04)
    out:write(string.char(info.COUNT))
    out:write(string.char(info.TRACK))
    out:seek("set", 0x10)
    out:write(info.TITLE, info.AUTHOR, info.COPYRIGHT)
    for k, v in pairs(VERSION_INFO[drv].gbs.adr) do
      out:seek("set", v)
      out:write(string.char(rate[k]))
    end
    out:close()

    disp("Creating GB ROM image...")
    out = io.open(fname .. ".gb", "wb")
    gb = io.open("inc/" .. VERSION_INFO[drv].gb.fname, "rb")
    out:write(gb:read("*a"))
    gb:close()
    out:seek("end", -0x1C2)
    out:write(periods)
    out:seek("end")
    out:write(bin)
    local fsize = out:seek()
    for _, v in ipairs(ROM_SIZE) do
      if fsize <= v.size then
        out:write(("\x00"):rep(v.size - fsize))
        out:seek("set", 0x148)
        out:write(string.char(v.val))
        fsize = v.size; break
      end
    end
    for k, v in pairs(VERSION_INFO[drv].gb.adr) do
      out:seek("set", v)
      out:write(string.char(rate[k]))
    end

    out:seek("set", 0x14D) -- checksums
    out:write("\x00\x00\x00")
    out:close()
    
    out = io.open(fname .. ".gb", "rb")
    out:seek("set", 0x134)
    local checksum = 0
    for i = 0x134, 0x14C do
      checksum = (checksum - out:read(1):byte() - 1) % 0x100
    end
    out:seek("set", 0)
    local check2 = checksum
    for c in out:lines(1) do
      check2 = (check2 + c:byte()) % 0x10000
    end
    out:seek("set", 0)
    local final = out:read(0x14D)
    final = final .. string.char(checksum, math.floor(check2 / 0x100), check2 % 0x100)
    out:seek("set", 0x150)
    final = final .. out:read("*a")
    out:close()
    
    out = io.open(fname .. ".gb", "wb")
    out:write(final)
    out:close()
  end

make = function (fname)
  local t = os.clock()
  disp("Opening " .. fname .. "...")
  local f = io.open(fname, "rb")
  local ret = {pcall(_make_, f, fname)}
  if f then f:close() end
  local suc = table.remove(ret, 1)
  if not suc then
    alert(ret[1])
  else
    disp("Operation completed in " .. os.clock() - t .. " seconds.")
  end
  return suc -- table.unpack(ret)
end end

if arg[0]:find " " then arg[0] = '"' .. arg[0] .. '"' end
local desc = [[
FamiTracker NSF to GBS converter
Usage: lua ]] .. arg[0] .. [[ [filename]

The following builds are supported:
 - FamiTracker 0.4.5 stable
 - FamiTracker 0.4.6 stable
 - 0CC-FamiTracker 0.3.13 (last revision build)
See http://gist.github.com/HertzDevil/d204524485d3a37a1829 for details.

(C) HertzDevil 2016
MIT License.
]]

if arg[1] then
  os.exit(make(arg[1]))
else
  io.stdout:write(desc)
  os.exit(true)
end
