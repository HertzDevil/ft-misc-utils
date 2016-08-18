local MULT = {1, 3, 2, 4, 6, 8, 10, 12, 16}

local assertParams = function (t)
  assert(type(t.file) == "string",
    "Bad filename")
  assert(type(t.vol) == "table" and #t.vol == #MULT,
    "Bad partial volume")
  assert(not t.master or (type(t.master) == "number" and t.master >= 0),
    "Bad master volume")
  assert(type(t.wavelen) == "number" and t.wavelen % 4 == 0 and t.wavelen >= 4 and t.wavelen <= 240,
    "Bad N163 wave size")
  assert(not t.perc or type(t.perc) == "table",
    "Bad percussion parameters")
  if t.perc then
    assert(type(t.perc.mult) == "number" and t.perc.mult >= 0,
      "Bad percussion frequency")
    assert(type(t.perc.vol) == "number" and t.perc.vol >= 0,
      "Bad percussion volume")
    assert(type(t.perc.len) == "number" and t.perc.len >= 0,
      "Bad percussion decay length")
  end
  return t
end

local generatewaves = function (arg)
  local base = {}
  local percussion = {}

  for i = 1, arg.wavelen do
    local val = 0
    for j = 1, #MULT do
      val = val + math.sin(2 * math.pi / arg.wavelen * (i - .5) * MULT[j]) * arg.vol[j]
    end
    base[i] = val / 8
    
    percussion[i] = not arg.perc and 0 or
                    math.sin(2 * math.pi / arg.wavelen * (i - .5) * arg.perc.mult) * arg.perc.vol
  end

  local out = {}
  local upper, lower = 0, 0
  local count = (arg.perc and arg.perc.len and math.ceil(arg.perc.len) or 0) + 1
  for i = 1, count do
    out[i] = {}
    for j = 1, arg.wavelen do
      local val = base[j] + percussion[j] * (1 - (i - 1) / count)
      out[i][j] = val
      upper = math.max(upper, val)
      lower = math.min(lower, val)
    end
  end

  if not arg.master then
    arg.master = upper <= lower and 1 or 7.5 / math.max(upper, -lower)
  end

  f = io.open(arg.file .. ".fti", "wb")
  f:write("FTI", "2.4", "\x05", string.pack("s4", arg.file))
  f:write(string.char(5, 0, 0, 0, 0, 0))
  f:write(string.pack("<I4I4I4", arg.wavelen, 0, count))
  for _, k in ipairs(out) do for _, v in ipairs(k) do
    local val = math.floor(arg.master * v + 7.5 + .5)
    val = math.min(15, math.max(0, val))
    f:write(string.char(val))
  end end
  f:close()
end

if arg[1] then
  local wavelen = 32
  if arg[2] then wavelen = tonumber(arg[2]) end

  generatewaves(assertParams{
--    vol = {8, 8, 8, 4, 0, 0, 0, 1, 2},
--    vol = {8, 6.5, 2, 0, 3, 0, 0, 1, 0},
    vol = {8, 4, 4, 0, 0, 4, 4, 4, 4},
    file = arg[1],
    --master = 1,
    wavelen = wavelen,
    perc = {
      mult = 6,
      vol = 1.5,
      len = 7,
    },
  })
  print(os.clock() .. " seconds elapsed.")
else
  io.write("Usage: \n  " .. arg[0] .. [[ name [wavesize]

Arguments: (edit these manually in the script)
  vol: partial volumes, max 8
  file: file name, extension omitted
  master: master volume, remove parameter for normalized waves
  perc:
    mult: percussion frequency
    vol: percussion volume, max 1
    len: percussion decay length
]])
end
