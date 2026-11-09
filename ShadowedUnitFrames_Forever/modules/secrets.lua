--[[
	Secret value helpers for WoW Forever.

	In combat (and for some units outside it) the game hands addons "secret" values:
	health, power, aura data, cast info, names and so on. Addon code can store them and
	pass them to the widgets and APIs that accept them (StatusBar:SetMinMaxValues/SetValue,
	FontString:SetText/SetFormattedText, C_StringUtil.AbbreviateNumbers, curves, ...),
	but can't compare them, do maths with them, test them with "if", or use them as
	table keys. Doing any of those raises an error.

	Everything that reads a value that may be secret should go through these helpers, or
	only ever hand the value straight to something that accepts secrets.
]]

local Secrets = {}
ShadowUF.Secrets = Secrets

local issecretvalue = issecretvalue or function() return false end
local pcall, select, type = pcall, select, type

Secrets.IsSecret = issecretvalue

-- Does this client restrict addons with secret values at all?
Secrets.enabled = C_Secrets and C_Secrets.HasSecretRestrictions and C_Secrets.HasSecretRestrictions() or false

-- True if any of the arguments is secret
function Secrets.Any(...)
	for i = 1, select("#", ...) do
		if( issecretvalue((select(i, ...))) ) then return true end
	end
	return false
end

-- The value if it's a plain (non secret) value, otherwise the fallback
function Secrets.Plain(value, fallback)
	if( issecretvalue(value) ) then return fallback end
	return value
end

-- Calls fn(...) and returns its first result only if the call worked and the result isn't secret
function Secrets.Read(fn, ...)
	if( not fn ) then return nil end
	local ok, value = pcall(fn, ...)
	if( not ok or issecretvalue(value) ) then return nil end
	return value
end

-- Same as Read but keeps every return value; any secret one comes back as nil
function Secrets.ReadAll(fn, ...)
	if( not fn ) then return end
	local results = {pcall(fn, ...)}
	if( not results[1] ) then return end
	for i = 2, #results do
		if( issecretvalue(results[i]) ) then results[i] = nil end
	end
	return unpack(results, 2, table.maxn(results))
end

-- Curves the game evaluates for us, so a secret percent never has to be touched in Lua
local function createCurve(curveType, points)
	if( not C_CurveUtil or not C_CurveUtil.CreateCurve ) then return nil end
	local ok, curve = pcall(function()
		local c = C_CurveUtil.CreateCurve()
		if( curveType and Enum.LuaCurveType ) then c:SetType(Enum.LuaCurveType[curveType]) end
		for _, point in ipairs(points) do c:AddPoint(point[1], point[2]) end
		return c
	end)
	return ok and curve or nil
end
Secrets.CreateCurve = createCurve

-- A curve that is 0 below `threshold` (0-1) and 1 from it upwards; good for alpha
function Secrets.CreateStepCurve(threshold)
	return createCurve("Step", {{0, 0}, {threshold, 1}, {1, 1}})
end

-- points = {{x, r, g, b[, a]}, ...}, x from 0 to 1
function Secrets.CreateColorCurve(points)
	if( not C_CurveUtil or not C_CurveUtil.CreateColorCurve or not CreateColor ) then return nil end
	local ok, curve = pcall(function()
		local c = C_CurveUtil.CreateColorCurve()
		if( Enum.LuaCurveType ) then c:SetType(Enum.LuaCurveType.Linear) end
		for _, p in ipairs(points) do c:AddPoint(p[1], CreateColor(p[2], p[3], p[4], p[5] or 1)) end
		return c
	end)
	return ok and curve or nil
end

Secrets.ScaleTo100 = CurveConstants and CurveConstants.ScaleTo100 or createCurve("Linear", {{0, 0}, {1, 100}})
Secrets.ReverseTo100 = CurveConstants and CurveConstants.ReverseTo100 or createCurve("Linear", {{0, 100}, {1, 0}})
Secrets.ZeroToOne = CurveConstants and CurveConstants.ZeroToOne or createCurve("Linear", {{0, 0}, {1, 1}})

-- Health percent of the unit, 0-100 (may be secret). Uses the game's own maths.
function Secrets.HealthPercent(unit)
	if( UnitHealthPercent and Secrets.ScaleTo100 ) then
		local ok, value = pcall(UnitHealthPercent, unit, true, Secrets.ScaleTo100)
		if( ok and (issecretvalue(value) or value ~= nil) ) then return value end
	end

	local cur, max = UnitHealth(unit), UnitHealthMax(unit)
	if( issecretvalue(cur) or issecretvalue(max) ) then return nil end
	return max > 0 and (cur / max * 100) or 0
end

-- Power percent of the unit, 0-100 (may be secret)
function Secrets.PowerPercent(unit, powerType)
	if( UnitPowerPercent and Secrets.ScaleTo100 ) then
		local ok, value = pcall(UnitPowerPercent, unit, powerType, false, Secrets.ScaleTo100)
		if( ok and (issecretvalue(value) or value ~= nil) ) then return value end
	end

	local cur, max = UnitPower(unit, powerType), UnitPowerMax(unit, powerType)
	if( issecretvalue(cur) or issecretvalue(max) ) then return nil end
	return max > 0 and (cur / max * 100) or 0
