--[[
            24 * t // s ==  k                            CSoundGen::m_iTempoDecrement
             24 * t % s ==  rem                          CSoundGen::m_iTempoRemainder
                 24 * t ==  k * s + rem                  CSoundGen::m_iTempoAccum + rem

 60 * floor(1e6 / intv) ==  60 * framerate       (0.4.6) see CSoundGen::UpdatePlayer()
      floor(6e7 / intv) ==  60 * framerate       (0.5.0) see also CCompiler::CreateMainHeader()
                                                         this value is copied to var_Tempo_Count

For integer tick-per-row count,

floor(6e7 / intv) - rem ==  0 (mod k)                    Note: 0 <= rem < k need not hold
      floor(6e7 / intv) ==  rem + i * k                  for i integer
        rem + i * k + 1  >  6e7 / intv  >=  rem + i * k
6e7 / (rem + i * k + 1)  <     intv     <=  6e7 / (rem + i * k)
]]

local torate = function (t, s)
  print(("Tempo: %3d\nSpeed: %3d"):format(t, s))
  local k = math.floor(t * 24 / s)
  local rem = t * 24 % s
  local i = 0
  while true do
    local lo = math.floor(6e7 / (rem + i * k + 1)) + 1
    local hi = math.floor(6e7 / (rem + i * k))
    if lo > 65535 then goto continue end
    if lo > hi then break end
    if lo < hi then
      print(("%3d tick%s per row: %5d - %5d  %8.4f Hz - %8.4f Hz"):format(
        i, i > 1 and "s" or " ", lo, hi, 1e6 / hi, 1e6 / lo))
    else
      print(("%3d tick%s per row:         %5d                %8.4f Hz"):format(
        i, i > 1 and "s" or " ", hi, 1e6 / hi))
    end
    ::continue::
    i = i + 1
  end
end

for str in io.lines() do
  local a, b = str:match "^(%d+) (%d+)$"
  if a and b then torate(a, b) end
end