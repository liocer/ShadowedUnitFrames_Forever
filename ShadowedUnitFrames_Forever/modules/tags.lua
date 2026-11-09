--[[
	Tag (text) system. Originally by Shadowed for Shadowed Unit Frames.

	WoW Forever port: tags have to cope with "secret" values (health, power, names and so on
	in combat). A secret can be passed along, concatenated and string.format'ed, but never
	compared, tested with if/and/or/not, used in maths or as a table key. Every default tag
	checks issecretvalue() before testing a value, and falls back to something sensible:
	usually the same text built by the game (C_StringUtil.AbbreviateNumbers,
	UnitHealthPercent with a curve, UnitHealthMissing, ...). See notes/tags.md.

	Rules the machinery follows:
	- a tag result is only tested after issecretvalue() says it's not secret;
	- custom (user written) tags run inside pcall, so one broken custom tag only blanks itself;
	- tag code calls the unit APIs itself (not through helpers here), so the movers' config
	  mode, which swaps the tag functions' environment for fake data, keeps working.
]]

local GetSpellName = C_Spell.GetSpellName
local issecretvalue = issecretvalue or function() return false end

local Tags = {afkStatus = {}, offlineStatus = {}, customEvents = {}, powerMap = {}, moduleKey = "tags"}
local tagPool, functionPool, temp, regFontStrings, powerMap = {}, {}, {}, {}, Tags.powerMap
local L = ShadowUF.L
local Secrets = ShadowUF.Secrets

ShadowUF.Tags = Tags

-- Map the numeric index to the string
local numerics = {}
for id, color in pairs(PowerBarColor) do
	if( type(id) == "number" ) then
		numerics[color] = id
	end
end

for id, color in pairs(PowerBarColor) do
	if( type(id) == "string" and numerics[color] ) then
		powerMap[numerics[color]] = id
		powerMap[id] = true
	end
end

-- Avoid having to do string.match on every event
local powerFilters = {["SUF_POWERTYPE:CURRENT"] = "CURRENT"}
for powerType in pairs(PowerBarColor) do
	if( type(powerType) == "string" ) then
		powerFilters["SUF_POWERTYPE:" .. powerType] = powerType
	end
end

-- Tags that existed in retail SUF but have nothing to show in WoW Forever. Saved texts that
-- still use them show nothing instead of "[tag-error]".
Tags.removedTags = {
	["rune:timer"] = true,
	["sshards"] = true,
	["hpower"] = true,
	["monk:chipoints"] = true,
	["monk:stagger"] = true,
	["monk:abs:stagger"] = true,
}

-- Retail tags that are the same thing as another tag here: mana is only ever a secondary
-- power for druids in Classic (no Insanity or Maelstrom), so [sec:*] is [druid:*].
Tags.tagAliases = {
	["sec:curpp"] = "druid:curpp",
	["sec:abscurpp"] = "druid:abscurpp",
	["sec:curmaxpp"] = "druid:curmaxpp",
	["sec:absolutepp"] = "druid:absolutepp",
}

-- Finds the function for a tag name. Custom tags are wrapped in pcall; removed tags get a
-- function that shows nothing; aliases point at the tag they stand for.
local protectedPool, reportedErrors = {}, {}
local function noTag() return nil end

local function protectTag(name, func)
	return function(...)
		local ok, result = pcall(func, ...)
		if( ok ) then return result end

		if( not reportedErrors[name] ) then
			reportedErrors[name] = true
			if( issecretvalue(result) ) then result = "secret value" end
			geterrorhandler()(string.format("Shadowed Unit Frames: custom tag [%s] failed: %s", name, tostring(result)))
		end
		return nil
	end
end

local function getTagFunc(name)
	local func = protectedPool[name]
	if( func ~= nil ) then return func end

	if( Tags.defaultTags[name] ) then
		func = ShadowUF.tagFunc[name]
	elseif( ShadowUF.db.profile.tags[name] ) then
		func = ShadowUF.tagFunc[name]
		if( func ) then func = protectTag(name, func) end
	elseif( Tags.tagAliases[name] ) then
		func = ShadowUF.tagFunc[Tags.tagAliases[name]]
	elseif( Tags.removedTags[name] ) then
		func = noTag
	end

	protectedPool[name] = func or false
	return func
end

local function getTagEvents(tag)
	local custom = ShadowUF.db.profile.tags[tag]
	return Tags.defaultEvents[tag] or custom and custom.events or Tags.tagAliases[tag] and Tags.defaultEvents[Tags.tagAliases[tag]]
end

local function getTagFrequency(tag)
	local custom = ShadowUF.db.profile.tags[tag]
	return Tags.defaultFrequents[tag] or custom and custom.frequency or Tags.tagAliases[tag] and Tags.defaultFrequents[Tags.tagAliases[tag]]
end

-- Register the associated events with all the tags
function Tags:RegisterEvents(parent, fontString, tags)
	local hasPowerFilters;
	-- Strip parantheses and anything inside them
	for tag in string.gmatch(tags, "%[(.-)%]") do
		-- The reason the original %b() match won't work, with [( ()group())] (or any sort of tag with ( or )
		-- was breaking the logic and stripping the entire tag, this is a quick fix to stop that.
		local tagKey = select(2, string.match(tag, "(%b())([%w%p]+)(%b())"))
		if( not tagKey ) then tagKey = select(2, string.match(tag, "(%b())([%w%p]+)")) end
		if( not tagKey ) then tagKey = string.match(tag, "([%w%p]+)(%b())") end

		tag = tagKey or tag

		local tagEvents = getTagEvents(tag)
		if( tagEvents ) then
			for event in string.gmatch(tagEvents, "%S+") do
				-- Power filter event, store it instead
				if( powerFilters[event] ) then
					fontString.powerFilters = fontString.powerFilters or {}
					fontString.powerFilters[powerFilters[event]] = true

					if( powerFilters[event] == "CURRENT" ) then
						if( not hasPowerFilters ) then
							parent:RegisterUnitEvent("UNIT_DISPLAYPOWER", self, "UpdatePowerType")
							parent:RegisterUpdateFunc(self, "UpdatePowerType")
						end

						hasPowerFilters = true
					end

				-- Custom event registered by another module
				elseif( self.customEvents[event] ) then
					self.customEvents[event]:EnableTag(parent, fontString)
					fontString[event] = true
				-- Unit event
				elseif( Tags.eventType[event] ~= "unitless" or ShadowUF.Units.unitEvents[event] ) then
					local success = pcall(parent.RegisterUnitEvent, parent, event, fontString, "UpdateTags")
					if not success then
						-- switch the tag back
						ShadowUF.Units.unitEvents[event] = false
						Tags.eventType[event] = "unitless"

						parent:RegisterNormalEvent(event, fontString, "UpdateTags")
					end
				-- Everything else
				else
					parent:RegisterNormalEvent(event, fontString, "UpdateTags")
				end

				-- register UNIT_MANA event since its the only event that fires after repopping at a spirit healer
				if event == "UNIT_POWER_UPDATE" or event == "UNIT_POWER_FREQUENT" then
					parent:RegisterUnitEvent("UNIT_MANA", fontString, "UpdateTags")

					if ( parent.unit == "player" ) then
						parent:RegisterNormalEvent("PLAYER_UNGHOST", fontString, "UpdateTags")
					end
				end
			end
		end
	end
end

-- Update the cached power type
function Tags:UpdatePowerType(frame)
	local powerID, powerType = UnitPowerType(frame.unit)
	if( issecretvalue(powerID) ) then powerID = nil end
	if( issecretvalue(powerType) ) then powerType = nil end
	if( not powerType or not powerMap[powerType] ) then powerType = powerID and powerMap[powerID] or "ENERGY" end

	for _, fontString in pairs(frame.fontStrings) do
		if( fontString.UpdateTags ) then
			fontString.powerType = powerType
			fontString:UpdateTags()
		end
	end
end

-- This pretty much means a tag was updated in some way (or deleted) so we have to do a full update to get the new values shown
function Tags:Reload()
	-- Kill cached functions, ugly I know but it ensures its fully updated with the new data
	table.wipe(functionPool)
	table.wipe(ShadowUF.tagFunc)
	table.wipe(tagPool)
	table.wipe(protectedPool)
	table.wipe(reportedErrors)

	-- Now update frames
	for fontString, tags in pairs(regFontStrings) do
		self:Register(fontString.parent, fontString, tags)
		fontString.parent:RegisterUpdateFunc(fontString, "UpdateTags")
		fontString:UpdateTags()
	end
end

-- This is for bars that can be shown or hidden often, like druid power
function Tags:FastRegister(frame, parent)
	if( not frame.fontStrings ) then return end

	for _, fontString in pairs(frame.fontStrings) do
		-- Re-register anything that was already registered and is part of the parent
		if( regFontStrings[fontString] and ( not parent or fontString.parentBar == parent ) ) then
			fontString.UpdateTags = tagPool[regFontStrings[fontString]]
			fontString:Show()
		end
	end
end

function Tags:FastUnregister(frame, parent)
	if( not frame.fontStrings ) then return end

	for _, fontString in pairs(frame.fontStrings) do
		-- Redirect the updates to not do anything and hide it
		if( regFontStrings[fontString] and ( not parent or fontString.parentBar == parent ) ) then
			fontString.UpdateTags = ShadowUF.noop
			fontString:Hide()
		end
	end
end

