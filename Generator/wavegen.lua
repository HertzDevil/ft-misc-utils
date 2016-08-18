-- incomplete

local generatewaves = function (arg)
  arg.refresh = arg.refresh or 60
  assert(arg.loopstart and arg.wavebit and arg.wavelen and arg.wavecount and arg.file)

  -- load source waveform
  local f = io.open(arg.file, "rb")
  -- f:seek("set", 0x16); local chCount = string.unpack("<I2", f:read(2))
  f:seek("set", 0x18)
  local hz = string.unpack("<I4", f:read(4))
  print("Sample rate: " .. hz .. " Hz")
  f:seek("set", 0x22)
  local bits = string.unpack("<I2", f:read(2))
  print("Bit depth: " .. bits)
  f:seek("set", 0x10)
  local csize = string.unpack("<I4", f:read(4))
  f:seek("set", 0x18 + csize)
  local len = string.unpack("<I4", f:read(4))
  
  local start = 0
  if arg.loopstart then
    local size = len / bits * 8
    local x = (size - arg.loopstart) / arg.loopfix
    arg.loopfix = math.floor(size / x)
    start = math.floor((size - arg.loopfix * x) * bits / 8 + .5)
  end
  len = (arg.stop and math.min(len, arg.stop * bits / 8) or len) - start
  local seqlen = len / hz * 8 / bits
  print(string.format("Loop duration: %.3f s", seqlen))
  seqlen = math.floor(seqlen * arg.refresh / 2 ^ (arg.trsp / 12) + .5)
  if not arg.loopstart then arg.loopstart = len / bits * 8; arg.loopfix = seqlen end

  -- obtain samples
  local lanczos = function (a) return function (x)
    local px = math.pi * x
    return x == 0 and 1 or math.abs(x) < a and (a * math.sin(px) * math.sin(px / a) / px ^ 2) or 0
  end end
  local FILTER_SIZE = 2
  local filter = lanczos(FILTER_SIZE)
  local getsamp = function (i)
    local s = 0
    for j = math.floor(i) - FILTER_SIZE + 1, math.floor(i) + FILTER_SIZE do
      f:seek("set", 0x1C + csize + j)
      f:seek("cur", -(f:seek() % (bits / 8)))
      local b = f:read(1)
      if not b then
        f:seek("set", 0x1C + csize + j - (len - start))
        b = f:read(1)
      end
      if bits == 8 then
        b = b and string.byte(b) - 0x80 or 0
      elseif bits % 8 == 0 then
        local extra = {}
        for i = 16, bits, 8 do
          local ch = f:read(1)
          if not ch then b = 0; goto outer end
          extra[#extra + 1] = ch
        end
        b = b and string.unpack("<i" .. math.floor(bits / 8), b .. table.concat(extra)) or 0
        ::outer::
      end
      s = s + b * filter(i - j)
    end
    return s
  end
  local out = {}
  local sup, inf = {}, {}
  for t = 1, arg.loopfix do
    out[t] = {}
    for i = 1, arg.wavelen do
      local s = start + (t + (i - 0.5) / arg.wavelen - 1) * len / arg.loopfix
      out[t][i] = getsamp(s)
    end
    sup[t] = math.max(table.unpack(out[t]))
    inf[t] = math.min(table.unpack(out[t]))
  end
  f:close()

  -- normalize waveforms
  sup = math.max(table.unpack(sup))
  inf = math.min(table.unpack(inf))
  for _, t in ipairs(out) do for k in ipairs(t) do
    t[k] = math.floor((t[k] - inf) / (sup - inf) * 2 ^ arg.wavebit)
    if t[k] == 2 ^ arg.wavebit then t[k] = t[k] - 1 end
  end end

  arg.loopstart = arg.loopstart * bits / 8
  local looppoint = math.floor((arg.loopstart - start) / (len - start) * seqlen + .5)
  if looppoint < 0 or looppoint >= seqlen then looppoint = -1 end
  
  local fname = string.gsub(arg.file, ".wav$", "")
  f = io.open(fname .. ".fti", "wb")
  f:write("FTI", "2.4", "\x05", string.pack("s4", fname))
  f:write(string.char(5, 0, 0, 0, 0, 1))
  f:write(string.pack("<I4i4i4I4", seqlen, looppoint, -1, 0))
  for i = 1, seqlen do f:write(string.char(math.floor((i - 1) / seqlen * arg.wavecount))) end
  f:write(string.pack("<I4I4I4", #out[1], 0, arg.wavecount))
  for i = 1, arg.wavecount do for _, v in ipairs(out[math.floor((i - 1) * #out / arg.wavecount) + 1]) do
    f:write(string.char(math.min(15, math.max(0, v))))
  end end
  f:close()
end

if arg[4] then
  arg[2] = tonumber(arg[2])
  arg[3] = tonumber(arg[3])
  arg[4] = tonumber(arg[4])
  local wavelen = 32
  local refresh = 60
  local trsp = 0
  for i = 5, #arg do
    local str = arg[i]
    local x = tonumber(str:match("^-L(%d+)$"))
    if x then wavelen = x end
    local x = tonumber(str:match("^-R(%d+)$"))
    if x then refresh = x end
    local x = tonumber(str:match("^-T(-?%d+)$"))
    if x then trsp = x end
  end
  
  assert(arg[2] % 1 == 0 and arg[2] >= 1 and arg[2] <= 64)
  assert(arg[3] % 1 == 0 and arg[3] >= 0)
  assert(arg[4] % 1 == 0 and arg[4] >= 1)
  assert(wavelen % 4 == 0 and wavelen >= 4 and wavelen <= 240)
  assert(refresh > 0)
  
  generatewaves({
    file = arg[1],      -- filename
    wavebit = 4,	      -- wave resolution
    wavelen = wavelen,  -- wavelength
    wavecount = arg[2], -- number of waves
    loopstart = arg[3], -- beginning of loop, in samples
    loopfix = arg[4],   -- number of loops
    refresh = refresh,  -- target refresh rate
    trsp = trsp,        -- transposition for wave sequence
  })
  print(os.clock() .. " seconds elapsed.")
else
  print([[
N163 FTI sampler
Usage: lua wavegen.lua [filename] [wavecount] [loopstart] [loopcount] {option}
 [filename] : Name of the file
 [wavecount]: Number of waves in exported FTI
 [loopstart]: Loop point, in number of samples
 [loopcount]: Number of oscillations per sample loop
Options:
 -Lx: Set FTI wave size to x samples (default 32)
 -Rx: Set target refresh rate to x Hz (default 60)
DOES NOT support stereo samples and IEEE float/double samples.]])
end
