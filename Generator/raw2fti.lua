local desc = [[
Raw PCM to N163 FTI converter
Usage: lua raw2fti.lua [filename] [wavesize] [outname]

[filename]: Input raw PCM file name
[wavesize]: N163 wave size, default 128
[outname]: Output file name pattern, default "pcm"
]]
if not arg[1] then io.stdout:write(desc); os.exit(1) end

local wavesize = tonumber(arg[2]) or 128
local maxwaves = 16 -- 64 for 0CC-FT

local all = {}
local wav = {}
local samples = 0

local makefti; do
  local count = 0
makefti = function (t)
  local fname = ("%s-%03i.fti"):format(arg[3] or "pcm", count)
  local f = io.open(fname, "wb")
  count = count + 1
  f:write("FTI", "2.4", "\x05", ("s4"):pack(fname))
  f:write(string.char(5, 0, 0, 0, 0, 1))
  f:write(("<I4i4i4I4"):pack(#t, -1, -1, 0))
  for i = 1, #t do f:write(string.char(i - 1)) end
  f:write(("<I4I4I4"):pack(wavesize, 0, #t))
  for _, v in ipairs(t) do
    local w = table.concat(v)
    f:write(w, ("\x08"):rep(wavesize - #w))
  end
  f:close()
end; end

local pcm = io.open(arg[1], "rb")
for b in pcm:lines(1) do
  table.insert(wav, string.char((b:byte() >> 4) & 0xF))
  samples = samples + 1
  if samples % wavesize == 0 then
    table.insert(all, wav)
    wav = {}
    if samples % (wavesize * maxwaves) == 0 then
      makefti(all)
      all = {}
    end
  end
end
pcm:close()

if next(wav) then table.insert(all, wav) end
if next(all) then makefti(all) end