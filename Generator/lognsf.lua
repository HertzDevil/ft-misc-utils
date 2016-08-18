-- table with numeric keys sorted ascending for iteration
local NumSort = function ()
  local order = {}
  return setmetatable({}, {
    __metatable = "NumSort",
    __newindex = function (t, k, v)
      rawset(t, k, v)
      if not order[1] then order[1] = k; return end
      if k < order[1] then table.insert(order, 1, k); return end
      if k > order[#order] then order[#order + 1] = k; return end
      local b, e = 1, #order
      while e - b > 1 do
        local m = math.ceil((b + e) / 2)
        if k < order[m] then e = m
        elseif k > order[m] then b = m
        else break end
      end
      table.insert(order, e, k)
    end,
    __len = function (t)
      return #order
    end,
    __pairs = function (t)
      return coroutine.wrap(function ()
        for _, v in ipairs(order) do
          coroutine.yield(v, t[v])
        end
      end)
    end,
  })
end

-- tracing
local Tracer; do
  local mt = {
    __metatable = "Tracer",
    __index = {
      access = function (self, adr, t)
        if not self.accessed[adr] then
          self.accessed[adr] = t
          if not self.frame[t] then
            if t > self.lastframe then self.lastframe = t end
            self.frame[t] = NumSort()
          end
          self.frame[t][adr] = true
        end
      end,
    },
    __pairs = function (self)
      return coroutine.wrap(function ()
        for f, t in pairs(self.frame) do
          for k in pairs(t) do coroutine.yield(k, f) end
        end
      end)
    end
  }
Tracer = function ()
  return setmetatable({
    accessed = NumSort(),
    frame = NumSort(),
    lastframe = -1
  }, mt)
end; end

-- constants
-- flag enumeration
local FL = {}
for i, v in ipairs {"C", "Z", "I", "-", "B", "-", "V", "N"} do FL[v] = i end -- D is not supported
-- addressing mode enumeration
local ADR = {}
for i, v in ipairs {"imp", "imm", "zp", "zpx", "zpy", "izx", "izy", "abs", "abx", "aby", "ind", "rel"} do ADR[v] = i end
-- i/o
local WRITABLE = {
  {0x0000, 0x07FF},
  --{0x5FF6, 0x5FF7},
  {0x5FF8, 0x5FFF},
  --{0x6000, 0x7FFF},
  --{0x8000, 0xDFFF},
}
--local CHIP = {[1] = "VRC6", [2] = "VRC7", [4] = "FDS", [8] = "MMC5", [16] = "N163", [32] = "5B"}
local IOREGS = {
  {0x4000, 0x4013}, -- 2A03
  {0x4015, 0x4015},
  {0x4017, 0x4017},
  {0x9000, 0x9003}, -- VRC6
  {0xA000, 0xA002},
  {0xB000, 0xB002},
  {0x9010, 0x9010}, -- VRC7
  {0x9030, 0x9030},
  {0x4040, 0x408A}, -- FDS
  {0x5205, 0x5206}, -- MMC5
  {0x5C00, 0x5FF5},
  {0x4800, 0x4800}, -- N163
  {0xF800, 0xF800},
  {0xC000, 0xC000}, -- 5B
  {0xE000, 0xE000},
}

-- helper functions
local signed = function (x) return (x & 0xFF) - (x & 0x80 ~= 0 and 0x100 or 0) end
local boolnum = function (x) return x and 1 or 0 end

-- registers
local mem
local flag
-- extra states
local lastPC
local lastOP
local opcount
local nextSwitch
local frame
local codetrace
local datatrace
local iotrace

-- initialization
local initState = function ()
  mem = {A = 0x00, X = 0x00, Y = 0x00, PC = 0x0000, S = 0xFF}
  for i = 0, 0xFFFF do mem[i] = 0x00 end
  -- mem.LOAD, mem.INIT, mem.PLAY, mem.switch = 0x8000, 0x8000, 0x8000, false
  flag = {}
  for _, v in pairs(FL) do flag[v] = false end
  lastPC = 0
  lastOP = "NOP"
  opcount = 0
  nextSwitch = nil
  frame = -1
  codetrace = Tracer()
  datatrace = Tracer()
  iotrace = {}
end

-- display
local dumpRegs = function ()
  local t = {}
  for i = #flag, 1, -1 do t[#t + 1] = boolnum(flag[i]) end
  print(string.format("A: %02X X: %02X Y: %02X PC: %04X S: %02X NV-BDIZC: %d%d%d%d%d%d%d%d",
      mem.A, mem.X, mem.Y, mem.PC, mem.S, table.unpack(t)))
end
local dumpStack = function ()
  dumpMem(0x100 + mem.S, 0x100 - mem.S)
  dumpMem(0x1E0, 0x20)
end
local dumpMem = function (begin, size, row)
  row = row or 16
  local t = {}
  local e = begin + size - 1
  for i = begin, e, row do
    local r = {[1] = mem[i]}
    local s = math.min(i + row - 1, e)
    table.move(mem, i + 1, s, 2, r)
    t[#t + 1] = string.format("%04X:" .. string.rep(" %02X", #r), i, table.unpack(r))
  end
  print(table.concat(t, "\n"))
end
local dumpIO = function ()
  print("Frame " .. frame)
  for _, v in ipairs(iotrace) do
    io.write(string.format("$%04X <- #$%02X   ", v.pos, v.val))
  end
  io.write("\n")
  iotrace = {}
end

local originalAdr = function (adr)
  if adr > 0xFFFF or adr < 0x8000 then return -1 end
  if not mem.switch then return adr >= mem.LOAD and adr + 0x80 - mem.LOAD or -1 end
  local index = (adr >> 12) - 8
  if index == 0 and (adr & 0xFFF) < (mem.LOAD & 0xFFF) then return -1 end
  return mem[0x5FF8 + index] * 0x1000 + 0x80 + (adr & 0xFFF) - (mem.LOAD & 0xFFF)
end

local readVal = function (pos, count)
  count = count or 1
  local z = 0
  for i = 0, count - 1 do
    local adr = (pos & 0xFF00) | (pos + i & 0xFF)
    z = z + (mem[adr] << i * 8)
  end
  return z
end
local readPC = function (count)
  count = count or 1
  local z = 0
  for i = 1, count do
    z = z + (mem[mem.PC] << (i - 1) * 8)
    local adr = originalAdr(mem.PC)
    if mem.PC < 0x3FF0 or mem.PC > 0x3FF7 then codetrace:access(adr, frame) end
    mem.PC = mem.PC + 1 & 0xFFFF
  end
  return z
end
local writeVal = function (pos, val)
  local protected = true
  if type(pos) == "string" then
    if mem[pos] ~= nil then protected = false end
  else
    if pos >= 0x5FF8 and pos <= 0x5FFF then nextSwitch = pos & 0x7 end
    for _, v in ipairs(WRITABLE) do if pos >= v[1] and pos <= v[2] then protected = false; break end end
  end
  if not protected then mem[pos] = val end
  for _, v in ipairs(IOREGS) do if pos >= v[1] and pos <= v[2] then table.insert(iotrace, {pos = pos, val = val}) end end
end

-- addressing modes
local getAdr = {}
getAdr[ADR.imp] = function () return "A" end -- for shift/rotate
getAdr[ADR.imm] = function () return mem.PC end
getAdr[ADR.zp]  = function () return readPC(1) end
getAdr[ADR.zpx] = function () return readPC(1) + mem.X & 0xFF end
getAdr[ADR.zpy] = function () return readPC(1) + mem.Y & 0xFF end
getAdr[ADR.izx] = function () return readVal(readPC(1) + mem.X & 0xFF, 2) end
getAdr[ADR.izy] = function () return readVal(readPC(1), 2) + mem.Y & 0xFFFF end
getAdr[ADR.abs] = function () return readPC(2) end
getAdr[ADR.abx] = function () return readPC(2) + mem.X & 0xFFFF end
getAdr[ADR.aby] = function () return readPC(2) + mem.Y & 0xFFFF end
getAdr[ADR.ind] = function () return readVal(readPC(2), 2) end
getAdr[ADR.rel] = function () return mem.PC + signed(readPC(1)) + 1 & 0xFFFF end

-- read from effective address
local getVal = function (adrMode)
  if adrMode == ADR.imm then return readPC(1) end
  local adr = getAdr[adrMode]()
  if adrMode ~= ADR.imp and adr >= 0x8000 and adr <= 0xFFFF then
    datatrace:access(originalAdr(adr), frame)
  end
  return mem[adr]
end

-- register assignment
local updateFlags = function (val, ...)
  for _, v in ipairs {...} do
    if v == FL.Z then flag[v] = val == 0
    elseif v == FL.N then flag[v] = val & 0x80 ~= 0
    elseif v == FL.C then flag[v] = val >= 0
    end
  end
end
local assignMem = function (name, val) mem[name] = val; updateFlags(val, FL.Z, FL.N) end

-- stack operations
local STACK_POS = 0x100
local pushStack = function (...)
  for _, v in ipairs {...} do
    mem[STACK_POS + mem.S] = v
    mem.S = (mem.S - 1) & 0xFF
  end
end
local popStack = function (count)
  count = count or 1
  local t = {}
  for i = 1, count do
    mem.S = (mem.S + 1) & 0xFF
    t[#t + 1] = mem[STACK_POS + mem.S]
  end
  return table.unpack(t)
end

-- opcodes
local opcode = {}
opcode.ORA = function (adrMode) assignMem("A", mem.A | getVal(adrMode)) end
opcode.AND = function (adrMode) assignMem("A", mem.A & getVal(adrMode)) end
opcode.EOR = function (adrMode) assignMem("A", mem.A ~ getVal(adrMode)) end
opcode.ADC = function (adrMode) local v = mem.A + getVal(adrMode) + boolnum(flag[FL.C]);
    flag[FL.C] = v > 0xFF; flag[FL.V] = flag[FL.C]; assignMem("A", v & 0xFF) end
opcode.SBC = function (adrMode) local v = mem.A - getVal(adrMode) - boolnum(not flag[FL.C]);
    flag[FL.C] = v >= 0; flag[FL.V] = not flag[FL.C]; assignMem("A", v & 0xFF) end
opcode.CMP = function (adrMode) updateFlags(mem.A - getVal(adrMode), FL.Z, FL.N, FL.C) end
opcode.CPX = function (adrMode) updateFlags(mem.X - getVal(adrMode), FL.Z, FL.N, FL.C) end
opcode.CPY = function (adrMode) updateFlags(mem.Y - getVal(adrMode), FL.Z, FL.N, FL.C) end
opcode.DEC = function (adrMode) local p = getAdr[adrMode](); assignMem(p, mem[p] - 1 & 0xFF) end
opcode.DEX = function () assignMem("X", (mem.X - 1) & 0xFF) end
opcode.DEY = function () assignMem("Y", (mem.Y - 1) & 0xFF) end
opcode.INC = function (adrMode) local p = getAdr[adrMode](); assignMem(p, mem[p] + 1 & 0xFF) end
opcode.INX = function () assignMem("X", (mem.X + 1) & 0xFF) end
opcode.INY = function () assignMem("Y", (mem.Y + 1) & 0xFF) end
opcode.ASL = function (adrMode) local p = getAdr[adrMode]();
    flag[FL.C] = mem[p] & 0x80 ~= 0; assignMem(p, mem[p] << 1 & 0xFF); if flag[FL.C] then flag[FL.Z] = false end end
opcode.ROL = function (adrMode) local p = getAdr[adrMode](); local c = boolnum(flag[FL.C]);
    flag[FL.C] = mem[p] & 0x80 ~= 0; assignMem(p, (mem[p] << 1) + c & 0xFF) end
opcode.LSR = function (adrMode) local p = getAdr[adrMode](); flag[FL.C] = mem[p] & 0x01 ~= 0; assignMem(p, mem[p] >> 1) end
opcode.ROR = function (adrMode) local p = getAdr[adrMode](); local c = boolnum(flag[FL.C]);
    flag[FL.C] = mem[p] & 0x01 ~= 0; assignMem(p, (mem[p] >> 1) + c * 0x80) end

opcode.LDA = function (adrMode) assignMem("A", getVal(adrMode)) end
opcode.STA = function (adrMode) writeVal(getAdr[adrMode](), mem.A) end
opcode.LDX = function (adrMode) assignMem("X", getVal(adrMode)) end
opcode.STX = function (adrMode) writeVal(getAdr[adrMode](), mem.X) end
opcode.LDY = function (adrMode) assignMem("Y", getVal(adrMode)) end
opcode.STY = function (adrMode) writeVal(getAdr[adrMode](), mem.Y) end
opcode.TAX = function () assignMem("X", mem.A) end
opcode.TXA = function () assignMem("A", mem.X) end
opcode.TAY = function () assignMem("Y", mem.A) end
opcode.TYA = function () assignMem("A", mem.Y) end
opcode.TSX = function () assignMem("X", mem.S) end
opcode.TXS = function () mem.S = mem.X end
opcode.PLA = function () assignMem("A", popStack()) end
opcode.PHA = function () pushStack(mem.A) end
opcode.PLP = function () local z = popStack(); for i = 0, 7 do flag[i + 1] = (z & (1 << i)) ~= 0 end end
opcode.PHP = function () local z = 0; for i = 0, 7 do z = z + (flag[i + 1] and (1 << i) or 0) end; pushStack(z) end

opcode.BPL = function (adrMode) local p = getAdr[adrMode](); if flag[FL.N] == false then mem.PC = p end end
opcode.BMI = function (adrMode) local p = getAdr[adrMode](); if flag[FL.N] == true then mem.PC = p end end
opcode.BVC = function (adrMode) local p = getAdr[adrMode](); if flag[FL.V] == false then mem.PC = p end end
opcode.BVS = function (adrMode) local p = getAdr[adrMode](); if flag[FL.V] == true then mem.PC = p end end
opcode.BCC = function (adrMode) local p = getAdr[adrMode](); if flag[FL.C] == false then mem.PC = p end end
opcode.BCS = function (adrMode) local p = getAdr[adrMode](); if flag[FL.C] == true then mem.PC = p end end
opcode.BNE = function (adrMode) local p = getAdr[adrMode](); if flag[FL.Z] == false then mem.PC = p end end
opcode.BEQ = function (adrMode) local p = getAdr[adrMode](); if flag[FL.Z] == true then mem.PC = p end end
opcode.BRK = function () print("BRK is not implemented") end
opcode.RTI = function () print("RTI is not implemented") end
opcode.JSR = function (adrMode) pushStack(mem.PC + 1 >> 8, mem.PC + 1 & 0xFF); mem.PC = getAdr[adrMode]() end
opcode.RTS = function () local lo, hi = popStack(2); mem.PC = (lo | (hi << 8)) + 1 end
opcode.JMP = function (adrMode) mem.PC = getAdr[adrMode]() end
opcode.BIT = function (adrMode) local v = getVal(adrMode); flag[FL.N], flag[FL.V], flag[FL.Z] = v & 0x80 ~= 0, v & 0x40 ~= 0, v & mem.A ~= 0 end
opcode.CLC = function () flag[FL.C] = false end
opcode.SEC = function () flag[FL.C] = true end
opcode.CLD = function () flag[FL.D] = false end
opcode.SED = function () flag[FL.D] = true end
opcode.CLI = function () flag[FL.I] = false end
opcode.SEI = function () flag[FL.I] = true end
opcode.CLV = function () flag[FL.V] = false end
opcode.NOP = function () end

opcode.err = function () print("Illegal opcode") end

-- lookup table
local OP = {
  {"BRK", "imp"}, {"ORA", "izx"}, {"KIL", "imp"}, {"SLO", "izx"}, {"NOP", "zp" }, {"ORA", "zp" }, {"ASL", "zp" }, {"SLO", "zp" }, {"PHP", "imp"}, {"ORA", "imm"}, {"ASL", "imp"}, {"ANC", "imm"}, {"NOP", "abs"}, {"ORA", "abs"}, {"ASL", "abs"}, {"SLO", "abs"},
  {"BPL", "rel"}, {"ORA", "izy"}, {"KIL", "imp"}, {"SLO", "izy"}, {"NOP", "zpx"}, {"ORA", "zpx"}, {"ASL", "zpx"}, {"SLO", "zpx"}, {"CLC", "imp"}, {"ORA", "aby"}, {"NOP", "imp"}, {"SLO", "aby"}, {"NOP", "abx"}, {"ORA", "abx"}, {"ASL", "abx"}, {"SLO", "abx"},
  {"JSR", "abs"}, {"AND", "izx"}, {"KIL", "imp"}, {"RLA", "izx"}, {"BIT", "zp" }, {"AND", "zp" }, {"ROL", "zp" }, {"RLA", "zp" }, {"PLP", "imp"}, {"AND", "imm"}, {"ROL", "imp"}, {"ANC", "imm"}, {"BIT", "abs"}, {"AND", "abs"}, {"ROL", "abs"}, {"RLA", "abs"},
  {"BMI", "rel"}, {"AND", "izy"}, {"KIL", "imp"}, {"RLA", "izy"}, {"NOP", "zpx"}, {"AND", "zpx"}, {"ROL", "zpx"}, {"RLA", "zpx"}, {"SEC", "imp"}, {"AND", "aby"}, {"NOP", "imp"}, {"RLA", "aby"}, {"NOP", "abx"}, {"AND", "abx"}, {"ROL", "abx"}, {"RLA", "abx"},
  {"RTI", "imp"}, {"EOR", "izx"}, {"KIL", "imp"}, {"SRE", "izx"}, {"NOP", "zp" }, {"EOR", "zp" }, {"LSR", "zp" }, {"SRE", "zp" }, {"PHA", "imp"}, {"EOR", "imm"}, {"LSR", "imp"}, {"ALR", "imm"}, {"JMP", "abs"}, {"EOR", "abs"}, {"LSR", "abs"}, {"SRE", "abs"},
  {"BVC", "rel"}, {"EOR", "izy"}, {"KIL", "imp"}, {"SRE", "izy"}, {"NOP", "zpx"}, {"EOR", "zpx"}, {"LSR", "zpx"}, {"SRE", "zpx"}, {"CLI", "imp"}, {"EOR", "aby"}, {"NOP", "imp"}, {"SRE", "aby"}, {"NOP", "abx"}, {"EOR", "abx"}, {"LSR", "abx"}, {"SRE", "abx"},
  {"RTS", "imp"}, {"ADC", "izx"}, {"KIL", "imp"}, {"RRA", "izx"}, {"NOP", "zp" }, {"ADC", "zp" }, {"ROR", "zp" }, {"RRA", "zp" }, {"PLA", "imp"}, {"ADC", "imm"}, {"ROR", "imp"}, {"ARR", "imm"}, {"JMP", "ind"}, {"ADC", "abs"}, {"ROR", "abs"}, {"RRA", "abs"},
  {"BVS", "rel"}, {"ADC", "izy"}, {"KIL", "imp"}, {"RRA", "izy"}, {"NOP", "zpx"}, {"ADC", "zpx"}, {"ROR", "zpx"}, {"RRA", "zpx"}, {"SEI", "imp"}, {"ADC", "aby"}, {"NOP", "imp"}, {"RRA", "aby"}, {"NOP", "abx"}, {"ADC", "abx"}, {"ROR", "abx"}, {"RRA", "abx"},
  {"NOP", "imm"}, {"STA", "izx"}, {"NOP", "imm"}, {"SAX", "izx"}, {"STY", "zp" }, {"STA", "zp" }, {"STX", "zp" }, {"SAX", "zp" }, {"DEY", "imp"}, {"NOP", "imm"}, {"TXA", "imp"}, {"XAA", "imm"}, {"STY", "abs"}, {"STA", "abs"}, {"STX", "abs"}, {"SAX", "abs"},
  {"BCC", "rel"}, {"STA", "izy"}, {"KIL", "imp"}, {"AHX", "izy"}, {"STY", "zpx"}, {"STA", "zpx"}, {"STX", "zpy"}, {"SAX", "zpy"}, {"TYA", "imp"}, {"STA", "aby"}, {"TXS", "imp"}, {"TAS", "aby"}, {"SHY", "abx"}, {"STA", "abx"}, {"SHX", "aby"}, {"AHX", "aby"},
  {"LDY", "imm"}, {"LDA", "izx"}, {"LDX", "imm"}, {"LAX", "izx"}, {"LDY", "zp" }, {"LDA", "zp" }, {"LDX", "zp" }, {"LAX", "zp" }, {"TAY", "imp"}, {"LDA", "imm"}, {"TAX", "imp"}, {"LAX", "imm"}, {"LDY", "abs"}, {"LDA", "abs"}, {"LDX", "abs"}, {"LAX", "abs"},
  {"BCS", "rel"}, {"LDA", "izy"}, {"KIL", "imp"}, {"LAX", "izy"}, {"LDY", "zpx"}, {"LDA", "zpx"}, {"LDX", "zpy"}, {"LAX", "zpy"}, {"CLV", "imp"}, {"LDA", "aby"}, {"TSX", "imp"}, {"LAS", "aby"}, {"LDY", "abx"}, {"LDA", "abx"}, {"LDX", "aby"}, {"LAX", "aby"},
  {"CPY", "imm"}, {"CMP", "izx"}, {"NOP", "imm"}, {"DCP", "izx"}, {"CPY", "zp" }, {"CMP", "zp" }, {"DEC", "zp" }, {"DCP", "zp" }, {"INY", "imp"}, {"CMP", "imm"}, {"DEX", "imp"}, {"AXS", "imm"}, {"CPY", "abs"}, {"CMP", "abs"}, {"DEC", "abs"}, {"DCP", "abs"},
  {"BNE", "rel"}, {"CMP", "izy"}, {"KIL", "imp"}, {"DCP", "izy"}, {"NOP", "zpx"}, {"CMP", "zpx"}, {"DEC", "zpx"}, {"DCP", "zpx"}, {"CLD", "imp"}, {"CMP", "aby"}, {"NOP", "imp"}, {"DCP", "aby"}, {"NOP", "abx"}, {"CMP", "abx"}, {"DEC", "abx"}, {"DCP", "abx"},
  {"CPX", "imm"}, {"SBC", "izx"}, {"NOP", "imm"}, {"ISC", "izx"}, {"CPX", "zp" }, {"SBC", "zp" }, {"INC", "zp" }, {"ISC", "zp" }, {"INX", "imp"}, {"SBC", "imm"}, {"NOP", "imp"}, {"SBC", "imm"}, {"CPX", "abs"}, {"SBC", "abs"}, {"INC", "abs"}, {"ISC", "abs"},
  {"BEQ", "rel"}, {"SBC", "izy"}, {"KIL", "imp"}, {"ISC", "izy"}, {"NOP", "zpx"}, {"SBC", "zpx"}, {"INC", "zpx"}, {"ISC", "zpx"}, {"SED", "imp"}, {"SBC", "aby"}, {"NOP", "imp"}, {"ISC", "aby"}, {"NOP", "abx"}, {"SBC", "abx"}, {"INC", "abx"}, {"ISC", "abx"},
}
local runOpcode = function ()
  lastPC = mem.PC
  local o = OP[readPC(1) + 1]
  if not opcode[o[1]] then o[1] = "err" end
  lastOP = o[1] .. " " .. o[2]
  opcode[o[1]](ADR[o[2]])
  --print(lastPC, o[1], o[2])
  opcount = opcount + 1
end

local dumpSongTrace = function (code, data)
  local l = NumSort()
  for k, v in pairs(code) do
    l[k] = {frame = v, code = true}
  end
  for k, v in pairs(data) do
    if l[k] then
      l[k].data = true
    else
      l[k] = {frame = v, data = true}
    end
  end

  io.output(io.open("lognsf_output.txt", "w"))
  for k, v in pairs(l) do
    if v.code then io.write(("$%06X first accessed as code on frame %d\n"):format(k, v.frame)) end
    if v.data then io.write(("$%06X first accessed as data on frame %d\n"):format(k, v.frame)) end
  end
  io.output():close()
  io.output(io.open("lognsf_output2.txt", "w"))
  for k, v in pairs(code) do
    io.write(("$%06X first accessed as code on frame %d\n"):format(k, v))
  end
  for k, v in pairs(data) do
    io.write(("$%06X first accessed as data on frame %d\n"):format(k, v))
  end
  io.output():close()
end

local lognsf = function (fname, param)
  local f = io.open(fname, "rb")
  if not f then error("Cannot open NSF file") end
  if f:read(6) ~= "NESM\x1A\x01" then error("File is not a valid NSF") end
  local TRACK = f:read(1):byte()
  f:read(1) -- first track
  local tracklist = {}
  for i = 1, TRACK do table.insert(tracklist, i) end
  local LOAD = ("<I2"):unpack(f:read(2))
  local INIT = ("<I2"):unpack(f:read(2))
  local PLAY = ("<I2"):unpack(f:read(2))
  local INFO = {}
  INFO.TITLE = f:read(0x20)
  INFO.AUTHOR = f:read(0x20)
  INFO.COPYRIGHT = f:read(0x20)
  f:seek("set", 0x70)
  local switch = false
  local banks = {}
  for i = 1, 8 do
    banks[i] = f:read(1):byte()
    switch = switch or banks[i] ~= 0
  end
  f:seek("set", 0x7A)
  local REGION = f:read(1):byte()

  -- initialization
  local bankswitch = function (index, banknum)
    mem[0x5FF8 + index] = banknum
    if banknum == 0 then
      f:seek("set", 0x80)
      for i = (8 + index) * 0x1000, (9 + index) * 0x1000 - 1 do
        local b = (i & 0xFFF) < (LOAD & 0xFFF) and "\0" or f:read(1)
        mem[i] = b and b:byte() or 0x00
      end
    else
      f:seek("set", banknum * 0x1000 + 0x80 - (LOAD & 0xFFF))
      for i = (8 + index) * 0x1000, (9 + index) * 0x1000 - 1 do
        local b = f:read(1)
        mem[i] = b and b:byte() or 0x00
      end
    end
  end

  local callInit = function (track)
    initState()
    mem[0x3FF0], mem[0x3FF1], mem[0x3FF2] = 0x20, INIT & 0xFF, INIT >> 8
    mem[0x3FF4], mem[0x3FF5], mem[0x3FF6] = 0x20, PLAY & 0xFF, PLAY >> 8
    mem.LOAD = LOAD
    mem.switch = switch
    if switch then
      for i = 0, 7 do
        bankswitch(i, banks[i + 1])
      end
    else
      f:seek("set", 0x80)
      for i = LOAD, 0xFFFF do
        local b = f:read(1)
        mem[i] = b and b:byte() or 0x00
      end
    end
    mem.PC = 0x3FF0
    mem.A = track
    mem.X = REGION
    while mem.PC ~= 0x3FF3 do
      runOpcode()
      if nextSwitch then
        bankswitch(nextSwitch, mem[0x5FF8 + nextSwitch])
        nextSwitch = nil
      end
    end
    frame = 0
  end

  local callPlay = function ()
    mem.S = 0xFF
    mem.PC = 0x3FF4
    while mem.PC ~= 0x3FF7 do
      runOpcode()
      if nextSwitch then
        print("Bankswitching")
        bankswitch(nextSwitch, mem[0x5FF8 + nextSwitch])
        nextSwitch = nil
      end
    end
    frame = frame + 1
  end

--[[
  callInit(1)
  repeat
    callPlay()
  until frame >= math.max(codetrace.lastframe, datatrace.lastframe) + param.timeout;
  dumpSongTrace(codetrace, datatrace)
]]

  local codeAll = NumSort()
  local dataAll = NumSort()
  local codeSet = {}
  local dataSet = {}

  for _, i in ipairs(tracklist) do
    print("Tracing song " .. i .. "...")
    callInit(i - 1)
    repeat
      callPlay()
    until frame >= math.max(codetrace.lastframe, datatrace.lastframe) + param.timeout;
    codeSet[i] = codetrace
    dataSet[i] = datatrace
    for v in pairs(codetrace) do
      if not codeAll[v] then
        codeAll[v] = NumSort()
      end
      codeAll[v][i] = true
    end
    for v in pairs(datatrace) do
      if not dataAll[v] then
        dataAll[v] = NumSort()
      end
      dataAll[v][i] = true
    end
  end

  print("Generating log file...")
  io.output(io.open(param.fname, "w"))
  io.write(("File name: %s\nTitle: %s\nAuthor: %s\nCopyright: %s\n%d tracks\n"):format(
    fname:gsub(".*[/\\]", ""), INFO.TITLE, INFO.AUTHOR, INFO.COPYRIGHT, TRACK))
  io.write("Bankswitching ", (switch and "enabled" or "disabled"), '\n')
  for i = 0, 7 do bankswitch(i, banks[i + 1]) end
  io.write(("INIT address: $%X\n"):format(originalAdr(INIT)))
  io.write(("PLAY address: $%X\n"):format(originalAdr(PLAY)))

  local trackStr = {}
  local ranges = {}
  local rangesAll = NumSort()
  for _, i in ipairs(tracklist) do trackStr[i], ranges[i] = "", {} end

  io.write "\n\n\nCommon data:\n"
  for k, v in pairs(dataAll) do
    f:seek("set", k)
    if #v > 1 then
      io.write(("$%06X:%02X accessed in tracks:"):format(k, f:read(1):byte()))
      for i in pairs(v) do io.write((" %3d"):format(i)) end
      io.write '\n'
    else
      local t = next(v)
      local r = ranges[t][#ranges[t]]
      if r and r[2] == k - 1 then
        r[2] = k
      else
        table.insert(ranges[t], {k, k})
      end
      trackStr[t] = trackStr[t] .. ("$%06X:%02X first accessed on frame %4d\n"):format(
        k, f:read(1):byte(), dataSet[t].accessed[k])
    end
  end
  io.write("\n\n\nTrack data:\n")
  for i, t in next, ranges do for _, v in ipairs(t) do
    v[3] = i
    rangesAll[v[1]] = v
  end end
  for _, v in pairs(rangesAll) do
    io.write(("Track %03d: $%06X - $%06X (%d byte%s)\n"):format(
      v[3], v[1], v[2], v[2] - v[1] + 1, v[1] == v[2] and "" or "s"))
  end
  for _, i in ipairs(tracklist) do
    io.write("\n\n\nTrack " .. i .. " accesses:\n", trackStr[i])
  end
  
  local coderange = {}
  for k, v in pairs(codeAll) do if #v == TRACK then
    local r = coderange[#coderange]
    if r and r[2] == k - 1 then
      r[2] = k
    else
      table.insert(coderange, {k, k})
    end
  end end

  io.write "\n\n\nCommon code:\n"
  for _, v in ipairs(coderange) do
    io.write(("$%06X - $%06X (%d byte%s)\n"):format(
      v[1], v[2], v[2] - v[1] + 1, v[1] == v[2] and "" or "s"))
  end
  io.write "\n\n\nConditional code:\n"
  for k, v in pairs(codeAll) do if #v < TRACK then
    f:seek("set", k)
    io.write(("$%06X:%02X accessed in tracks:"):format(k, f:read(1):byte()))
    for i in pairs(v) do io.write((" %3d"):format(i)) end
    io.write '\n'
  end end

  io.output():close()
  f:close()
end

local DESC = "Usage: " .. arg[-1]:gsub(".*[/\\]", ""):gsub("%.exe$", "")
                       .. " " .. arg[0]:gsub(".*[/\\]", "")
                       .. ""
local main = function ()
  if not arg[1] then
    print(DESC); os.exit(0)
  end

  local param = {
    fname = arg[2] or "lognsf_output.txt",
    timeout = 1200,
  }

  lognsf(arg[1], param)
  print(os.clock() .. " seconds elapsed.")
  os.exit(0)
end

main()
