-- higher order stuff

local function papply (f, ...)
	if select("#", ...) == 0 then return f end
	local x = ...
	return papply(function(...) return f(x, ...) end, select(2, ...))
end

local id = papply(select, 1)
local join = papply(papply, id)

local function compose (...)
	if select("#", ...) == 0 then return id end
	if select("#", ...) == 1 then return ... end
	local f, g = ..., compose(select(2, ...))
	return function (...) return f(g(...)) end
end

local function pick (n, ...)
	if n <= 0 then return end
	return (...), pick(n - 1, select(2, ...))
end

local function map (f, ...)
	if select("#", ...) == 0 then return end
	return f((...)), map(f, select(2, ...))
end

local function foldl (f, ...)
	if select("#", ...) == 0 then return end
	if select("#", ...) == 1 then return (...) end
	return foldl(f, f(pick(2, ...)), select(3, ...))
end

local function scanl (f, ...)
	if select("#", ...) == 0 then return end
	if select("#", ...) == 1 then return (...) end
	return (...), scanl(f, f(pick(2, ...)), select(3, ...))
end

local function rep (n, ...)
	if n <= 0 then return end
	return join(...)(rep(n - 1, ...))
end

local function adjacent_dif (f, ...)
	if select("#", ...) < 2 then return end
	return f(pick(2, ...)), adjacent_dif(f, select(2, ...))
end

-- helper functions

local add = function (x, y) return x + y end
local function gcd (x, y) return y > x and gcd(y, x) or y == 0 and x or gcd(y, x % y) end
math.round = function (x) return math.floor(x + .5) end
local sum = compose(papply(foldl, add), table.unpack)

local call = function (name) return function (t, ...) return t[name](t, ...) end end
local printf = compose(papply(call "write", io.stdout), call "format")

-- read standard input

local newrate, oldrate = io.stdin:read("*n", "*n")
assert(newrate and oldrate)
local Fxx = {}
while true do
	local x = io.stdin:read "*n"
	if not x then break end
	table.insert(Fxx, x)
end
printf("Refresh rate: %.2f Hz -> %.2f Hz\nOld:\t%s\nNew:\t",
	oldrate, newrate, table.concat(Fxx, '\t'))

-- wtf boom

local suc, msg = pcall(compose(
	print,
	papply(adjacent_dif, function (x, y) return y - x end),
	papply(map, math.round),
	papply(scanl, add, 0),
	papply(rep, oldrate / gcd(oldrate, sum(Fxx) * newrate)),
	papply(map, function (x) return x * newrate / oldrate end),
	table.unpack
), Fxx)
if not suc then io.stderr:write(msg) end