end

-- Sets a status bar's range and value; both may be secret. Returns true if the bar
-- ended up on the real min/max scale (false means it fell back to 0-100 percent).
function Secrets.SetBar(bar, cur, max, percentFn)
	local ok = pcall(bar.SetMinMaxValues, bar, 0, max)
	ok = ok and pcall(bar.SetValue, bar, cur)
	if( not ok and percentFn ) then
		local pct = percentFn()
		if( issecretvalue(pct) or pct ~= nil ) then
			pcall(bar.SetMinMaxValues, bar, 0, 100)
			pcall(bar.SetValue, bar, pct)
		end
	end
	return ok
end

-- Short number text ("12.3K"); fine with secrets.
local abbreviate = (C_StringUtil and C_StringUtil.AbbreviateNumbers) or _G.AbbreviateNumbers
local abbreviateLarge = (C_StringUtil and C_StringUtil.AbbreviateLargeNumbers) or _G.AbbreviateLargeNumbers
local breakUp = (C_StringUtil and C_StringUtil.BreakUpLargeNumbers) or _G.BreakUpLargeNumbers
function Secrets.Abbreviate(value)
	if( abbreviate ) then
		local ok, text = pcall(abbreviate, value)
		if( ok ) then return text end
	end
	if( issecretvalue(value) ) then return value end
	return tostring(value)
end

function Secrets.AbbreviateLarge(value)
	if( abbreviateLarge ) then
		local ok, text = pcall(abbreviateLarge, value)
		if( ok ) then return text end
	end
	return Secrets.Abbreviate(value)
end

function Secrets.BreakUp(value)
	if( breakUp ) then
		local ok, text = pcall(breakUp, value)
		if( ok ) then return text end
	end
	if( issecretvalue(value) ) then return value end
	return tostring(value)
end

-- Safe "a == b" for values that may be secret: nil when it can't be told
function Secrets.Equals(a, b)
	if( issecretvalue(a) or issecretvalue(b) ) then return nil end
	return a == b
end

-- Truthiness of a value that may be a secret boolean: nil when it can't be told
function Secrets.Bool(value)
	if( issecretvalue(value) ) then return nil end
	return value and true or false
end

--[[
	Auras. On Forever the game doesn't hand addons secret aura data: reading an aura that is
	secret raises "Auras cannot be accessed when secret while tainted". So every read asks
	C_Secrets first and skips what it can't have (also wrapped in pcall in case it's wrong).
]]
local ShouldIndexBeSecret = C_Secrets and C_Secrets.ShouldUnitAuraIndexBeSecret
local ShouldInstanceBeSecret = C_Secrets and C_Secrets.ShouldUnitAuraInstanceBeSecret
local GetAuraDataByIndex = C_UnitAuras.GetAuraDataByIndex
local GetAuraDataByAuraInstanceID = C_UnitAuras.GetAuraDataByAuraInstanceID
local MAX_AURA_INDEX = 100

local function indexSecret(unit, index, filter)
	if( not ShouldIndexBeSecret ) then return false end
	local ok, secret = pcall(ShouldIndexBeSecret, unit, index, filter)
	return not ok or issecretvalue(secret) or secret == true
end

-- The first readable aura at or after index+1: returns auraData, itsIndex (nil when there are no more).
-- Use in loops as:  auraData, index = Secrets.NextAura(unit, index, filter)
function Secrets.NextAura(unit, index, filter)
	while( index < MAX_AURA_INDEX ) do
		index = index + 1
		if( not indexSecret(unit, index, filter) ) then
			local ok, auraData = pcall(GetAuraDataByIndex, unit, index, filter)
			if( not ok ) then
				-- unreadable after all; keep going
			elseif( not auraData ) then
				return nil, index
			elseif( not issecretvalue(auraData) ) then
				return auraData, index
			end
		end
	end
	return nil, index
end

-- A single aura by index, nil when it's missing or secret
function Secrets.AuraByIndex(unit, index, filter)
	if( indexSecret(unit, index, filter) ) then return nil end
	local ok, auraData = pcall(GetAuraDataByIndex, unit, index, filter)
	if( not ok or issecretvalue(auraData) ) then return nil end
	return auraData
end

-- An aura by its instance ID, nil when it's gone or secret
function Secrets.AuraByInstance(unit, auraInstanceID)
	if( not auraInstanceID or issecretvalue(auraInstanceID) ) then return nil end
	if( ShouldInstanceBeSecret ) then
		local ok, secret = pcall(ShouldInstanceBeSecret, unit, auraInstanceID)
		if( not ok or issecretvalue(secret) or secret == true ) then return nil end
	end
	local ok, auraData = pcall(GetAuraDataByAuraInstanceID, unit, auraInstanceID)
	if( not ok or issecretvalue(auraData) ) then return nil end
	return auraData
end
