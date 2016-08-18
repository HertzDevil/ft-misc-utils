local VIB_AMP = {
  0x01, 0x02, 0x03, 0x04, 0x06, 0x09, 0x0B, 0x0D, 0x10, 0x15, --0x1D, 0x2B, 0x3F, 0x5F, 0x7F,
}

local apulimit = function (x) return math.min(0x7FF, math.max(0, x)) end
local apufreq = function (x) return apulimit(math.floor(236250000 / 132 / 16 / x - 1 + .5)) end
local freqapu = function (x) return 236250000 / 132 / 16 / (x + 1) end
local hibyte = function (x) return math.floor(x / 0x100) % 0x100 end
local lobyte = function (x) return math.floor(x % 0x100) end

local detune = tonumber(io.stdin:read()) or 0 -- cents
local NOTE = {[0] = "C-", "C#", "D-", "D#", "E-", "F-", "F#", "G-", "G#", "A-", "A#", "B-"}
for i = 0, 95 do
  local reg = apufreq(440 * 2 ^ ((i - 45 + detune / 100) / 12))
  local pxx = {}
  for j = 1, #VIB_AMP do
    local upreg = apulimit(reg - VIB_AMP[j])
    local loreg = apulimit(reg + VIB_AMP[j])
    
    if hibyte(upreg) ~= hibyte(reg) or hibyte(loreg) ~= hibyte(reg) then
      local upoffs = math.log(freqapu(upreg) / freqapu(reg), 2) * 1200
      local looffs = math.log(freqapu(loreg) / freqapu(reg), 2) * 1200
      local det = lobyte(reg) >= 0x80 and lobyte(loreg) + 0x81 or lobyte(upreg) - 0x80
      pxx[#pxx + 1] = ("    4x%X: P%02X (%+6.1f ~ %+6.1f)"):format(j, det, looffs, upoffs)
    end
  end
  if #pxx > 0 then
  	io.stdout:write(("%s%d - %03X, %6.1f Hz"):format(
  	  NOTE[i % 12], math.floor(i / 12), reg, freqapu(reg)))
  	for i, v in ipairs(pxx) do
  	  if i % 3 == 1 then io.stdout:write '\n' end
  	  io.stdout:write(v)
  	end
  	io.stdout:write '\n'
  end
end