-- Tags may ask for the whole font string to fade out (for example [missinghp] at full health
-- when the health is secret and "is it full" can't be tested in Lua). That's only honoured
-- when the text is that one tag and nothing else, so it can never hide other text.
local function applyTagAlpha(fontString)
	if( fontString.tagAlphaSet ) then
		if( not pcall(fontString.SetAlpha, fontString, fontString.tagAlpha) ) then
			fontString:SetAlpha(1)
		end
		fontString.tagAlphaUsed = true
	elseif( fontString.tagAlphaUsed ) then
		fontString.tagAlphaUsed = nil
		fontString:SetAlpha(1)
	end

	fontString.tagAlpha = nil
	fontString.tagAlphaSet = nil
end

-- Register a font string with the tag system
local powerEvents = {["UNIT_POWER_UPDATE"] = true, ["UNIT_POWER_FREQUENT"] = true, ["UNIT_MAXPOWER"] = true}
local frequencyCache = {}
local function createTagFunction(tags, resetCache)
	if( tagPool[tags] and not resetCache ) then
		return tagPool[tags], frequencyCache[tags]
	end

	if( resetCache ) then
		table.wipe(protectedPool)
		table.wipe(reportedErrors)
	end

	-- Using .- prevents supporting tags such as [foo ([)]. Supporting that and having a single pattern
	local formattedText = string.gsub(string.gsub(tags, "%%", "%%%%"), "[[].-[]]", "%%s")
	formattedText = string.gsub(formattedText, "|", "||")
	formattedText = string.gsub(formattedText, "||c", "|c")
	formattedText = string.gsub(formattedText, "||r", "|r")

	local args = {}
	local lowestFrequency = 9999

	for tag in string.gmatch(tags, "%[(.-)%]") do
		-- Tags that use pre or appends "foo(|)" etc need special matching, which is what this will handle
		local cachedFunc = not resetCache and functionPool[tag] or getTagFunc(tag)
		if( not cachedFunc ) then
			local hasPre, hasAp = true, true
			local tagKey = select(2, string.match(tag, "(%b())([%w%p]+)(%b())"))
			if( not tagKey ) then hasPre, hasAp = true, false tagKey = select(2, string.match(tag, "(%b())([%w%p]+)")) end
			if( not tagKey ) then hasPre, hasAp = false, true tagKey = string.match(tag, "([%w%p]+)(%b())") end

			frequencyCache[tag] = tagKey and getTagFrequency(tagKey)

			local tagFunc = tagKey and getTagFunc(tagKey)
			if( tagFunc ) then
				local startOff, endOff = string.find(tag, tagKey, 1, true)
				local pre = hasPre and string.sub(tag, 2, startOff - 2)
				local ap = hasAp and string.sub(tag, endOff + 2, -2)

				-- The result may be secret: concatenating is fine, testing it isn't
				if( pre and ap ) then
					cachedFunc = function(...)
						local str = tagFunc(...)
						if( issecretvalue(str) or str ) then return pre .. str .. ap end
					end
				elseif( pre ) then
					cachedFunc = function(...)
						local str = tagFunc(...)
						if( issecretvalue(str) or str ) then return pre .. str end
					end
				elseif( ap ) then
					cachedFunc = function(...)
						local str = tagFunc(...)
						if( issecretvalue(str) or str ) then return str .. ap end
					end
				end

				functionPool[tag] = cachedFunc
			end
		else
			frequencyCache[tag] = getTagFrequency(tag)
		end


		-- Figure out the lowest frequency rate we update at
		if( frequencyCache[tag] ) then
			lowestFrequency = math.min(lowestFrequency, frequencyCache[tag])
		end

		-- It's an invalid tag, simply return the tag itself wrapped in brackets
		if( not cachedFunc ) then
			functionPool[tag] = functionPool[tag] or function() return string.format("[%s-error]", tag) end
			cachedFunc = functionPool[tag]
		end

		table.insert(args, cachedFunc)
	end

	-- Only one tag and nothing else (but spaces): that tag may fade the font string
	local soleTag = #args == 1 and string.match(formattedText, "^%s*%%s%s*$") and true or nil

	frequencyCache[tags] = lowestFrequency < 9999 and lowestFrequency or nil
	tagPool[tags] = function(fontString, frame, event, unit, powerType)
		-- we can only run on frames with units set
		if not fontString.parent.unit then
			return
		end

		if( event and powerEvents[event] and fontString.powerFilters and not issecretvalue(powerType) and powerType ) then
			if( not fontString.powerFilters[powerType] and ( not fontString.powerFilters.CURRENT or fontString.powerType ~= powerType ) ) then
				return
			end
		end

		fontString.tagSole = soleTag
		for id, func in pairs(args) do
			local value = func(fontString.parent.unit, fontString.parent.unitOwner, fontString)
			if( issecretvalue(value) ) then
				temp[id] = value
			elseif( value == nil or value == false ) then
				temp[id] = ""
			else
				temp[id] = value
			end
		end

		fontString:SetFormattedText(formattedText, unpack(temp))
		applyTagAlpha(fontString)
	end

	return tagPool[tags], frequencyCache[tags]
end

local function createMonitorTimer(fontString, frequency)
	if( not fontString.monitor or fontString.monitor.frequency ~= frequency ) then
		if fontString.monitor then
			fontString.monitor:Cancel()
		end
		fontString.monitor  = C_Timer.NewTicker(frequency, function() fontString:UpdateTags() end)
		fontString.monitor.frequency = frequency
	end
end

local function cancelMonitorTimer(fontString)
	if( fontString.monitor ) then
		fontString.monitor:Cancel()
		fontString.monitor = nil
	end
end

function Tags:Register(parent, fontString, tags, resetCache)
	-- Unregister the font string first if we did register it already
	if( fontString.UpdateTags ) then
		self:Unregister(fontString)
	end

	fontString.parent = parent
	regFontStrings[fontString] = tags

	-- And give other frames an easy way to force an update
	local frequency
	fontString.UpdateTags, frequency = createTagFunction(tags, resetCache)

	if( frequency ) then
		createMonitorTimer(fontString, frequency)
	elseif( fontString.monitor ) then
		cancelMonitorTimer(fontString)
	end

	-- Register any needed event
	self:RegisterEvents(parent, fontString, tags)
end

function Tags:Unregister(fontString)
	regFontStrings[fontString] = nil

	-- Unregister it as using HC
	for key, module in pairs(self.customEvents) do
		if( fontString[key] ) then
			fontString[key] = nil
			module:DisableTag(fontString.parent, fontString)
		end
	end

	-- Kill any tag data
	cancelMonitorTimer(fontString)
	fontString.parent:UnregisterAll(fontString)
	fontString.powerFilters = nil
	fontString.UpdateTags = nil
	fontString:SetText("")
	if( fontString.tagAlphaUsed ) then
		fontString.tagAlphaUsed = nil
		fontString:SetAlpha(1)
	end

	-- See if we need to unregister events
	local parent = fontString.parent
	local hasPowerFilter
	for _, f in pairs(parent.fontStrings) do
		if( f.powerFilters and f.powerFilters.CURRENT ) then
			hasPowerFilter = true
			break
		end
	end

	if( not hasPowerFilter ) then
		parent:UnregisterSingleEvent("UNIT_DISPLAYPOWER", self)
		parent:UnregisterUpdateFunc(self, "UpdatePowerType")
	end
end

--[[
	Secret-safe helpers for tag code. Exposed so custom tags can use them too:
	ShadowUF.Tags.Plain(v)         v, or nil if v is secret
	ShadowUF.Tags.Abs(v)           v as an absolute number; secret numbers become a (secret) "%d" string
	ShadowUF:FormatLargeNumber(v)  11.5k style; secret numbers go through C_StringUtil.AbbreviateNumbers
	ShadowUF:SmartFormatNumber(v)  same, but only abbreviates millions
	ShadowUF.Tags.HealthPercentText(unit, fmt) / PowerPercentText(unit, fmt[, powerType])
	                               string.format(fmt, percent 0-100) using the game's own maths
	ShadowUF.Tags.FadeText(fontString, alpha)  fade a single-tag text (alpha may be secret)
]]
Tags.IsSecret = issecretvalue

function Tags.Plain(value)
	if( issecretvalue(value) ) then return nil end
	return value
end

function Tags.Abs(value)
	if( issecretvalue(value) ) then
		local ok, text = pcall(string.format, "%d", value)
		if( ok ) then return text end
	end
	return value
end

-- C_StringUtil.AbbreviateNumbers takes secrets. Give it breakpoints that copy SUF's own
-- formats (9999, 11.5k, 1.25m, 150m), and only use them if a test with plain numbers comes
-- out right; otherwise the game's default abbreviation is used.
local abbreviateNumbers = C_StringUtil and C_StringUtil.AbbreviateNumbers or _G.AbbreviateNumbers
local function buildAbbreviation(breakpoints, checks)
	if( not abbreviateNumbers ) then return nil end

	local data = {}
	for _, point in ipairs(breakpoints) do
		table.insert(data, {breakpoint = point[1], abbreviation = point[2], significandDivisor = point[3], fractionDivisor = point[4], abbreviationIsGlobal = false})
	end

	local options = {breakpointData = data}
	if( C_StringUtil and C_StringUtil.CreateAbbreviateConfig ) then
		local ok, config = pcall(C_StringUtil.CreateAbbreviateConfig, data)
		if( ok and config ) then options = {config = config} end
	end

	for number, pattern in pairs(checks) do
		local ok, text = pcall(abbreviateNumbers, number, options)
		if( not ok or type(text) ~= "string" or not string.match(text, pattern) ) then return nil end
	end

	return options
end

local largeNumberOptions = buildAbbreviation(
	{{100000000, "m", 1000000, 1}, {1000000, "m", 10000, 100}, {10000, "k", 100, 10}},
	{[1234] = "^1234$", [12345] = "^12%.3k$", [1234567] = "^1%.23m$", [123456789] = "^123m$"})
local smartNumberOptions = buildAbbreviation(
	{{100000000, "m", 1000000, 1}, {1000000, "m", 10000, 100}},
	{[123456] = "^123456$", [1234567] = "^1%.23m$", [123456789] = "^123m$"})

local function abbreviateSecret(number, options)
	if( abbreviateNumbers ) then
		local ok, text = pcall(abbreviateNumbers, number, options)
		if( ok ) then return text end

		ok, text = pcall(abbreviateNumbers, number)
		if( ok ) then return text end
	end

	return Tags.Abs(number)
end

-- The game's own percent maths; the result may be secret, nil when it can't be had
local scaleTo100 = Secrets and Secrets.ScaleTo100
function Tags.HealthPercentText(unit, fmt)
	if( not UnitHealthPercent or not scaleTo100 ) then return nil end
	local ok, percent = pcall(UnitHealthPercent, unit, true, scaleTo100)
	if( not ok or ( not issecretvalue(percent) and not percent ) ) then return nil end
	return string.format(fmt, percent)
end

function Tags.PowerPercentText(unit, fmt, powerType)
	if( not UnitPowerPercent or not scaleTo100 ) then return nil end
	local ok, percent = pcall(UnitPowerPercent, unit, powerType, false, scaleTo100)
	if( not ok or ( not issecretvalue(percent) and not percent ) ) then return nil end
	return string.format(fmt, percent)
end

-- 1 while the unit is missing health (or power), 0 when it's full, as a secret if need be.
-- Feeds Tags.FadeText so [missinghp] can still vanish at full health in combat.
local notFullCurve = Secrets and Secrets.CreateCurve and Secrets.CreateCurve("Step", {{0, 1}, {1, 0}})
function Tags.HealthNotFull(unit)
	if( not notFullCurve or not UnitHealthPercent ) then return nil end
	local ok, alpha = pcall(UnitHealthPercent, unit, true, notFullCurve)
	if( ok ) then return alpha end
end

function Tags.PowerNotFull(unit, powerType)
	if( not notFullCurve or not UnitPowerPercent ) then return nil end
	local ok, alpha = pcall(UnitPowerPercent, unit, powerType, false, notFullCurve)
	if( ok ) then return alpha end
end

function Tags.FadeText(fontString, alpha)
	if( not fontString or not fontString.tagSole ) then return end
	if( not issecretvalue(alpha) and alpha == nil ) then return end
	fontString.tagAlpha = alpha
	fontString.tagAlphaSet = true
end

-- [hp:color] when health is secret: one curve per colour channel (0-255) over the health
-- fraction, red -> yellow -> green like the health bar's gradient. Rebuilt when the colours change.
local gradientCurves, gradientColors = {}, {}
function Tags.HealthGradientHex(unit)
	if( not UnitHealthPercent or not Secrets or not Secrets.CreateCurve ) then return nil end

	local colors = ShadowUF.db.profile.healthColors
	local red, yellow, green = colors.red, colors.yellow, colors.green
	local changed
	for i, value in ipairs({red.r, red.g, red.b, yellow.r, yellow.g, yellow.b, green.r, green.g, green.b}) do
		if( gradientColors[i] ~= value ) then
			gradientColors[i] = value
			changed = true
		end
	end

	if( changed ) then
		for i, key in ipairs({"r", "g", "b"}) do
			gradientCurves[i] = Secrets.CreateCurve("Linear", {{0, red[key] * 255}, {0.5, yellow[key] * 255}, {1, green[key] * 255}})
		end
	end

	if( not gradientCurves[1] or not gradientCurves[2] or not gradientCurves[3] ) then return nil end
	local ok, text = pcall(function()
		return string.format("|cff%02x%02x%02x", UnitHealthPercent(unit, true, gradientCurves[1]), UnitHealthPercent(unit, true, gradientCurves[2]), UnitHealthPercent(unit, true, gradientCurves[3]))
	end)
	if( ok ) then return text end
end

-- true/false if the unit has the aura, nil if that can't be told (secret aura data)
function Tags.HasAura(unit, spell)
	if( not spell ) then return false end
	local ok, name = pcall(ShadowUF.UnitAuraBySpell, unit, spell)
	if( not ok or issecretvalue(name) ) then return nil end
	return name ~= nil
end

-- Helper functions for tags, the reason I store it in ShadowUF is it's easier to type ShadowUF than ShadowUF.modules.Tags, and simpler for users who want to implement it.
function ShadowUF:Hex(r, g, b)
	if( type(r) == "table" ) then
		if( r.r ) then
			r, g, b = r.r, r.g, r.b
		else
			r, g, b = unpack(r)
		end
	end

	-- A secret colour can't be turned into a colour code
	if( issecretvalue(r) or issecretvalue(g) or issecretvalue(b) or not r ) then return nil end

	return string.format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)
end

function ShadowUF:FormatLargeNumber(number)
	if( issecretvalue(number) ) then
		return abbreviateSecret(number, largeNumberOptions)
	elseif( number < 9999 ) then
		return number
	elseif( number < 999999 ) then
		return string.format("%.1fk", number / 1000)
	elseif( number < 99999999 ) then
		return string.format("%.2fm", number / 1000000)
	end

	return string.format("%dm", number / 1000000)
end

function ShadowUF:SmartFormatNumber(number)
	if( issecretvalue(number) ) then
		return abbreviateSecret(number, smartNumberOptions)
	elseif( number < 999999 ) then
		return number
	elseif( number < 99999999 ) then
		return string.format("%.2fm", number / 1000000)
	end

	return string.format("%dm", number / 1000000)
end

function ShadowUF:GetClassColor(unit)
	if( not UnitIsPlayer(unit) ) then
		return nil
	end

	-- The class is secret for some players (identity restricted); no colour then
	local class = select(2, UnitClass(unit))
	if( issecretvalue(class) or not class or not ShadowUF.db.profile.classColors[class] ) then return nil end
	return ShadowUF:Hex(ShadowUF.db.profile.classColors[class])
end

function ShadowUF:FormatShortTime(seconds)
	if( seconds >= 3600 ) then
		return string.format("%dh", seconds / 3600)
	elseif( seconds >= 60 ) then
		return string.format("%dm", seconds / 60)
	end

	return string.format("%ds", seconds)
end

-- Name abbreviation. Only ever called with plain names (secret ones are shown as they are).
local function abbreviateName(text)
	return (string.utf8sub or string.sub)(text, 1, 1) .. "."
end

Tags.abbrevCache = setmetatable({}, {
	__index = function(tbl, name)
		local abbreviated = string.gsub(name, "([^%s]+) ", abbreviateName)
		rawset(tbl, name, abbreviated)
		return abbreviated
end})

-- Going to have to start using an env wrapper for tags I think
local Druid = {}
Druid.CatForm = GetSpellName(768)
Druid.MoonkinForm = GetSpellName(24858)
Druid.TravelForm = GetSpellName(783)
Druid.BearForm = GetSpellName(5487)
Druid.DireBearForm = GetSpellName(9634)
Druid.TreeForm = GetSpellName(33891)
Druid.AquaticForm = GetSpellName(1066)
Druid.SwiftFlightForm = GetSpellName(40120)
Druid.FlightForm = GetSpellName(33943)
ShadowUF.Druid = Druid

-- Which form a druid is in: "Cat", "Bear", ... or nil (not a druid, no form, or can't be told)
local druidForms = {
	{"Cat", "CatForm"}, {"Tree", "TreeForm"}, {"Moonkin", "MoonkinForm"}, {"Bear", "BearForm"}, {"Bear", "DireBearForm"},
	{"Flight", "SwiftFlightForm"}, {"Flight", "FlightForm"}, {"Travel", "TravelForm"}, {"Aquatic", "AquaticForm"},
}
Tags.druidFormShort = {Cat = "C", Tree = "T", Moonkin = "M", Bear = "B", Flight = "F", Travel = "T", Aquatic = "A"}
function Tags.DruidForm(unit)
	if( Tags.Plain((select(2, UnitClass(unit)))) ~= "DRUID" ) then return nil end

	for _, form in ipairs(druidForms) do
		if( Tags.HasAura(unit, Druid[form[2]]) ) then
			return form[1]
		end
	end
end

--[[
	Default tags. Each one is Lua source compiled with loadstring and called as
	func(unit, unitOwner, fontString). Anything that may be secret is checked with
	issecretvalue() before it's compared or tested (see the file header).
]]
Tags.defaultTags = {
	["totem:timer"] = [[function(unit, unitOwner, fontString)
		local endTime = fontString.block and fontString.block.endTime
		if( issecretvalue(endTime) or not endTime ) then return nil end
		return string.format("%.1f", endTime - GetTime())
	end]],
	["hp:color"] = [[function(unit, unitOwner)
		local cur, max = UnitHealth(unit), UnitHealthMax(unit)
		if( issecretvalue(cur) or issecretvalue(max) ) then
			return ShadowUF.Tags.HealthGradientHex(unit)
		end

		return ShadowUF:Hex(ShadowUF.modules.healthBar.getGradientColor(unit))
	end]],
	["short:druidform"] = [[function(unit, unitOwner)
		local form = ShadowUF.Tags.DruidForm(unit)
		local short = form and ShadowUF.Tags.druidFormShort[form]
		return short and ShadowUF.L[short]
	end]],
	["druidform"] = [[function(unit, unitOwner)
		local form = ShadowUF.Tags.DruidForm(unit)
		return form and ShadowUF.L[form]
	end]],
	["guild"] = [[function(unit, unitOwner)
		return (GetGuildInfo(unitOwner))
	end]],
	["abbrev:name"] = [[function(unit, unitOwner)
		local name = UnitName(unitOwner)
		if( issecretvalue(name) ) then return name end

		name = name or _G.UNKNOWN or ShadowUF.L["Unknown"]
		return string.len(name) > 10 and ShadowUF.Tags.abbrevCache[name] or name
	end]],
	["unit:situation"] = [[function(unit, unitOwner)
		local state = ShadowUF.Tags.Plain(UnitThreatSituation(unit))
		if( state == 3 ) then
			return ShadowUF.L["Aggro"]
		elseif( state == 2 ) then
			return ShadowUF.L["High"]
		elseif( state == 1 ) then
			return ShadowUF.L["Medium"]
		end
	end]],
	["situation"] = [[function(unit, unitOwner)
		local state = ShadowUF.Tags.Plain(UnitThreatSituation("player", "target"))
		if( state == 3 ) then
			return ShadowUF.L["Aggro"]
		elseif( state == 2 ) then
			return ShadowUF.L["High"]
		elseif( state == 1 ) then
			return ShadowUF.L["Medium"]
		end
	end]],
	["unit:color:sit"] = [[function(unit, unitOwner)
		local state = ShadowUF.Tags.Plain(UnitThreatSituation(unit))

		return state and state > 0 and ShadowUF:Hex(GetThreatStatusColor(state))
	end]],
	["unit:color:aggro"] = [[function(unit, unitOwner)
		local state = ShadowUF.Tags.Plain(UnitThreatSituation(unit))

		return state and state >= 3 and ShadowUF:Hex(GetThreatStatusColor(state))
	end]],
	["color:sit"] = [[function(unit, unitOwner)
		local state = ShadowUF.Tags.Plain(UnitThreatSituation("player", "target"))

		return state and state > 0 and ShadowUF:Hex(GetThreatStatusColor(state))
	end]],
	["color:aggro"] = [[function(unit, unitOwner)
		local state = ShadowUF.Tags.Plain(UnitThreatSituation("player", "target"))

		return state and state >= 3 and ShadowUF:Hex(GetThreatStatusColor(state))
	end]],
	["scaled:threat"] = [[function(unit, unitOwner)
		local scaled = select(3, UnitDetailedThreatSituation("player", "target"))
		if( issecretvalue(scaled) ) then return string.format("%d%%", scaled) end
		return scaled and string.format("%d%%", scaled)
	end]],
	["general:sit"] = [[function(unit, unitOwner)
		local state = ShadowUF.Tags.Plain(UnitThreatSituation("player"))
		if( state == 3 ) then
			return ShadowUF.L["Aggro"]
		elseif( state == 2 ) then
			return ShadowUF.L["High"]
		elseif( state == 1 ) then
			return ShadowUF.L["Medium"]
		end
	end]],
	["color:gensit"] = [[function(unit, unitOwner)
		local state = ShadowUF.Tags.Plain(UnitThreatSituation("player"))

		return state and state > 0 and ShadowUF:Hex(GetThreatStatusColor(state))
	end]],
	["status:time"] = [[function(unit, unitOwner)
		local offlineStatus = ShadowUF.Tags.offlineStatus
		if( not UnitIsConnected(unitOwner) ) then
			offlineStatus[unitOwner] = offlineStatus[unitOwner] or GetTime()
			return string.format(ShadowUF.L["Off:%s"], ShadowUF:FormatShortTime(GetTime() - offlineStatus[unitOwner]))
		end

		offlineStatus[unitOwner] = nil
	end]],
	["afk:time"] = [[function(unit, unitOwner)
		if( not UnitIsConnected(unitOwner) ) then return end

		-- Away flags are secret during chat lockdown; keep the timer as it was
		local afk, dnd = UnitIsAFK(unitOwner), UnitIsDND(unitOwner)
		if( issecretvalue(afk) or issecretvalue(dnd) ) then return nil end

		local afkStatus = ShadowUF.Tags.afkStatus
		local status = afk and ShadowUF.L["AFK:%s"] or dnd and ShadowUF.L["DND:%s"]
		if( status ) then
			afkStatus[unitOwner] = afkStatus[unitOwner] or GetTime()
			return string.format(status, ShadowUF:FormatShortTime(GetTime() - afkStatus[unitOwner]))
		end

		afkStatus[unitOwner] = nil
	end]],
	["pvp:time"] = [[function(unit, unitOwner)
		local timer = ShadowUF.Tags.Plain(GetPVPTimer())
		if( not timer or timer >= 300000 ) then
			return nil
		end

		return string.format(ShadowUF.L["PVP:%s"], ShadowUF:FormatShortTime(timer / 1000))
	end]],
	["afk"] = [[function(unit, unitOwner, fontString)
		local afk, dnd = UnitIsAFK(unitOwner), UnitIsDND(unitOwner)
		if( issecretvalue(afk) or issecretvalue(dnd) ) then return nil end
		return afk and ShadowUF.L["AFK"] or dnd and ShadowUF.L["DND"]
	end]],
	["close"] = [[function(unit, unitOwner) return "|r" end]],
	["smartrace"] = [[function(unit, unitOwner)
		if( UnitIsPlayer(unit) ) then
			return ShadowUF.tagFunc.race(unit)
		end

		return ShadowUF.tagFunc.creature(unit)
	end]],
	["reactcolor"] = [[function(unit, unitOwner)
		local color
		if( not UnitIsFriend(unit, "player") and UnitPlayerControlled(unit) ) then
			if( UnitCanAttack("player", unit) ) then
				color = ShadowUF.db.profile.healthColors.hostile
			else
				color = ShadowUF.db.profile.healthColors.enemyUnattack
			end
		else
			local reaction = ShadowUF.Tags.Plain(UnitReaction(unit, "player"))
			if( not reaction ) then
				color = nil
			elseif( reaction > 4 ) then
				color = ShadowUF.db.profile.healthColors.friendly
			elseif( reaction == 4 ) then
				color = ShadowUF.db.profile.healthColors.neutral
			elseif( reaction < 4 ) then
				color = ShadowUF.db.profile.healthColors.hostile
			end
		end

		return color and ShadowUF:Hex(color)
	end]],
	["class"] = [[function(unit, unitOwner)
		if( not UnitIsPlayer(unit) ) then return nil end
		return (UnitClass(unit))
	end]],
	["classcolor"] = [[function(unit, unitOwner) return ShadowUF:GetClassColor(unit) end]],
	["creature"] = [[function(unit, unitOwner)
		local family = UnitCreatureFamily(unit)
		if( issecretvalue(family) or family ) then return family end
		return (UnitCreatureType(unit))
	end]],
	["curhp"] = [[function(unit, unitOwner)
		if( UnitIsDead(unit) ) then
			return ShadowUF.L["Dead"]
		elseif( UnitIsGhost(unit) ) then
			return ShadowUF.L["Ghost"]
		elseif( not UnitIsConnected(unit) ) then
			return ShadowUF.L["Offline"]
		end

		return ShadowUF:FormatLargeNumber(UnitHealth(unit))
	end]],
	["colorname"] = [[function(unit, unitOwner)
		local color = ShadowUF:GetClassColor(unitOwner)
		local name = UnitName(unitOwner)
		if( not issecretvalue(name) and not name ) then name = _G.UNKNOWN or ShadowUF.L["Unknown"] end
		if( not color ) then
			return name
		end

		return string.format("%s%s|r", color, name)
	end]],
	["curpp"] = [[function(unit, unitOwner)
		local maxPower = UnitPowerMax(unit)
		if( not issecretvalue(maxPower) and maxPower <= 0 ) then
			return nil
		elseif( UnitIsDeadOrGhost(unit) ) then
			return 0
		end

		return ShadowUF:FormatLargeNumber(UnitPower(unit))
	end]],
	["curmaxhp"] = [[function(unit, unitOwner)
		if( UnitIsDead(unit) ) then
			return ShadowUF.L["Dead"]
		elseif( UnitIsGhost(unit) ) then
			return ShadowUF.L["Ghost"]
		elseif( not UnitIsConnected(unit) ) then
			return ShadowUF.L["Offline"]
		end

		return string.format("%s/%s", ShadowUF:FormatLargeNumber(UnitHealth(unit)), ShadowUF:FormatLargeNumber(UnitHealthMax(unit)))
	end]],
	["smart:curmaxhp"] = [[function(unit, unitOwner)
		if( UnitIsDead(unit) ) then
			return ShadowUF.L["Dead"]
		elseif( UnitIsGhost(unit) ) then
			return ShadowUF.L["Ghost"]
		elseif( not UnitIsConnected(unit) ) then
			return ShadowUF.L["Offline"]
		end

		return string.format("%s/%s", ShadowUF:SmartFormatNumber(UnitHealth(unit)), ShadowUF:SmartFormatNumber(UnitHealthMax(unit)))
	end]],
	["absolutehp"] = [[function(unit, unitOwner)
		if( UnitIsDead(unit) ) then
			return ShadowUF.L["Dead"]
		elseif( UnitIsGhost(unit) ) then
			return ShadowUF.L["Ghost"]
		elseif( not UnitIsConnected(unit) ) then
			return ShadowUF.L["Offline"]
		end

		return string.format("%s/%s", ShadowUF.Tags.Abs(UnitHealth(unit)), ShadowUF.Tags.Abs(UnitHealthMax(unit)))
	end]],
	["abscurhp"] = [[function(unit, unitOwner)
		if( UnitIsDead(unit) ) then
			return ShadowUF.L["Dead"]
		elseif( UnitIsGhost(unit) ) then
			return ShadowUF.L["Ghost"]
		elseif( not UnitIsConnected(unit) ) then
			return ShadowUF.L["Offline"]
		end

		return ShadowUF.Tags.Abs(UnitHealth(unit))
	end]],
	["absmaxhp"] = [[function(unit, unitOwner) return ShadowUF.Tags.Abs(UnitHealthMax(unit)) end]],
	["abscurpp"] = [[function(unit, unitOwner)
		local maxPower = UnitPowerMax(unit)
		if( not issecretvalue(maxPower) and maxPower <= 0 ) then
			return nil
		elseif( UnitIsDeadOrGhost(unit) ) then
			return 0
		end

		return ShadowUF.Tags.Abs(UnitPower(unit))
	end]],
	["absmaxpp"] = [[function(unit, unitOwner)
		local power = UnitPowerMax(unit)
		if( issecretvalue(power) ) then return ShadowUF.Tags.Abs(power) end
		return power > 0 and power or nil
	end]],
	["absolutepp"] = [[function(unit, unitOwner)
		local maxPower = ShadowUF.Tags.Abs(UnitPowerMax(unit))
		local power = ShadowUF.Tags.Abs(UnitPower(unit))
		if( UnitIsDeadOrGhost(unit) ) then
			return string.format("0/%s", maxPower)
		elseif( not issecretvalue(maxPower) and maxPower <= 0 ) then
			return nil
		end

		return string.format("%s/%s", power, maxPower)
	end]],
	["curmaxpp"] = [[function(unit, unitOwner)
		local maxPower = UnitPowerMax(unit)
		local power = UnitPower(unit)
		if( UnitIsDeadOrGhost(unit) ) then
			return string.format("0/%s", ShadowUF:FormatLargeNumber(maxPower))
		elseif( not issecretvalue(maxPower) and maxPower <= 0 ) then
			return nil
		end

		return string.format("%s/%s", ShadowUF:FormatLargeNumber(power), ShadowUF:FormatLargeNumber(maxPower))
	end]],
	["smart:curmaxpp"] = [[function(unit, unitOwner)
		local maxPower = UnitPowerMax(unit)
		local power = UnitPower(unit)
		if( UnitIsDeadOrGhost(unit) ) then
			return string.format("0/%s", ShadowUF.Tags.Abs(maxPower))
		elseif( not issecretvalue(maxPower) and maxPower <= 0 ) then
			return nil
		end

		return string.format("%s/%s", ShadowUF:SmartFormatNumber(power), ShadowUF:SmartFormatNumber(maxPower))
	end]],
	["levelcolor"] = [[function(unit, unitOwner)
		if( UnitIsWildBattlePet(unit) or UnitIsBattlePetCompanion(unit) ) then
			return nil
		end

		local level = UnitLevel(unit)
		if( issecretvalue(level) ) then return ShadowUF.Tags.Abs(level) end

		level = level or 0
		if( level < 0 and ShadowUF.Tags.Plain(UnitClassification(unit)) == "worldboss" ) then
			return nil
		end

		if( UnitCanAttack("player", unit) ) then
			local color = ShadowUF:Hex(GetQuestDifficultyColor(level > 0 and level or 99))
			if( not color ) then
				return level > 0 and level or "??"
			end

			return color .. (level > 0 and level or "??") .. "|r"
		else
			return level > 0 and level or "??"
		end
	end]],
	["faction"] = [[function(unit, unitOwner) return (UnitFactionGroup(unitOwner)) end]],
	["level"] = [[function(unit, unitOwner)
		if( UnitIsWildBattlePet(unit) or UnitIsBattlePetCompanion(unit) ) then
			return ShadowUF.Tags.Abs(UnitBattlePetLevel(unit))
		end

		local level = UnitLevel(unit)
		if( issecretvalue(level) ) then return ShadowUF.Tags.Abs(level) end

		level = level or 0
		return level > 0 and level or ShadowUF.Tags.Plain(UnitClassification(unit)) ~= "worldboss" and "??" or nil
	end]],
	["maxhp"] = [[function(unit, unitOwner) return ShadowUF:FormatLargeNumber(UnitHealthMax(unit)) end]],
	["maxpp"] = [[function(unit, unitOwner)
		local power = UnitPowerMax(unit)
		if( not issecretvalue(power) and power <= 0 ) then
			return nil
		elseif( UnitIsDeadOrGhost(unit) ) then
			return 0
		end

		return ShadowUF:FormatLargeNumber(power)
	end]],
	["missinghp"] = [[function(unit, unitOwner, fontString)
		if( UnitIsDead(unit) ) then
			return ShadowUF.L["Dead"]
		elseif( UnitIsGhost(unit) ) then
			return ShadowUF.L["Ghost"]
		elseif( not UnitIsConnected(unit) ) then
			return ShadowUF.L["Offline"]
		end

		local cur, max = UnitHealth(unit), UnitHealthMax(unit)
		if( issecretvalue(cur) or issecretvalue(max) ) then
			-- "Is anything missing" can't be tested; the text fades out at full health instead
			-- when it's the only tag in the text, otherwise it shows -0
			if( not UnitHealthMissing ) then return nil end
			ShadowUF.Tags.FadeText(fontString, ShadowUF.Tags.HealthNotFull(unit))
			return "-" .. ShadowUF:FormatLargeNumber(UnitHealthMissing(unit))
		end

		local missing = max - cur
		if( missing <= 0 ) then return nil end
		return "-" .. ShadowUF:FormatLargeNumber(missing)
	end]],
	["missingpp"] = [[function(unit, unitOwner, fontString)
		local power = UnitPowerMax(unit)
		local cur = UnitPower(unit)
		if( issecretvalue(power) or issecretvalue(cur) ) then
			if( not UnitPowerMissing ) then return nil end
			ShadowUF.Tags.FadeText(fontString, ShadowUF.Tags.PowerNotFull(unit))
			return "-" .. ShadowUF:FormatLargeNumber(UnitPowerMissing(unit))
		end

		if( power <= 0 ) then
			return nil
		end

		local missing = power - cur
		if( missing <= 0 ) then return nil end
		return "-" .. ShadowUF:FormatLargeNumber(missing)
	end]],
	["def:name"] = [[function(unit, unitOwner)
		-- No font string passed on purpose: [missinghp] mustn't fade the name out
		local deficit = ShadowUF.tagFunc.missinghp(unit, unitOwner)
		if( not issecretvalue(deficit) and deficit ) then return deficit end

		-- With secret health it can't be told whether anything is missing: show the name
		return ShadowUF.tagFunc.name(unit, unitOwner)
	end]],
	["name"] = [[function(unit, unitOwner)
		local name = UnitName(unitOwner)
		if( issecretvalue(name) ) then return name end
		return name or _G.UNKNOWN or ShadowUF.L["Unknown"]
	end]],
	["server"] = [[function(unit, unitOwner)
		local server = select(2, UnitName(unitOwner))
		if( issecretvalue(server) ) then return nil end
		if( ShadowUF.Tags.Plain(UnitRealmRelationship(unitOwner)) == (_G.LE_REALM_RELATION_VIRTUAL or 3) ) then
			return nil
		end

		return server ~= "" and server or nil
	end]],
	["perhp"] = [[function(unit, unitOwner)
		if( UnitIsDead(unit) or UnitIsGhost(unit) or not UnitIsConnected(unit) ) then
			return "0%"
		end

		local cur, max = UnitHealth(unit), UnitHealthMax(unit)
		if( issecretvalue(cur) or issecretvalue(max) ) then
			return ShadowUF.Tags.HealthPercentText(unit, "%.0f%%")
		elseif( max <= 0 ) then
			return "0%"
		end

		return math.floor(cur / max * 100 + 0.5) .. "%"
	end]],
	["perpp"] = [[function(unit, unitOwner)
		local maxPower = UnitPowerMax(unit)
		if( not issecretvalue(maxPower) and maxPower <= 0 ) then
			return nil
		elseif( UnitIsDeadOrGhost(unit) or not UnitIsConnected(unit) ) then
			return "0%"
		end

		local power = UnitPower(unit)
		if( issecretvalue(power) or issecretvalue(maxPower) ) then
			return ShadowUF.Tags.PowerPercentText(unit, "%.0f%%")
		end

		return string.format("%d%%", math.floor(power / maxPower * 100 + 0.5))
	end]],
	["plus"] = [[function(unit, unitOwner) local classif = ShadowUF.Tags.Plain(UnitClassification(unit)) return (classif == "elite" or classif == "rareelite") and "+" end]],
	["race"] = [[function(unit, unitOwner) return (UnitRace(unit)) end]],
	["rare"] = [[function(unit, unitOwner) local classif = ShadowUF.Tags.Plain(UnitClassification(unit)) return (classif == "rare" or classif == "rareelite") and ShadowUF.L["Rare"] end]],
	["sex"] = [[function(unit, unitOwner) local sex = ShadowUF.Tags.Plain(UnitSex(unit)) return sex == 2 and ShadowUF.L["Male"] or sex == 3 and ShadowUF.L["Female"] end]],
	["smartclass"] = [[function(unit, unitOwner)
		if( UnitIsPlayer(unit) ) then
			return ShadowUF.tagFunc.class(unit)
		end

		return ShadowUF.tagFunc.creature(unit)
	end]],
	["status"] = [[function(unit, unitOwner)
		if( UnitIsDead(unit) ) then
			return ShadowUF.L["Dead"]
		elseif( UnitIsGhost(unit) ) then
			return ShadowUF.L["Ghost"]
		elseif( not UnitIsConnected(unit) ) then
			return ShadowUF.L["Offline"]
		end
	end]],
	["cpoints"] = [[function(unit, unitOwner)
		-- Combo points are on the target in Forever, like vanilla
		local points = GetComboPoints("player", "target")
		if( issecretvalue(points) ) then return ShadowUF.Tags.Abs(points) end
		if( points ) then return points end

		return ShadowUF.Tags.Abs(UnitPower("player", Enum.PowerType.ComboPoints))
	end]],
	["pet:happiness"] = [[function(unit, unitOwner)
		if( not C_PetInfo or not C_PetInfo.GetPetHappiness ) then return nil end

		local happiness = ShadowUF.Tags.Plain((C_PetInfo.GetPetHappiness()))
		if( happiness == 1 ) then
			return _G.PET_HAPPINESS1 or ShadowUF.L["Unhappy"]
		elseif( happiness == 2 ) then
			return _G.PET_HAPPINESS2 or ShadowUF.L["Content"]
		elseif( happiness == 3 ) then
			return _G.PET_HAPPINESS3 or ShadowUF.L["Happy"]
		end
	end]],
	["smartlevel"] = [[function(unit, unitOwner)
		local classif = ShadowUF.Tags.Plain(UnitClassification(unit))
		if( classif == "worldboss" ) then
			return ShadowUF.L["Boss"]
		else
			local plus = ShadowUF.tagFunc.plus(unit)
			local level = ShadowUF.tagFunc.level(unit)
			if( plus ) then
				return level .. plus
			else
				return level
			end
		end
	end]],
	["dechp"] = [[function(unit, unitOwner)
		local cur, maxHealth = UnitHealth(unit), UnitHealthMax(unit)
		if( issecretvalue(cur) or issecretvalue(maxHealth) ) then
			return ShadowUF.Tags.HealthPercentText(unit, "%.1f%%")
		elseif( maxHealth <= 0 ) then
			return "0.0%"
		end

		return string.format("%.1f%%", (cur / maxHealth) * 100)
	end]],
	["classification"] = [[function(unit, unitOwner)
		local classif = ShadowUF.Tags.Plain(UnitClassification(unit))
		if( classif == "rare" ) then
			return ShadowUF.L["Rare"]
		elseif( classif == "rareelite" ) then
			return ShadowUF.L["Rare Elite"]
		elseif( classif == "elite" ) then
			return ShadowUF.L["Elite"]
		elseif( classif == "worldboss" ) then
			return ShadowUF.L["Boss"]
		elseif( classif == "minus" ) then
			return ShadowUF.L["Minion"]
		end

		return nil
	end]],
	["shortclassification"] = [[function(unit, unitOwner)
		local classif = ShadowUF.Tags.Plain(UnitClassification(unit))
		return classif == "rare" and "R" or classif == "rareelite" and "R+" or classif == "elite" and "+" or classif == "worldboss" and "B" or classif == "minus" and "M"
	end]],
	["group"] = [[function(unit, unitOwner)
		local inRaid = UnitInRaid(unitOwner)
		if( issecretvalue(inRaid) or not inRaid ) then return nil end

		local name, server = UnitName(unitOwner)
		if( issecretvalue(name) or issecretvalue(server) or not name ) then return nil end
		if( server and server ~= "" ) then
			name = string.format("%s-%s", name, server)
		end

		for i=1, GetNumGroupMembers() do
			local raidName, _, group = GetRaidRosterInfo(i)
			if( not issecretvalue(raidName) and raidName == name ) then
				return ShadowUF.Tags.Plain(group)
			end
		end

		return nil
	end]],
	["druid:curpp"] = [[function(unit, unitOwner)
		if( ShadowUF.Tags.Plain((select(2, UnitClass(unit)))) ~= "DRUID" ) then return nil end
		local powerType = ShadowUF.Tags.Plain((UnitPowerType(unit)))
		if( powerType ~= Enum.PowerType.Rage and powerType ~= Enum.PowerType.Energy ) then return nil end
		return ShadowUF:FormatLargeNumber(UnitPower(unit, Enum.PowerType.Mana))
	end]],
	["druid:abscurpp"] = [[function(unit, unitOwner)
		if( ShadowUF.Tags.Plain((select(2, UnitClass(unit)))) ~= "DRUID" ) then return nil end
		local powerType = ShadowUF.Tags.Plain((UnitPowerType(unit)))
		if( powerType ~= Enum.PowerType.Rage and powerType ~= Enum.PowerType.Energy ) then return nil end
		return ShadowUF.Tags.Abs(UnitPower(unit, Enum.PowerType.Mana))
	end]],
	["druid:curmaxpp"] = [[function(unit, unitOwner)
		if( ShadowUF.Tags.Plain((select(2, UnitClass(unit)))) ~= "DRUID" ) then return nil end
		local powerType = ShadowUF.Tags.Plain((UnitPowerType(unit)))
		if( powerType ~= Enum.PowerType.Rage and powerType ~= Enum.PowerType.Energy ) then return nil end

		local maxPower = UnitPowerMax(unit, Enum.PowerType.Mana)
		local power = UnitPower(unit, Enum.PowerType.Mana)
		if( UnitIsDeadOrGhost(unit) ) then
			return string.format("0/%s", ShadowUF:FormatLargeNumber(maxPower))
		elseif( not issecretvalue(maxPower) and not issecretvalue(power) and maxPower == 0 and power == 0 ) then
			return nil
		end

		return string.format("%s/%s", ShadowUF:FormatLargeNumber(power), ShadowUF:FormatLargeNumber(maxPower))
	end]],
	["druid:absolutepp"] = [[function(unit, unitOwner)
		if( ShadowUF.Tags.Plain((select(2, UnitClass(unit)))) ~= "DRUID" ) then return nil end
		local powerType = ShadowUF.Tags.Plain((UnitPowerType(unit)))
		if( powerType ~= Enum.PowerType.Rage and powerType ~= Enum.PowerType.Energy ) then return nil end

		return ShadowUF.Tags.Abs(UnitPower(unit, Enum.PowerType.Mana))
	end]],
	-- Incoming heals and absorbs are always secret in Forever, so "nothing incoming" can't be
	-- told apart: the number tags show 0, the :name tags show the name, the percent shows nothing.
	["per:incheal"] = [[function(unit, unitOwner, fontString)
		local heal = UnitGetIncomingHeals(unit)
		local maxHealth = UnitHealthMax(unit)
		if( issecretvalue(heal) or issecretvalue(maxHealth) ) then return nil end
		return heal and heal > 0 and maxHealth > 0 and string.format("%d%%", (heal / maxHealth) * 100)
	end]],
	["abs:incheal"] = [[function(unit, unitOwner, fontString)
		local heal = UnitGetIncomingHeals(unit)
		if( issecretvalue(heal) ) then return ShadowUF.Tags.Abs(heal) end
		return heal and heal > 0 and string.format("%d", heal)
	end]],
	["incheal"] = [[function(unit, unitOwner, fontString)
		local heal = UnitGetIncomingHeals(unit)
		if( issecretvalue(heal) ) then return ShadowUF:FormatLargeNumber(heal) end
		return heal and heal > 0 and ShadowUF:FormatLargeNumber(heal)
	end]],
	["incheal:name"] = [[function(unit, unitOwner, fontString)
		local heal = UnitGetIncomingHeals(unit)
		if( not issecretvalue(heal) and heal and heal > 0 ) then return string.format("+%d", heal) end
		return ShadowUF.tagFunc.name(unit, unitOwner, fontString)
	end]],
	["abs:incabsorb"] = [[function(unit, unitOwner, fontString)
		local absorb = UnitGetTotalAbsorbs(unit)
		if( issecretvalue(absorb) ) then return ShadowUF.Tags.Abs(absorb) end
		return absorb and absorb > 0 and absorb
	end]],
	["incabsorb"] = [[function(unit, unitOwner, fontString)
		local absorb = UnitGetTotalAbsorbs(unit)
		if( issecretvalue(absorb) ) then return ShadowUF:FormatLargeNumber(absorb) end
		return absorb and absorb > 0 and ShadowUF:FormatLargeNumber(absorb)
	end]],
	["incabsorb:name"] = [[function(unit, unitOwner, fontString)
		local absorb = UnitGetTotalAbsorbs(unit)
		if( not issecretvalue(absorb) and absorb and absorb > 0 ) then return string.format("+%d", absorb) end
		return ShadowUF.tagFunc.name(unit, unitOwner, fontString)
	end]],
	["abs:healabsorb"] = [[function(unit, unitOwner, fontString)
		local absorb = UnitGetTotalHealAbsorbs(unit)
		if( issecretvalue(absorb) ) then return ShadowUF.Tags.Abs(absorb) end
		return absorb and absorb > 0 and absorb
	end]],
	["healabsorb"] = [[function(unit, unitOwner, fontString)
		local absorb = UnitGetTotalHealAbsorbs(unit)
		if( issecretvalue(absorb) ) then return ShadowUF:FormatLargeNumber(absorb) end
		return absorb and absorb > 0 and ShadowUF:FormatLargeNumber(absorb)
	end]],
	-- Units whose GUID is secret can't be matched (ShadowUF.Units.ReadGUID gives nil); they're left out of the count
	["unit:raid:targeting"] = [[function(unit, unitOwner, fontString)
		if( GetNumGroupMembers() == 0 ) then return nil end
		local guid, hidden = ShadowUF.Units.ReadGUID(unit)
		if( hidden ) then return nil end
		if( not guid ) then return "0" end

		local total = 0
		for i=1, GetNumGroupMembers() do
			local raidUnit = ShadowUF.raidUnits[i]
			if( ShadowUF.Units.ReadGUID(ShadowUF.unitTarget[raidUnit]) == guid ) then
				total = total + 1
			end
		end
		return total
	end]],
	["unit:raid:assist"] = [[function(unit, unitOwner, fontString)
		if( GetNumGroupMembers() == 0 ) then return nil end
		local guid, hidden = ShadowUF.Units.ReadGUID(ShadowUF.unitTarget[unit])
		if( hidden ) then return nil end
		if( not guid ) then return "--" end

		local total = 0
		for i=1, GetNumGroupMembers() do
			local raidUnit = ShadowUF.raidUnits[i]
			if( ShadowUF.Units.ReadGUID(ShadowUF.unitTarget[raidUnit]) == guid ) then
				total = total + 1
			end
		end
		return total
	end]],
}

-- Default tag events
Tags.defaultEvents = {
	["totem:timer"]				= "SUF_TOTEM_TIMER",
	["hp:color"]				= "UNIT_HEALTH UNIT_MAXHEALTH",
	["short:druidform"]			= "UNIT_AURA",
	["druidform"]				= "UNIT_AURA",
	["guild"]					= "UNIT_NAME_UPDATE",
	["per:incheal"]				= "UNIT_HEAL_PREDICTION",
	["abs:incheal"]				= "UNIT_HEAL_PREDICTION",
	["incheal:name"]			= "UNIT_HEAL_PREDICTION",
	["incheal"]					= "UNIT_HEAL_PREDICTION",
	["abs:incabsorb"]			= "UNIT_ABSORB_AMOUNT_CHANGED",
	["incabsorb"]				= "UNIT_ABSORB_AMOUNT_CHANGED",
	["incabsorb:name"]			= "UNIT_ABSORB_AMOUNT_CHANGED",
	["abs:healabsorb"]			= "UNIT_HEAL_ABSORB_AMOUNT_CHANGED",
	["healabsorb"]				= "UNIT_HEAL_ABSORB_AMOUNT_CHANGED",
	-- ["crtabs"]				= "CRTABS",
	-- ["abs:crtabs"]			= "CRTABS",
	-- ["crtabs:name"]			= "CRTABS",
	["afk"]						= "PLAYER_FLAGS_CHANGED", -- Yes, I know it's called PLAYER_FLAGS_CHANGED, but arg1 is the unit including non-players.
	["afk:time"]				= "PLAYER_FLAGS_CHANGED UNIT_CONNECTION",
	["status:time"]				= "UNIT_POWER_FREQUENT UNIT_CONNECTION",
	["pvp:time"]				= "PLAYER_FLAGS_CHANGED",
	["curhp"]               	= "UNIT_HEALTH UNIT_CONNECTION",
	["abscurhp"]				= "UNIT_HEALTH UNIT_CONNECTION",
	["curmaxhp"]				= "UNIT_HEALTH UNIT_MAXHEALTH UNIT_CONNECTION",
	["absolutehp"]				= "UNIT_HEALTH UNIT_MAXHEALTH UNIT_CONNECTION",
	["smart:curmaxhp"]			= "UNIT_HEALTH UNIT_MAXHEALTH UNIT_CONNECTION",
	["curpp"]               	= "SUF_POWERTYPE:CURRENT UNIT_POWER_FREQUENT",
	["abscurpp"]            	= "SUF_POWERTYPE:CURRENT UNIT_POWER_FREQUENT UNIT_MAXPOWER",
	["curmaxpp"]				= "SUF_POWERTYPE:CURRENT UNIT_POWER_FREQUENT UNIT_MAXPOWER",
	["absolutepp"]				= "SUF_POWERTYPE:CURRENT UNIT_POWER_FREQUENT UNIT_MAXPOWER",
	["smart:curmaxpp"]			= "SUF_POWERTYPE:CURRENT UNIT_POWER_FREQUENT UNIT_MAXPOWER",
	["druid:curpp"]  	    	= "SUF_POWERTYPE:MANA UNIT_POWER_FREQUENT UNIT_DISPLAYPOWER",
	["druid:abscurpp"]      	= "SUF_POWERTYPE:MANA UNIT_POWER_FREQUENT UNIT_DISPLAYPOWER",
	["druid:curmaxpp"]			= "SUF_POWERTYPE:MANA UNIT_POWER_FREQUENT UNIT_MAXPOWER UNIT_DISPLAYPOWER",
	["druid:absolutepp"]		= "SUF_POWERTYPE:MANA UNIT_POWER_FREQUENT UNIT_MAXPOWER UNIT_DISPLAYPOWER",
	["level"]               	= "UNIT_LEVEL UNIT_FACTION PLAYER_LEVEL_UP",
	["levelcolor"]				= "UNIT_LEVEL UNIT_FACTION PLAYER_LEVEL_UP",
	["maxhp"]               	= "UNIT_MAXHEALTH",
	["def:name"]				= "UNIT_NAME_UPDATE UNIT_MAXHEALTH UNIT_HEALTH",
	["absmaxhp"]				= "UNIT_MAXHEALTH",
	["maxpp"]               	= "SUF_POWERTYPE:CURRENT UNIT_MAXPOWER",
	["absmaxpp"]				= "SUF_POWERTYPE:CURRENT UNIT_MAXPOWER",
	["missinghp"]           	= "UNIT_HEALTH UNIT_MAXHEALTH UNIT_CONNECTION",
	["missingpp"]           	= "SUF_POWERTYPE:CURRENT UNIT_POWER_FREQUENT UNIT_MAXPOWER",
	["name"]                	= "UNIT_NAME_UPDATE",
	["abbrev:name"]				= "UNIT_NAME_UPDATE",
	["server"]					= "UNIT_NAME_UPDATE",
	["colorname"]				= "UNIT_NAME_UPDATE",
	["perhp"]               	= "UNIT_HEALTH UNIT_MAXHEALTH UNIT_CONNECTION",
	["perpp"]               	= "SUF_POWERTYPE:CURRENT UNIT_POWER_FREQUENT UNIT_MAXPOWER UNIT_CONNECTION",
	["status"]              	= "UNIT_HEALTH PLAYER_UPDATE_RESTING UNIT_CONNECTION",
	["smartlevel"]          	= "UNIT_LEVEL PLAYER_LEVEL_UP UNIT_CLASSIFICATION_CHANGED",
	["cpoints"]             	= "UNIT_POWER_FREQUENT PLAYER_TARGET_CHANGED COMBO_TARGET_CHANGED",
	["pet:happiness"]			= "UNIT_HAPPINESS",
	["rare"]                	= "UNIT_CLASSIFICATION_CHANGED",
	["classification"]      	= "UNIT_CLASSIFICATION_CHANGED",
	["shortclassification"] 	= "UNIT_CLASSIFICATION_CHANGED",
	["dechp"]					= "UNIT_HEALTH UNIT_MAXHEALTH",
	["group"]					= "GROUP_ROSTER_UPDATE",
	["unit:color:aggro"]		= "UNIT_THREAT_SITUATION_UPDATE",
	["color:aggro"]				= "UNIT_THREAT_SITUATION_UPDATE",
	["situation"]				= "UNIT_THREAT_SITUATION_UPDATE",
	["color:sit"]				= "UNIT_THREAT_SITUATION_UPDATE",
	["scaled:threat"]			= "UNIT_THREAT_SITUATION_UPDATE",
	["general:sit"]				= "UNIT_THREAT_SITUATION_UPDATE",
	["color:gensit"]			= "UNIT_THREAT_SITUATION_UPDATE",
	["unit:scaled:threat"]		= "UNIT_THREAT_SITUATION_UPDATE",
	["unit:color:sit"]			= "UNIT_THREAT_SITUATION_UPDATE",
	["unit:situation"]			= "UNIT_THREAT_SITUATION_UPDATE",
}

-- Default update frequencies for tag updating, used if it's needed to override the update speed
-- or it can't be purely event based
Tags.defaultFrequents = {
	["afk"] = 1,
	["afk:time"] = 1,
	["status:time"] = 1,
	["pvp:time"] = 1,
	["scaled:threat"] = 1,
	["unit:scaled:threat"] = 1,
	["unit:raid:targeting"] = 0.50,
	["unit:raid:assist"] = 0.50,
	-- Combo points change on the player but are shown on the target frame, whose unit
	-- events are filtered to "target"; poll so it never goes stale
	["cpoints"] = 0.25,
}

-- Default tag categories
Tags.defaultCategories = {
	["totem:timer"]				= "classtimer",
	["hp:color"]				= "health",
	["abs:incabsorb"]			= "health",
	["incabsorb"]				= "health",
	["incabsorb:name"]			= "health",
	["per:incheal"]				= "health",
	["abs:incheal"]				= "health",
	["incheal"]					= "health",
	["incheal:name"]			= "health",
	["smart:curmaxhp"]			= "health",
	["smart:curmaxpp"]			= "health",
	["afk"]						= "status",
	["afk:time"]				= "status",
	["status:time"]				= "status",
	["pvp:time"]				= "status",
	["cpoints"]					= "classspec",
	["smartlevel"]				= "classification",
	["classification"]			= "classification",
	["shortclassification"]		= "classification",
	["rare"]					= "classification",
	["plus"]					= "classification",
	["sex"]						= "misc",
	["smartclass"]				= "classification",
	["smartrace"]				= "classification",
	["status"]					= "status",
	["race"]					= "classification",
	["level"]					= "classification",
	["maxhp"]					= "health",
	["maxpp"]					= "power",
	["missinghp"]				= "health",
	["missingpp"]				= "power",
	["name"]					= "misc",
	["abbrev:name"]				= "misc",
	["server"]					= "misc",
	["perhp"]					= "health",
	["perpp"]					= "power",
	["class"]					= "classification",
	["classcolor"]				= "classification",
	["creature"]				= "classification",
	["short:druidform"]			= "classification",
	["druidform"]				= "classification",
	["curhp"]					= "health",
	["curpp"]					= "power",
	["curmaxhp"]				= "health",
	["curmaxpp"]				= "power",
	["levelcolor"]				= "classification",
	["def:name"]				= "health",
	["faction"]					= "classification",
	["colorname"]				= "misc",
	["guild"]					= "misc",
	["absolutepp"]				= "power",
	["absolutehp"]				= "health",
	["absmaxhp"]				= "health",
	["abscurhp"]				= "health",
	["absmaxpp"]				= "power",
	["abscurpp"]				= "power",
	["reactcolor"]				= "classification",
	["dechp"]					= "health",
	["group"]					= "misc",
	["close"]					= "misc",
	["druid:curpp"]     	    = "classspec",
	["druid:abscurpp"]  	    = "classspec",
	["druid:curmaxpp"]			= "classspec",
	["druid:absolutepp"]		= "classspec",
	["situation"]				= "playerthreat",
	["color:sit"]				= "playerthreat",
	["scaled:threat"]			= "playerthreat",
	["general:sit"]				= "playerthreat",
	["color:gensit"]			= "playerthreat",
	["color:aggro"]				= "playerthreat",
	["unit:scaled:threat"]		= "threat",
	["unit:color:sit"]			= "threat",
	["unit:situation"]			= "threat",
	["unit:color:aggro"]		= "threat",
	["unit:raid:assist"]		= "raid",
	["unit:raid:targeting"] 	= "raid",
	["pet:happiness"]			= "classspec",
}

-- Default tag help
Tags.defaultHelp = {
	["totem:timer"]				= L["How many seconds a totem has left before disappearing."],
	["abs:incabsorb"]			= L["Absolute damage absorption value on the unit, if 10,000 damage will be absorbed, it will show 10,000.|nAbsorbs are hidden from addons, so this shows 0 when there is no shield."],
	["incabsorb"]				= L["Shorten damage absorption, if 13,000 damage will e absorbed, it will show 13k.|nAbsorbs are hidden from addons, so this shows 0 when there is no shield."],
	["incabsorb:name"]			= L["If the unit has a damage absorption shield on them, it will show the absolute absorb value, otherwise the units name.|nWhile absorbs are hidden from addons, the name is always shown."],
	["hp:color"]				= L["Color code based on percentage of HP left on the unit, this works the same way as the color by health option. But for text instead of the entire bar."],
	["guild"]					= L["Show's the units guild name if they are in a guild."],
	["short:druidform"]			= L["Short version of [druidform], C = Cat, B = Bear, F = Flight and so on."],
	["druidform"]				= L["Returns the units current form if they are a druid, Cat for Cat Form, Moonkin for Moonkin and so on."],
	["per:incheal"]				= L["Percent of the players current health that's being healed, if they have 100,000 total health and 15,000 is incoming then 15% is shown.|nShows nothing while incoming heals are hidden from addons."],
	["abs:incheal"]				= L["Absolute incoming heal value, if 10,000 healing is incoming it will show 10,000.|nIncoming heals are hidden from addons, so this shows 0 when nothing is incoming."],
	["incheal"]					= L["Shorten incoming heal value, if 13,000 healing is incoming it will show 13k.|nIncoming heals are hidden from addons, so this shows 0 when nothing is incoming."],
	["abs:healabsorb"]			= L["Absolute heal absorb value, if 16,000 healing will be absorbed, it will show 16,000.|nHeal absorbs are hidden from addons, so this shows 0 when there is none."],
	["healabsorb"]				= L["Shorten heal absorb value, if 17,000 healing will be absorbed, it will show 17k.|nHeal absorbs are hidden from addons, so this shows 0 when there is none."],
	["incheal:name"]			= L["If the unit has heals incoming, it will show the absolute incoming heal value, otherwise it will show the units name.|nWhile incoming heals are hidden from addons, the name is always shown."],
	["smart:curmaxhp"]			= L["Smart number formating for [curmaxhp], numbers below 1,000,000 are left as is, numbers above 1,000,000 will use the short version such as 1m."],
	["smart:curmaxpp"]			= L["Smart number formating for [curmaxpp], numbers below 1,000,000 are left as is, numbers above 1,000,000 will use the short version such as 1m."],
	["pvp:time"]				= L["Shows how long until your PVP flag drops, will not show if the flag is manually on or you are in a hostile zone.|n|nThis will only work for yourself, you cannot use it to see the time left on your party or raid."],
	["afk:time"]				= L["Shows how long an unit has been AFK or DND."],
	["status:time"]				= L["Shows how long an unit has been offline."],
	["afk"]						= L["Shows AFK, DND or nothing depending on the units away status."],
	["cpoints"]					= L["Total number of combo points you have on your target."],
	["smartlevel"]				= L["Smart level, returns Boss for bosses, +50 for a level 50 elite mob, or just 80 for a level 80."],
	["classification"]			= L["Units classification, Rare, Rare Elite, Elite, Boss or Minion nothing is shown if they aren't any of those."],
	["shortclassification"]		= L["Short classifications, R for Rare, R+ for Rare Elite, + for Elite, B for Boss or M for Minion nothing is shown if they aren't any of those."],
	["rare"]					= L["Returns Rare if the unit is a rare or rare elite mob."],
	["plus"]					= L["Returns + if the unit is an elite or rare elite mob."],
	["sex"]						= L["Returns the units sex."],
	["smartclass"]				= L["If the unit is a player then class is returned, if it's a NPC then the creature type."],
	["smartrace"]				= L["If the unit is a player then race is returned, if it's a NPC then the creature type."],
	["status"]					= L["Shows Offline, Dead, Ghost or nothing depending on the units current status."],
	["race"]					= L["Units race, Blood Elf, Tauren, Troll (unfortunately) and so on."],
	["level"]					= L["Level without any coloring."],
	["maxhp"]					= L["Max health, uses a short format, 17750 is formatted as 17.7k, values below 10000 are formatted as is."],
	["maxpp"]					= L["Max power, uses a short format, 16000 is formatted as 16k, values below 10000 are formatted as is."],
	["missinghp"]				= L["Amount of health missing, if none is missing nothing is shown. Uses a short format, -18500 is shown as -18.5k, values below 10000 are formatted as is.|nIn combat, when health is hidden from addons, this text can only hide itself at full health if it is the only tag in the text; otherwise it shows -0."],
	["missingpp"]				= L["Amount of power missing,  if none is missing nothing is shown. Uses a short format, -13850 is shown as 13.8k, values below 10000 are formatted as is.|nWhen power is hidden from addons, this text can only hide itself at full power if it is the only tag in the text; otherwise it shows -0."],
	["name"]					= L["Unit name"],
	["server"]					= L["Unit server, if they are from your server then nothing is shown."],
	["perhp"]					= L["Returns current health as a percentage, if the unit is dead or offline than that is shown instead."],
	["perpp"]					= L["Returns current power as a percentage."],
	["class"]					= L["Class name without coloring, use [classcolor][class][close] if you want the class name to be colored by class."],
	["classcolor"]				= L["Color code for the class, use [classcolor][class][close] if you want the class text to be colored by class"],
	["creature"]				= L["Creature type, returns Felguard if the unit is a Felguard, Wolf if it's a Wolf and so on."],
	["curhp"]					= L["Current health, uses a short format, 11500 is formatted as 11.5k, values below 10000 are formatted as is."],
	["curpp"]					= L["Current power, uses a short format, 12750 is formatted as 12.7k, values below 10000 are formatted as is."],
	["curmaxhp"]				= L["Current and maximum health, formatted as [curhp]/[maxhp], if the unit is dead or offline then that is shown instead."],
	["curmaxpp"]				= L["Current and maximum power, formatted as [curpp]/[maxpp]."],
	["levelcolor"]				= L["Returns the color code based off of the units level compared to yours. If you cannot attack them then no color is returned."],
	["def:name"]				= L["When the unit is mising health, the [missinghp] tag is shown, when they are at full health then the [name] tag is shown. This lets you see -1000 when they are missing 1000 HP, but their name when they are not missing any.|nIn combat, when health is hidden from addons, the name is always shown."],
	["faction"]					= L["Units alignment, Thrall will return Horde, Magni Bronzebeard will return Alliance."],
	["colorname"]				= L["Unit name colored by class."],
	["absolutepp"]				= L["Shows current and maximum power in absolute form, 18000 power will be showed as 18000 power."],
	["absolutehp"]				= L["Shows current and maximum health in absolute form, 17500 health will be showed as 17500 health."],
	["absmaxhp"]				= L["Shows maximum health in absolute form, 14000 health is showed as 14000 health."],
	["abscurhp"]				= L["Shows current health value in absolute form meaning 15000 health is shown as 15000."],
	["absmaxpp"]				= L["Shows maximum power in absolute form, 13000 power is showed as 13000 power."],
	["abscurpp"]				= L["Shows current power value in absolute form, 15000 power will be displayed as 1500 still."],
	["reactcolor"]				= L["Reaction color code, use [reactcolor][name][close] to color the units name by their reaction."],
	["dechp"]					= L["Shows the units health as a percentage rounded to the first decimal, meaning 61 out of 110 health is shown as 55.4%."],
	["abbrev:name"]				= L["Abbreviates unit names above 10 characters, \"Dark Rune Champion\" becomes \"D.R.Champion\" and \"Dark Rune Commoner\" becomes \"D.R.Commoner\".|nNames hidden from addons are shown in full."],
	["group"]					= L["Shows current group number of the unit."],
	["close"]					= L["Closes a color code, prevents colors from showing up on text that you do not want it to."],
	["druid:curpp"]         	= string.format(L["Works the same as [%s], but this is only shown if the unit is in Cat or Bear form."], "curpp"),
	["druid:abscurpp"]      	= string.format(L["Works the same as [%s], but this is only shown if the unit is in Cat or Bear form."], "abscurpp"),
	["druid:curmaxpp"]			= string.format(L["Works the same as [%s], but this is only shown if the unit is in Cat or Bear form."], "curmaxpp"),
	["druid:absolutepp"]		= string.format(L["Works the same as [%s], but this is only shown if the unit is in Cat or Bear form."], "absolutepp"),
	["situation"]				= L["Returns text based on your threat situation with your target: Aggro for Aggro, High for being close to taking aggro, and Medium as a general warning to be wary.|nShows nothing while threat is hidden from addons."],
	["color:sit"]				= L["Returns a color code of the threat situation with your target: Red for Aggro, Orange for High threat and Yellow to be careful.|nShows nothing while threat is hidden from addons."],
	["scaled:threat"]			= L["Returns a scaled threat percent of your aggro on your current target, always 0 - 100%."],
	["general:sit"]				= L["Returns text based on your general threat situation on all units: Aggro for Aggro, High for being near to pulling aggro and Medium as a general warning.|nShows nothing while threat is hidden from addons."],
	["color:gensit"]			= L["Returns a color code of your general threat situation on all units: Red for Aggro, Orange for High threat and Yellow to watch out.|nShows nothing while threat is hidden from addons."],
	["unit:scaled:threat"]		= L["Returns the scaled threat percentage for the unit, if you put this on a party member you would see the percentage of how close they are to getting any from any hostile mobs. Always 0 - 100%.|nThis cannot be used on target of target or focus target types of units."],
	["unit:color:sit"]			= L["Returns the color code for the units threat situation in general: Red for Aggro, Orange for High threat and Yellow to watch out.|nThis cannot be used on target of target or focus target types of units.|nShows nothing while threat is hidden from addons."],
	["unit:situation"]			= L["Returns text based on the units general threat situation: Aggro for Aggro, High for being close to taking aggro, and Medium as a warning to be wary.|nThis cannot be used on target of target or focus target types of units.|nShows nothing while threat is hidden from addons."],
	["unit:color:aggro"]		= L["Same as [unit:color:sit] except it only returns red if the unit has aggro, rather than transiting from yellow -> orange -> red."],
	["color:aggro"]				= L["Same as [color:sit] except it only returns red if you have aggro, rather than transiting from yellow -> orange -> red."],
	["unit:raid:targeting"]		= L["How many people in your raid are targeting the unit, for example if you put this on yourself it will show how many people are targeting you. This includes you in the count!|nPeople whose target is hidden from addons are not counted."],
	["unit:raid:assist"]		= L["How many people are assisting the unit, for example if you put this on yourself it will show how many people are targeting your target. This includes you in the count!|nPeople whose target is hidden from addons are not counted."],
	["pet:happiness"]			= L["Your hunter pet's happiness: Happy, Content or Unhappy. Shows nothing if the game doesn't report it."],
}

Tags.defaultNames = {
	["totem:timer"]				= L["Totem Timer"],
	["abs:incabsorb"]			= L["Damage absorption (Absolute)"],
	["incabsorb"]				= L["Damage absorption (Short)"],
	["incabsorb:name"]			= L["Damage absorption/Name"],
	["per:incheal"]				= L["Incoming heal (Percent)"],
	["incheal:name"]			= L["Incoming heal/Name"],
	["abs:healabsorb"]			= L["Heal Absorb (Absolute)"],
	["healabsorb"]				= L["Heal Absorb (Short)"],
	["unit:scaled:threat"]		= L["Unit scaled threat"],
	["unit:color:sit"]			= L["Unit colored situation"],
	["unit:situation"]			= L["Unit situation name"],
	["hp:color"]				= L["Health color"],
	["guild"]					= L["Guild name"],
	["druidform"]				= L["Druid form"],
	["short:druidform"]			= L["Druid form (Short)"],
	["abs:incheal"]				= L["Incoming heal (Absolute)"],
	["incheal"]					= L["Incoming heal (Short)"],
	["abbrev:name"]				= L["Name (Abbreviated)"],
	["smart:curmaxhp"]			= L["Cur/Max HP (Smart)"],
	["smart:curmaxpp"]			= L["Cur/Max PP (Smart)"],
	["pvp:time"]				= L["PVP timer"],
	["afk:time"]				= L["AFK timer"],
	["status:time"]				= L["Offline timer"],
	["afk"]						= L["AFK status"],
	["cpoints"]					= L["Combo points"],
	["smartlevel"]				= L["Smart level"],
	["classification"]			= L["Classification"],
	["shortclassification"]		= L["Short classification"],
	["rare"]					= L["Rare indicator"],
	["plus"]					= L["Short elite indicator"],
	["sex"]						= L["Sex"],
	["smartclass"]				= L["Class (Smart)"],
	["smartrace"]				= L["Race (Smart)"],
	["status"]					= L["Status"],
	["race"]					= L["Race"],
	["level"]					= L["Level"],
	["maxhp"]					= L["Max HP (Short)"],
	["maxpp"]					= L["Max power (Short)"],
	["missinghp"]				= L["Missing HP (Short)"],
	["missingpp"]				= L["Missing power (Short)"],
	["name"]					= L["Unit name"],
	["server"]					= L["Unit server"],
	["perhp"]					= L["Percent HP"],
	["perpp"]					= L["Percent power"],
	["class"]					= L["Class"],
	["classcolor"]				= L["Class color tag"],
	["creature"]				= L["Creature type"],
	["curhp"]					= L["Current HP (Short)"],
	["curpp"]					= L["Current Power (Short)"],
	["curmaxhp"]				= L["Cur/Max HP (Short)"],
	["curmaxpp"]				= L["Cur/Max Power (Short)"],
	["levelcolor"]				= L["Level (Colored)"],
	["def:name"]				= L["Deficit/Unit Name"],
	["faction"]					= L["Unit faction"],
	["colorname"]				= L["Unit name (Class colored)"],
	["absolutepp"]				= L["Cur/Max power (Absolute)"],
	["absolutehp"]				= L["Cur/Max HP (Absolute)"],
	["absmaxhp"]				= L["Max HP (Absolute)"],
	["abscurhp"]				= L["Current HP (Absolute)"],
	["absmaxpp"]				= L["Max power (Absolute)"],
	["abscurpp"]				= L["Current power (Absolute)"],
	["reactcolor"]				= L["Reaction color tag"],
	["dechp"]					= L["Decimal percent HP"],
	["group"]					= L["Group number"],
	["close"]					= L["Close color"],
	["druid:curpp"]         	= L["Current power (Druid)"],
	["druid:abscurpp"]      	= L["Current power (Druid/Absolute)"],
	["druid:curmaxpp"]			= L["Cur/Max power (Druid)"],
	["druid:absolutepp"]		= L["Cur/Max power (Druid/Absolute)"],
	["situation"]				= L["Threat situation"],
	["color:sit"]				= L["Color code for situation"],
	["scaled:threat"]			= L["Scaled threat percent"],
	["general:sit"]				= L["General threat situation"],
	["color:gensit"]			= L["Color code for general situation"],
	["color:aggro"]				= L["Color code on aggro"],
	["unit:color:aggro"]		= L["Unit color code on aggro"],
	["unit:raid:targeting"]		= L["Raid targeting unit"],
	["unit:raid:assist"]		= L["Raid assisting unit"],
	["pet:happiness"]			= L["Pet happiness"],
}

-- List of event types
Tags.eventType = {
	["UNIT_POWER_FREQUENT"] = "power",
	["UNIT_MAXPOWER"] = "power",
	["UNIT_ABSORB_AMOUNT_CHANGED"] = "health",
	["UNIT_HEALTH"] = "health",
	["UNIT_MAXHEALTH"] = "health",
	["GROUP_ROSTER_UPDATE"] = "unitless",
	["RAID_TARGET_UPDATE"] = "unitless",
	["PLAYER_TARGET_CHANGED"] = "unitless",
	["PARTY_LEADER_CHANGED"] = "unitless",
	["PLAYER_ENTERING_WORLD"] = "unitless",
	["PLAYER_REGEN_DISABLED"] = "unitless",
	["PLAYER_REGEN_ENABLED"] = "unitless",
	["PLAYER_XP_UPDATE"] = "unitless",
	["PLAYER_TOTEM_UPDATE"] = "unitless",
	["PLAYER_LEVEL_UP"] = "unitless",
	["UPDATE_EXHAUSTION"] = "unitless",
	["PLAYER_UPDATE_RESTING"] = "unitless",
	["COMBO_TARGET_CHANGED"] = "unitless",
	["PARTY_LOOT_METHOD_CHANGED"] = "unitless",
	["READY_CHECK"] = "unitless",
	["READY_CHECK_FINISHED"] = "unitless",
	["UPDATE_FACTION"] = "unitless",
}

-- Tag groups that have a special filter that can't be used on certain units, like the threat API's
Tags.unitBlacklist = {
	["threat"]	= "%w+target",
}

-- Single tags that can only be used on a single unit
Tags.unitRestrictions = {
	["pvp:time"] = "player",
	["totem:timer"] = "player",
	["pet:happiness"] = "pet",
}

Tags.anchorRestriction = {
	["totem:timer"] = "$totemBar",
}

-- Event scanner to automatically figure out what events a tag will need
local function loadAPIEvents()
	if( Tags.APIEvents ) then return end
	Tags.APIEvents = {
		["InCombatLockdown"]		= "PLAYER_REGEN_ENABLED PLAYER_REGEN_DISABLED",
		["UnitLevel"]				= "UNIT_LEVEL UNIT_FACTION",
		["UnitBattlePetLevel"]		= "UNIT_LEVEL UNIT_FACTION",
		["UnitName"]				= "UNIT_NAME_UPDATE",
		["UnitClassification"]		= "UNIT_CLASSIFICATION_CHANGED",
		["UnitFactionGroup"]		= "UNIT_FACTION PLAYER_FLAGS_CHANGED",
		["UnitHealth%("]			= "UNIT_HEALTH",
		["UnitHealthMax"]			= "UNIT_MAXHEALTH",
		["UnitPower%("]				= "UNIT_POWER_FREQUENT",
		["UnitPowerMax"]			= "UNIT_MAXPOWER",
		["UnitHealthPercent"]		= "UNIT_HEALTH UNIT_MAXHEALTH",
		["UnitHealthMissing"]		= "UNIT_HEALTH UNIT_MAXHEALTH",
		["UnitPowerPercent"]		= "UNIT_POWER_FREQUENT UNIT_MAXPOWER",
		["UnitPowerMissing"]		= "UNIT_POWER_FREQUENT UNIT_MAXPOWER",
		["UnitGetIncomingHeals"]	= "UNIT_HEAL_PREDICTION",
		["UnitGetTotalHealAbsorbs"]	= "UNIT_HEAL_ABSORB_AMOUNT_CHANGED",
		["GetPetHappiness"]		= "UNIT_HAPPINESS",
		["UnitPowerType"]			= "UNIT_DISPLAYPOWER",
		["UnitIsDead"]				= "UNIT_HEALTH",
		["UnitIsGhost"]				= "UNIT_HEALTH",
		["UnitIsConnected"]			= "UNIT_HEALTH UNIT_CONNECTION",
		["UnitIsAFK"]				= "PLAYER_FLAGS_CHANGED",
		["UnitIsDND"]				= "PLAYER_FLAGS_CHANGED",
		["UnitIsPVP"]				= "PLAYER_FLAGS_CHANGED UNIT_FACTION",
		["UnitIsGroupLeader"]		= "PARTY_LEADER_CHANGED GROUP_ROSTER_UPDATE",
		["UnitIsPVPFreeForAll"]		= "PLAYER_FLAGS_CHANGED UNIT_FACTION",
		["UnitCastingInfo"]			= "UNIT_SPELLCAST_START UNIT_SPELLCAST_STOP UNIT_SPELLCAST_FAILED UNIT_SPELLCAST_INTERRUPTED UNIT_SPELLCAST_DELAYED",
		["UnitChannelInfo"]			= "UNIT_SPELLCAST_CHANNEL_START UNIT_SPELLCAST_CHANNEL_STOP UNIT_SPELLCAST_CHANNEL_INTERRUPTED UNIT_SPELLCAST_CHANNEL_UPDATE",
		["GetAuraDataByIndex"]		= "UNIT_AURA",
		["GetBuffDataByIndex"]		= "UNIT_AURA",
		["GetDebuffDataByIndex"]	= "UNIT_AURA",
		["UnitAuraBySpell"]			= "UNIT_AURA",
		["UnitXPMax"]				= "UNIT_PET_EXPERIENCE PLAYER_XP_UPDATE PLAYER_LEVEL_UP",
		["UnitGetTotalAbsorbs"]		= "UNIT_ABSORB_AMOUNT_CHANGED",
		["UnitXP%("]				= "UNIT_PET_EXPERIENCE PLAYER_XP_UPDATE PLAYER_LEVEL_UP",
		["GetTotemInfo"]			= "PLAYER_TOTEM_UPDATE",
		["GetXPExhaustion"]			= "UPDATE_EXHAUSTION",
		["GetWatchedFactionInfo"]	= "UPDATE_FACTION",
		["GetRaidTargetIndex"]		= "RAID_TARGET_UPDATE",
		["GetComboPoints"]			= "UNIT_POWER_FREQUENT PLAYER_TARGET_CHANGED COMBO_TARGET_CHANGED",
		["GetNumSubgroupMembers"]	= "GROUP_ROSTER_UPDATE",
		["GetNumGroupMembers"]		= "GROUP_ROSTER_UPDATE",
		["GetRaidRosterInfo"]		= "GROUP_ROSTER_UPDATE",
		["GetReadyCheckStatus"]		= "READY_CHECK READY_CHECK_CONFIRM READY_CHECK_FINISHED",
		["GetLootMethod"]			= "PARTY_LOOT_METHOD_CHANGED",
		["GetThreatStatusColor"]	= "UNIT_THREAT_SITUATION_UPDATE",
		["UnitThreatSituation"]		= "UNIT_THREAT_SITUATION_UPDATE",
		["UnitDetailedThreatSituation"] = "UNIT_THREAT_SITUATION_UPDATE",
	}
end

-- Scan the actual tag code to find the events it uses
local alreadyScanned = {}
function Tags:IdentifyEvents(code, parentTag)
	-- Already scanned this tag, prevents infinite recursion
	if( parentTag and alreadyScanned[parentTag] ) then
		return ""
	-- Flagged that we already took care of this
	elseif( parentTag ) then
		alreadyScanned[parentTag] = true
	else
		for k in pairs(alreadyScanned) do alreadyScanned[k] = nil end
		loadAPIEvents()
	end

	-- Scan our function list to see what APIs are used
	local eventList = ""
	for func, events in pairs(self.APIEvents) do
		if( string.match(code, func) ) then
			eventList = eventList .. events .. " "
		end
	end

	-- Scan if they use any tags, if so we need to check them as well to see what content is used
	for tag in string.gmatch(code, "tagFunc%.(%w+)%(") do
		local c = ShadowUF.Tags.defaultTags[tag] or ShadowUF.db.profile.tags[tag] and ShadowUF.db.profile.tags[tag].func
		eventList = eventList .. " " .. self:IdentifyEvents(c, tag)
	end

	-- Remove any duplicate events
	if( not parentTag ) then
		local tagEvents = {}
		for event in string.gmatch(string.trim(eventList), "%S+") do
			tagEvents[event] = true
		end

		eventList = ""
		for event in pairs(tagEvents) do
			eventList = eventList .. event .. " "
		end
	end

	-- And give them our nicely outputted data
	return string.trim(eventList or "")
end


-- Checker function, makes sure tags are all happy
--@debug@
function Tags:Verify()
	local fine = true
	for tag, events in pairs(self.defaultEvents) do
		if( not self.defaultTags[tag] ) then
			print(string.format("Found event for %s, but no tag associated with it.", tag))
			fine = nil
		end
	end

	for tag, data in pairs(self.defaultTags) do
		if( not self.defaultTags[tag] ) then
			print(string.format("Found tag for %s, but no event associated with it.", tag))
			fine = nil
		end

		if( not self.defaultHelp[tag] ) then
			print(string.format("Found tag for %s, but no help text associated with it.", tag))
			fine = nil
		end

		if( not self.defaultNames[tag] ) then
			print(string.format("Found tag for %s, but no name associated with it.", tag))
			fine = nil
		end

		if( not self.defaultCategories[tag] ) then
			print(string.format("Found tag for %s, but no category associated with it.", tag))
			fine = nil
		end

		local funct, msg = loadstring("return " .. data)
		if( not funct and msg ) then
			print(string.format("Failed to load tag %s.", tag))
			print(msg)
			fine = nil
		else
			funct("player")
		end
	end

	if( fine ) then
		print("Verified tags, everything is fine.")
	end
end
--@end-debug@
