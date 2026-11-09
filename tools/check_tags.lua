--[[
	Lints the default tags in ShadowedUnitFrames_Forever/modules/tags.lua. Tag code lives inside Lua strings, so
	luacheck can't see it when it checks tags.lua itself.

	Run from the repo root:
	    lua5.1 tools/check_tags.lua [path/to/luacheck]

	It loads tags.lua with stubbed WoW globals, compiles every default tag (loadstring, like
	ShadowUF.tagFunc does), writes them all into one temp file and runs luacheck on it with the
	repo's .luacheckrc. Warnings are reported against the tag name and the line inside the tag.
	Exit code is non-zero if anything failed.
]]

local LUACHECK = arg[1] or os.getenv("LUACHECK") or "luacheck"

-- Globals that exist in the client (Blizzard's own code calls them) but aren't in
-- tools/forever_globals.lua because the API docs don't list them.
local EXTRA_GLOBALS = {"GetGuildInfo", "GetRaidRosterInfo", "GetNumGroupMembers"}

-- A stand-in for any WoW global: indexing or calling it gives itself back
local dummy = setmetatable({}, {__index = function(t) return t end, __call = function(t) return t end})

local env = setmetatable({
	ShadowUF = {L = setmetatable({}, {__index = function(_, k) return k end}), db = {profile = {tags = {}}}, tagFunc = {}},
	PowerBarColor = {MANA = {}, [0] = {}},
}, {__index = function(_, key)
	local value = _G[key]
	if( value ~= nil ) then return value end
	return dummy
end})

local function loadInto(path)
	local chunk = assert(loadfile(path))
	setfenv(chunk, env)
	chunk("ShadowedUnitFrames", env.ShadowUF)
end

loadInto("ShadowedUnitFrames_Forever/modules/secrets.lua")
loadInto("ShadowedUnitFrames_Forever/modules/tags.lua")

local Tags = env.ShadowUF.Tags
local names = {}
for name in pairs(Tags.defaultTags) do table.insert(names, name) end
table.sort(names)

local failed = false
local tmp = os.tmpname() .. ".lua"
local out = assert(io.open(tmp, "w"))
local lineMap = {}
local line = 1

-- Tag code is called with (unit, unitOwner, fontString) and may leave them unused
out:write("-- luacheck: ignore 212\n") line = line + 1
out:write("local _tags = {}\n") line = line + 1

for _, name in ipairs(names) do
	local code = Tags.defaultTags[name]

	-- Same compile step ShadowUF.tagFunc uses
	local func, msg = loadstring("return " .. code, name)
	if( not func ) then
		print(string.format("[%s] does not compile: %s", name, msg))
		failed = true
	elseif( type(func()) ~= "function" ) then
		print(string.format("[%s] does not return a function", name))
		failed = true
	end

	out:write(string.format("_tags[%q] = ", name))
	local start = line
	for _ in string.gmatch(code, "\n") do line = line + 1 end
	out:write(code, "\n")
	line = line + 1
	table.insert(lineMap, {name = name, first = start, last = line - 1})
end
out:write("return _tags\n")
out:close()

local cmd = string.format("%s --no-color --codes --formatter plain --globals ShadowUF --read-globals %s -- %s 2>&1",
	LUACHECK, table.concat(EXTRA_GLOBALS, " "), tmp)
local pipe = assert(io.popen(cmd))
local warnings = 0
for result in pipe:lines() do
	local lineNo, col, rest = string.match(result, "^[^:]+:(%d+):(%d+): (.*)$")
	if( lineNo ) then
		lineNo = tonumber(lineNo)
		local where = "?"
		for _, entry in ipairs(lineMap) do
			if( lineNo >= entry.first and lineNo <= entry.last ) then
				where = string.format("[%s] line %d", entry.name, lineNo - entry.first + 1)
				break
			end
		end
		print(string.format("%s:%s: %s", where, col, rest))
		warnings = warnings + 1
	elseif( result ~= "" ) then
		print(result)
	end
end
pipe:close()
os.remove(tmp)

print(string.format("Checked %d default tags, %d luacheck warning(s).", #names, warnings))
if( failed or warnings > 0 ) then os.exit(1) end
