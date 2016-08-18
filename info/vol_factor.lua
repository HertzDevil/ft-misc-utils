-- VOL_TABLE[i][j] = i * j
-- VOL_TABLE_INV[i][j] = {k : k * j = i}
cartesian = function (ll) -- ll must be list of list
  local carry = {}
  local size = 1
  for i = #ll, 1, -1 do
    local s = #ll[i]
    if s == 0 then return function () return nil end end
    carry[i] = {div = size, modulo = s}
    size = size * s
  end
  
  local it = function (t, x)
    local z = {}
    x = (x or 0) + 1
    if x > size then return nil end
    for i, v in ipairs(t) do
      z[i] = v[math.floor((x - 1) / carry[i].div) % carry[i].modulo + 1]
    end
    return x, z
  end
  
  return it, ll, nil
end

local VOL_TABLE = {}
for i = 0, 15 do
  VOL_TABLE[i] = {}
  for j = 0, 15 do
    local v = i * j / 15
    VOL_TABLE[i][j] = v > 0 and v < 1 and 1 or math.floor(v)
  end
end
local VOL_TABLE_INV = {}
for i = 0, 15 do
  VOL_TABLE_INV[i] = {}
  for j = 0, 15 do -- for j = i, 15 do
    VOL_TABLE_INV[i][j] = {}
  end
end
for i = 0, 15 do
  for j = 0, 15 do
    VOL_TABLE_INV[VOL_TABLE[i][j]][j][i] = true
  end
end

seqFactor = function (...)
  local input = {}
  do
    local source = table.pack(...)
    for i = 1, #source do
      input[i] = {}
      table.move(source[i], 1, #source[i], 1, input[i])
    end
  end
  local size = 1
  for i = 1, #input do size = math.max(size, #input[i]) end
  for i = 1, #input do
    if #input[i] == 0 then input[i][1] = 0x0F end
    if #input[i] < size then
      for j = size, #input[i] + 1, -1 do input[i][j] = input[i][#input[i]] end
    end
  end
  
  local function factorStep (a, b)
    local mult = {}
    local ans = {}
    for i = 0, 15 do
      mult[i] = {}
      for j = 0, 15 do
        mult[i][j] = {corr = true}
        for k = 1, size do
          --if seq[a][k] > i or seq[b][k] > j then break end
          local join = {}
          for n in pairs(VOL_TABLE_INV[input[a][k]][i]) do
            if VOL_TABLE_INV[input[b][k]][j][n] then table.insert(join, n) end
          end
          if #join == 0 then mult[i][j].err = true; break end
          mult[i][j][k] = join
        end
        if not mult[i][j].err and (a ~= b or i == j) then
          for _, v in cartesian(mult[i][j]) do table.insert(ans, {seq = v, [a] = i, [b] = j}) end
        end
      end
    end
    return ans
  end
  
  if #input == 1 then return factorStep(1, 1) end
  local all = {}
  local final = {}
  for i = 1, #input do
    all[i] = factorStep(1, i)
  end
  for _, v in pairs(all[1]) do
    local t = {[1] = {v[1]}}
    for i = 2, #input do
      t[i] = {}
      for _, v2 in pairs(all[i]) do
        if v2[1] == t[1][1] then
          for j = 1, #v2.seq do
            if v2.seq[j] ~= v.seq[j] then goto continue end
          end
          table.insert(t[i], v2[i])
        end
        ::continue::
      end
    end
    for _, v2 in cartesian(t) do
      v2.seq = v.seq
      table.insert(final, v2)
    end
  end
  return final
end

local disp = function (...)
  local arg = table.pack(...)
  local result = seqFactor(...)
  print("Input:")
  for _, v in ipairs(arg) do
    print(string.format(" Sequence: {%s}", table.concat(v, " ")))
  end
  print("Output:")
  for i, t in ipairs(result) do
    local str = string.format(string.rep("%X", #t, ", "), table.unpack(t))
    print(string.format(" Volume: %s    Sequence: {%s}", str, table.concat(t.seq, " ")))
    if #t.seq > 252 then print("Warning: Sequence is longer than 252 terms") end
    if i == 5000 then
      print("Ouput limited to 5000 results.")
      break
    end
  end
  print(#result .. " result" .. (#result == 1 and "" or "s") .. " found.")
end

print("FamiTracker volume sequence factorizer")
disp({10, 9, 7}, {6, 5, 4})
