--[[
	Runs every default tag against stubbed WoW APIs, with plain values and with fake secret
	values, to prove no tag raises an error when the game hides values from addons.

	Run from the repo root:
	    lua5.1 tools/test_tags.lua [-v]

	A fake secret is a newproxy userdata whose metatable errors on arithmetic, ordering
	comparisons, #, indexing and calling, and allows concatenation (giving another secret).
	string.format/tostring are wrapped so a secret argument gives a secret string, as in game.

	Limits (Lua 5.1 can't intercept these, review them by hand):
	- truthiness tests (if x, x and y, x or y, not x) on a secret pass silently here;
	- secret == plain is just false here (in game it errors).
	To catch most of those anyway, the test also wraps every secret-returning API so that
	tag code which tests a secret without issecretvalue() usually takes a branch that ends in
	an error (see SECRET_TRUTHY below), and greps the tag source for risky patterns.
]]

local verbose = arg[1] == "-v"

---------------------------------------------------------------------------
-- Fake secrets
---------------------------------------------------------------------------
local secrets = setmetatable({}, {__mode = "k"})
local secretMeta
local function newSecret(desc)
	local proxy = newproxy(true)
	local meta = getmetatable(proxy)
	for key, value in pairs(secretMeta) do meta[key] = value end
	secrets[proxy] = desc or "secret"
	return proxy
end

local function fail(op) return function() error("attempt to " .. op .. " a secret value", 2) end end
secretMeta = {
	__index = fail("index"), __newindex = fail("index"), __call = fail("call"), __len = fail("get length of"),
	__add = fail("do arithmetic on"), __sub = fail("do arithmetic on"), __mul = fail("do arithmetic on"),
	__div = fail("do arithmetic on"), __mod = fail("do arithmetic on"), __pow = fail("do arithmetic on"),
	__unm = fail("do arithmetic on"), __lt = fail("compare"), __le = fail("compare"), __eq = fail("compare"),
	__concat = function() return newSecret("concat") end,
	__tostring = function() return "<secret>" end,
}

local function issecretvalue(value) return secrets[value] ~= nil end

-- WoW additions to the standard library
table.wipe = table.wipe or function(t) for k in pairs(t) do t[k] = nil end return t end
string.trim = string.trim or function(s) return (string.gsub(s, "^%s*(.-)%s*$", "%1")) end

local realFormat, realTostring = string.format, tostring
local function anySecret(...)
	for i = 1, select("#", ...) do
		if( issecretvalue((select(i, ...))) ) then return true end
	end
	return false
end

-- string.format: the format itself must be plain; secret arguments give a secret string
string.format = function(fmt, ...)
	if( issecretvalue(fmt) ) then error("secret format string", 2) end
	if( anySecret(...) ) then
		-- still check the format against plain stand-ins so bad specifiers are caught
		local args = {...}
		for i = 1, select("#", ...) do
			if( issecretvalue(args[i]) ) then args[i] = 1 end
		end
		realFormat(fmt, unpack(args, 1, select("#", ...)))
		return newSecret("format")
	end
	return realFormat(fmt, ...)
end
tostring = function(value)
	if( issecretvalue(value) ) then return newSecret("tostring") end
	return realTostring(value)
end

---------------------------------------------------------------------------
-- Scenario driven WoW API stubs
---------------------------------------------------------------------------
local S -- current scenario
local secretMode = false
local function maybe(value)
	if( secretMode and value ~= nil ) then return newSecret() end
	return value
end
-- Secret even when nil (a secret wraps "no value" too, as far as we know)
local function maybeAlways(value)
	if( secretMode ) then return newSecret() end
	return value
end

local env = {}
setmetatable(env, {__index = _G})
env.issecretvalue = issecretvalue
env.string = string
env.tostring = tostring

local function curveEval(curve, fraction)
	if( secretMode ) then return newSecret("curve") end
	return curve:Eval(fraction)
end

local Curve = {}
Curve.__index = Curve
function Curve:SetType(kind) self.kind = kind end
function Curve:AddPoint(x, y) table.insert(self.points, {x, y}) end
function Curve:Eval(x)
	local pts = self.points
	if( self.kind == "Step" ) then
		local value = pts[1][2]
		for _, p in ipairs(pts) do if( x >= p[1] ) then value = p[2] end end
		return value
	end
	for i = 2, #pts do
		if( x <= pts[i][1] ) then
			local a, b = pts[i - 1], pts[i]
			return a[2] + (b[2] - a[2]) * (x - a[1]) / (b[1] - a[1])
		end
	end
	return pts[#pts][2]
end

env.Enum = {
	PowerType = {Mana = 0, Rage = 1, Focus = 2, Energy = 3, ComboPoints = 4},
	LuaCurveType = {Linear = "Linear", Step = "Step"},
}
env.C_CurveUtil = {CreateCurve = function() return setmetatable({points = {}}, Curve) end}
env.CurveConstants = nil
env.C_Secrets = {HasSecretRestrictions = function() return true end}
env.CreateColor = function(r, g, b, a) return {r = r, g = g, b = b, a = a} end
env.PowerBarColor = {MANA = {r = 0, g = 0, b = 1}, RAGE = {r = 1, g = 0, b = 0}, ENERGY = {r = 1, g = 1, b = 0}}
env.PowerBarColor[0] = env.PowerBarColor.MANA
env.PowerBarColor[1] = env.PowerBarColor.RAGE
env.PowerBarColor[3] = env.PowerBarColor.ENERGY
env.C_Spell = {GetSpellName = function(id) return "Spell" .. id end}
env.C_StringUtil = {
	AbbreviateNumbers = function(number, options)
		if( issecretvalue(number) ) then return newSecret("abbrev") end
		if( type(number) ~= "number" ) then error("number expected") end
		local data = options and options.breakpointData
		if( data ) then
			for _, point in ipairs(data) do
				if( number >= point.breakpoint ) then
					return realTostring(math.floor(number / point.significandDivisor) / point.fractionDivisor) .. point.abbreviation
				end
			end
		end
		return realTostring(number)
	end,
}
env.C_PetInfo = {GetPetHappiness = function() return maybe(S.happiness) end}
env.C_Timer = {NewTicker = function() return {Cancel = function() end} end}
env.geterrorhandler = function() return function(msg) env.lastError = msg end end
env.GetTime = function() return 1000 end
env.GetPVPTimer = function() return maybe(S.pvpTimer or 301000) end
env.GetThreatStatusColor = function(state)
	if( issecretvalue(state) ) then error("GetThreatStatusColor: secret argument") end
	return 1, 0.5, 0
end
env.GetQuestDifficultyColor = function(level)
	if( issecretvalue(level) ) then error("GetQuestDifficultyColor: secret argument") end
	return {r = 1, g = 1, b = 0}
end
env.GetComboPoints = function() return maybe(S.combo or 0) end
env.GetGuildInfo = function() return maybe(S.guild) end
env.GetNumGroupMembers = function() return S.groupSize or 0 end
env.GetRaidRosterInfo = function(i) return maybe("Member" .. i), nil, maybe(math.ceil(i / 5)) end
env.UNKNOWN = "Unknown"

local function pick(field, default) return function() local v = S[field] if v == nil then v = default end return v end end
env.UnitHealth = function() return maybe(S.health or 5000) end
env.UnitHealthMax = function() return maybe(S.maxHealth or 10000) end
env.UnitHealthMissing = function() return maybe((S.maxHealth or 10000) - (S.health or 5000)) end
env.UnitHealthPercent = function(unit, predicted, curve)
	local fraction = (S.health or 5000) / (S.maxHealth or 10000)
	if( curve ) then return curveEval(curve, fraction) end
	return maybe(fraction)
end
env.UnitPower = function(unit, powerType)
	if( powerType == 4 ) then return maybe(S.combo or 0) end
	return maybe(S.power or 50)
end
env.UnitPowerMax = function() return maybe(S.maxPower or 100) end
env.UnitPowerMissing = function() return maybe((S.maxPower or 100) - (S.power or 50)) end
env.UnitPowerPercent = function(unit, powerType, unmodified, curve)
	local max = S.maxPower or 100
	local fraction = max > 0 and (S.power or 50) / max or 0
	if( curve ) then return curveEval(curve, fraction) end
	return maybe(fraction)
end
env.UnitPowerType = function() return maybe(S.powerType or 0), maybe(S.powerToken or "MANA") end
env.UnitName = function() return maybe(S.name or "Somebody Longname Here"), maybe(S.server) end
env.UnitClass = function() return maybe(S.className or "Druid"), maybe(S.class or "DRUID"), maybe(11) end
env.UnitRace = function() return maybe("Night Elf"), maybe("NightElf") end
env.UnitSex = function() return maybe(S.sex or 2) end
env.UnitCreatureFamily = function() return maybeAlways(S.family) end
env.UnitCreatureType = function() return maybe(S.creatureType or "Beast") end
env.UnitGUID = function(unit) return maybe(S.guids and S.guids[unit] or "GUID-" .. unit) end
env.UnitInRaid = function() return maybe(S.inRaid) end
env.UnitThreatSituation = function() return maybe(S.threat or 2) end
env.UnitDetailedThreatSituation = function() return maybe(true), maybe(2), maybe(S.scaledThreat or 85), maybe(90), maybe(1000) end
env.UnitIsAFK = function() return maybe(S.afk or false) end
env.UnitIsDND = function() return maybe(S.dnd or false) end
env.UnitGetIncomingHeals = function() return maybe(S.incHeal or 0) end
env.UnitGetTotalAbsorbs = function() return maybe(S.absorb or 0) end
env.UnitGetTotalHealAbsorbs = function() return maybe(S.healAbsorb or 0) end
env.UnitLevel = function() return maybe(S.level or 60) end
env.UnitClassification = function() return maybe(S.classif or "normal") end
env.UnitReaction = function() return maybe(S.reaction or 4) end
env.UnitRealmRelationship = function() return maybe(S.realmRelation) end
env.UnitFactionGroup = function() return maybe("Alliance"), maybe("Alliance") end
env.UnitBattlePetLevel = function() return maybe(1) end
env.UnitIsDead = pick("dead", false)
env.UnitIsGhost = pick("ghost", false)
env.UnitIsDeadOrGhost = function() return S.dead or S.ghost or false end
env.UnitIsConnected = function() return not S.offline end
env.UnitIsPlayer = pick("player", true)
env.UnitIsFriend = pick("friend", true)
env.UnitCanAttack = pick("attackable", false)
env.UnitPlayerControlled = pick("player", true)
env.UnitIsWildBattlePet = function() return false end
env.UnitIsBattlePetCompanion = function() return false end

---------------------------------------------------------------------------
-- Load the addon pieces we need
---------------------------------------------------------------------------
local ShadowUF = {
	L = setmetatable({}, {__index = function(_, key) return key end}),
	db = {profile = {
		tags = {
			-- A custom tag that breaks on secrets: must not take the frame down
			["custom:bad"] = {func = [[function(unit) if( UnitHealth(unit) > 10 ) then return "big" end end]]},
			["custom:good"] = {func = [[function(unit) return "ok" end]]},
		},
		healthColors = {red = {r = 1, g = 0, b = 0}, yellow = {r = 1, g = 1, b = 0}, green = {r = 0, g = 1, b = 0},
			hostile = {r = 1, g = 0, b = 0}, friendly = {r = 0, g = 1, b = 0}, neutral = {r = 1, g = 1, b = 0}, enemyUnattack = {r = 0.5, g = 0, b = 0}},
		classColors = {DRUID = {r = 1, g = 0.49, b = 0.04}},
	}},
	playerUnit = "player",
	raidUnits = {}, modules = {},
	Units = {unitEvents = {}},
	noop = function() end,
}
for i = 1, 40 do ShadowUF.raidUnits[i] = "raid" .. i end
ShadowUF.unitTarget = setmetatable({}, {__index = function(tbl, unit) rawset(tbl, unit, unit .. "target") return unit .. "target" end})
ShadowUF.Units.ReadGUID = function(unit)
	local guid = env.UnitGUID(unit)
	if( issecretvalue(guid) ) then return nil, true end
	return guid, false
end
ShadowUF.UnitAuraBySpell = function(unit, spell)
	if( secretMode ) then return newSecret("aura") end
	if( S.forms and S.forms[spell] ) then return spell end
end
-- Same as health.lua: maths on plain values only
ShadowUF.modules.healthBar = {getGradientColor = function(unit)
	local max = env.UnitHealthMax(unit)
	local percent = env.UnitHealth(unit) / max
	return percent, percent, 0
end}
env.ShadowUF = ShadowUF

-- Same compiler as ShadowedUnitFrames.lua's tagFunc cache
ShadowUF.tagFunc = setmetatable({}, {
	__index = function(tbl, index)
		if( not ShadowUF.Tags.defaultTags[index] and not ShadowUF.db.profile.tags[index] ) then
			tbl[index] = false
			return false
		end

		local func, msg = loadstring("return " .. (ShadowUF.Tags.defaultTags[index] or ShadowUF.db.profile.tags[index].func or ""))
		if( func ) then
			setfenv(func, env)
			func = func()
		elseif( msg ) then
			error(msg, 3)
		end

		tbl[index] = func
		return tbl[index]
end})

local function loadInto(path)
	local chunk = assert(loadfile(path))
	setfenv(chunk, env)
	chunk("ShadowedUnitFrames", ShadowUF)
end
loadInto("ShadowedUnitFrames_Forever/modules/secrets.lua")
loadInto(os.getenv("TAGS_FILE") or "ShadowedUnitFrames_Forever/modules/tags.lua")
local Tags = ShadowUF.Tags

---------------------------------------------------------------------------
-- Fake frames and font strings
---------------------------------------------------------------------------
local function newFontString(parent)
	local fs = {parent = parent}
	function fs:SetFormattedText(fmt, ...)
		if( issecretvalue(fmt) ) then error("secret format") end
		self.text = string.format(fmt, ...)
	end
	function fs:SetText(text) self.text = text end
	function fs:SetAlpha(alpha) self.alpha = alpha end
	function fs:Show() end
	function fs:Hide() end
	parent.fontStrings[fs] = fs
	return fs
end

local function newFrame(unit)
	local frame = {unit = unit, unitOwner = unit, fontStrings = {}}
	local noop = function() end
	frame.RegisterUnitEvent, frame.RegisterNormalEvent, frame.RegisterUpdateFunc = noop, noop, noop
	frame.UnregisterAll, frame.UnregisterSingleEvent, frame.UnregisterUpdateFunc = noop, noop, noop
	return frame
end

local function show(value)
	if( issecretvalue(value) ) then return "<secret>" end
	return realTostring(value)
end

---------------------------------------------------------------------------
-- Scenarios
---------------------------------------------------------------------------
local scenarios = {
	{name = "full druid in cat form", health = 10000, maxHealth = 10000, power = 80, maxPower = 100, powerType = 3, forms = {Spell768 = true}, combo = 3},
	{name = "hurt npc elite", health = 1234, maxHealth = 123456789, player = false, classif = "rareelite", level = -1, family = "Wolf", attackable = true, friend = false, reaction = 2, maxPower = 0, power = 0, threat = 3},
	{name = "dead raid member", dead = true, inRaid = 3, groupSize = 10, server = "OtherRealm", guild = "Guild", afk = true, incHeal = 2500, absorb = 400, healAbsorb = 100, happiness = 2},
	{name = "offline ghost", offline = true, ghost = true, dnd = true, maxPower = 0, power = 0, sex = 3},
	{name = "boss", classif = "worldboss", level = -1, player = false, threat = 0, pvpTimer = 120000},
}

local names = {}
for name in pairs(Tags.defaultTags) do table.insert(names, name) end
for name in pairs(Tags.removedTags or {}) do table.insert(names, name) end
for name in pairs(Tags.tagAliases or {}) do table.insert(names, name) end
table.insert(names, "custom:bad")
table.insert(names, "custom:good")
table.sort(names)

local problems, runs = 0, 0
local function check(label, fn)
	runs = runs + 1
	local ok, err = pcall(fn)
	if( not ok ) then
		problems = problems + 1
		print("FAIL " .. label .. ": " .. realTostring(err))
	end
	return ok
end

for _, mode in ipairs({false, true}) do
	secretMode = mode
	for _, scenario in ipairs(scenarios) do
		S = scenario
		for _, name in ipairs(names) do
			-- Plain tag, with pre/append text, and next to another tag
			for _, text in ipairs({"[" .. name .. "]", "[(<)" .. name .. "(>)]", "[name] [" .. name .. "]"}) do
				local frame = newFrame(name == "pet:happiness" and "pet" or "target")
				local fs = newFontString(frame)
				fs.block = {endTime = maybe(1003.5)}
				local label = string.format("%s / %s / %s", mode and "secret" or "plain", scenario.name, text)
				check(label, function()
					env.lastError = nil
					Tags:Register(frame, fs, text, true)
					fs:UpdateTags()
					fs:UpdateTags(frame, "UNIT_POWER_FREQUENT", "target", maybe("MANA"))
					if( name == "custom:bad" and mode and not env.lastError ) then error("custom tag error wasn't reported") end
					if( verbose ) then print(label .. " => " .. show(fs.text) .. (fs.tagAlphaUsed and (" alpha " .. show(fs.alpha)) or "")) end
				end)
			end
		end
	end
end

-- Spot checks of plain output (must match the original SUF formats)
secretMode = false
local function expect(name, scenario, want)
	S = scenario
	local got = ShadowUF.tagFunc[name]("target", "target")
	runs = runs + 1
	if( got ~= want ) then
		problems = problems + 1
		print(string.format("FAIL [%s] gave %s, expected %s", name, realTostring(got), realTostring(want)))
	end
end
expect("curhp", {health = 11500}, "11.5k")
expect("curhp", {health = 999}, 999)
expect("curmaxhp", {health = 1234567, maxHealth = 2000000}, "1.23m/2.00m")
expect("perhp", {health = 61, maxHealth = 110}, "55%")
expect("dechp", {health = 61, maxHealth = 110}, "55.5%")
expect("missinghp", {health = 10000, maxHealth = 10000}, nil)
expect("missinghp", {health = 1500, maxHealth = 20000}, "-18.5k")
expect("perpp", {power = 33, maxPower = 100}, "33%")
expect("abbrev:name", {name = "Dark Rune Champion"}, "D.R.Champion")
expect("smartlevel", {classif = "elite", level = 50}, "50+")
expect("druid:curpp", {class = "DRUID", powerType = 1, power = 5000}, 5000)
expect("druid:curpp", {class = "DRUID", powerType = 0}, nil)
expect("cpoints", {combo = 4}, 4)
expect("group", {inRaid = 1, groupSize = 10, name = "Member7"}, 2)
expect("pet:happiness", {happiness = 3}, "Happy")
expect("short:druidform", {forms = {Spell5487 = true}}, "B")
expect("unit:raid:targeting", {groupSize = 5, guids = {target = "X", raid2target = "X", raid4target = "X"}}, 2)

-- Secret output checks: missinghp alone fades instead of showing -0
secretMode = true
S = {health = 10000, maxHealth = 10000}
do
	local frame = newFrame("target")
	local fs = newFontString(frame)
	Tags:Register(frame, fs, "[missinghp]", true)
	fs:UpdateTags()
	runs = runs + 1
	if( not fs.tagAlphaUsed or not issecretvalue(fs.alpha) ) then
		problems = problems + 1
		print("FAIL [missinghp] alone with secret health should set a secret alpha")
	end
	Tags:Register(frame, fs, "[name] [missinghp]", true)
	fs:UpdateTags()
	runs = runs + 1
	if( fs.tagAlphaUsed or fs.alpha ~= 1 ) then
		problems = problems + 1
		print("FAIL [missinghp] next to other text must not fade the font string")
	end
end

---------------------------------------------------------------------------
-- Static review: secrets must not be tested without issecretvalue() first.
-- Flags "x and"/"x or"/"if x" style uses of values that came from secret APIs on the
-- same line, unless the line also mentions issecretvalue/Plain.
---------------------------------------------------------------------------
local risky = 0
for _, name in ipairs(names) do
	local code = Tags.defaultTags[name]
	if( code ) then
		local n = 0
		for line in string.gmatch(code, "[^\n]+") do
			n = n + 1
			if( string.match(line, "Unit%w+%b()%s*or") or string.match(line, "Unit%w+%b()%s*[<>=~]") ) then
				if( not string.match(line, "issecretvalue") and not string.match(line, "Plain") and not string.match(line, "UnitIs") and not string.match(line, "UnitCanAttack") and not string.match(line, "UnitPlayerControlled") and not string.match(line, "UnitIsFriend") ) then
					risky = risky + 1
					print(string.format("REVIEW [%s] line %d: %s", name, n, line))
				end
			end
		end
	end
end

print(string.format("%d runs, %d failure(s), %d line(s) to review.", runs, problems, risky))
if( problems > 0 ) then os.exit(1) end
