local MACHINE = {NTSC = 1, PAL = 2}
local RATE = {
  [MACHINE.NTSC] = {[0] = 428, 380, 340, 320, 286, 254, 226, 214, 190, 160, 142, 128, 106, 84, 72, 54},
  [MACHINE.PAL]  = {[0] = 398, 354, 316, 298, 276, 236, 210, 198, 176, 148, 132, 118,  98, 78, 66, 50},
}
local CLOCK = {
  [MACHINE.NTSC] = 236250000 / 132,
  [MACHINE.PAL]  = 26601712.5 / 16,
}
local THRESHOLD = 0.5 -- cents

-- m: machine name
-- p: dpcm pitch
-- f: frequency
local gen = function (m, p, f)
  local mstr = m
  m = assert(MACHINE[m], "machine \"" .. m .. "\" does not exist")
  assert(f > 0)
  local t = {}
  local rc = CLOCK[m] / RATE[m][p] / f / 8
  for len = 0x1, 0xFF1, 0x10 do
    local osc = math.floor(len / rc + .5)
    local cent = 1200 * math.log(osc / len * rc, 2)
    if math.abs(cent) <= THRESHOLD then
      t[#t + 1] = {len = len, osc = osc, cent = cent}
    end
  end
  table.sort(t, function (x, y) return math.abs(x.cent) < math.abs(y.cent) end)
  print(("Frequency %.2f Hz, %s, DPCM pitch %.1X:"):format(f, mstr, p))
  -- length in bytes, length in seconds, oscillation count, detune in cents
  print(" Length   (samp)  Count   Detune")
  for _, v in ipairs(t) do
    print(("%7d %7.0f %7d %+8.3f"):format(v.len, v.len * 8 / (CLOCK[m] / RATE[m][p]) * 48000, v.osc, v.cent))
  end
  print(#t .. " results found.")
end

-- synopsis
-- note names, display only
local NOTE = {"A-3", "A#3", "B-3", "C-4", "C#4"}
-- iterate through these notes
for i, v in ipairs(NOTE) do
  -- real frequency, "- 25" is transposition
  local realFreq = 440 * 2 ^ ((i - 1) / 12 - 18 / 1200)
  -- calculate the 2A03 period register, "- 25" is transposition
  local preg = math.floor(CLOCK[MACHINE.NTSC] / 16 / realFreq - 1 + .5)
  -- obtain the actual frequency on the 2A03
  local freq = CLOCK[MACHINE.NTSC] / 16 / (preg + 1)
  -- print info
  print(("Note %s, real frequency = %.2f Hz, period register = $%04X"):format(v, realFreq, preg))
  -- print results
  gen("NTSC", 15, freq)
end