--[[
	Range indicator. Originally by Shadowed (Shadowed Unit Frames), ported to WoW Forever.

	Forever: LibSpellRange is gone. Range comes from C_Spell.IsSpellInRange with Classic-era
	spells, then UnitInRange for group members (secret result: applied with SetAlphaFromBoolean),
	then CheckInteractDistance (28 yards) out of combat.
]]
local GetSpellName = C_Spell.GetSpellName
local GetSpellInfo = C_Spell.GetSpellInfo
local IsSpellUsable = C_Spell.IsSpellUsable
local IsSpellInRange = C_Spell.IsSpellInRange
local Secrets = ShadowUF.Secrets
local issecretvalue = Secrets.IsSecret

-- Spells checked in order; a unit counts as in range if any of them is in range (so melee + ranged
-- spells cover hunters' dead zone). Spell IDs are rank 1, the names resolve to whatever rank is known.
local Range = {
	friendly = {
		["PRIEST"] = {2050, 2061, 139, 17}, -- Lesser Heal, Flash Heal, Renew, Power Word: Shield (40 yards)
		["DRUID"] = {5185, 774}, -- Healing Touch, Rejuvenation (40 yards)
		["PALADIN"] = {635, 19750}, -- Holy Light, Flash of Light (40 yards)
		["SHAMAN"] = {331, 8004}, -- Healing Wave, Lesser Healing Wave (40 yards)
		["MAGE"] = {475, 1459}, -- Remove Lesser Curse (40 yards), Arcane Intellect (30 yards)
		["WARLOCK"] = {5697}, -- Unending Breath (30 yards)
	},
	hostile = {
		["PRIEST"] = {589, 585, 8092}, -- Shadow Word: Pain, Smite, Mind Blast (30 yards)
		["DRUID"] = {5176, 8921}, -- Wrath, Moonfire (30 yards)
		["PALADIN"] = {20473, 20271, 853}, -- Holy Shock (20 yards, talent), Judgement, Hammer of Justice (10 yards)
		["SHAMAN"] = {403, 8042}, -- Lightning Bolt (30 yards), Earth Shock (20 yards)
		["MAGE"] = {116, 133, 2136}, -- Frostbolt (30 yards), Fireball (35 yards), Fire Blast (20 yards)
		["WARLOCK"] = {686, 348, 172}, -- Shadow Bolt, Immolate, Corruption (30 yards)
		["HUNTER"] = {3044, 75, 1978, 2974, 2973}, -- Arcane Shot, Auto Shot, Serpent Sting (35 yards, 8 yard minimum), Wing Clip, Raptor Strike (melee)
		["ROGUE"] = {2764, 2480, 7918, 7919, 1752}, -- Throw, Shoot Bow/Gun/Crossbow (30 yards), Sinister Strike (melee)
		["WARRIOR"] = {2480, 7918, 7919, 2764, 78}, -- Shoot Bow/Gun/Crossbow, Throw (30 yards), Heroic Strike (melee)
	},
}

ShadowUF:RegisterModule(Range, "range", ShadowUF.L["Range indicator"])

local playerClass = select(2, UnitClass("player"))
local rangeSpells = {friendly = {}, hostile = {}}
local INTERACT_FOLLOW = 4 -- CheckInteractDistance index, 28 yards

-- Phase reasons that don't matter while we can see the unit
local ignoredPhases = {}
if( Enum.PhaseReason ) then
	for _, key in pairs({"WarMode", "ChromieTime", "TimerunningHwt"}) do
		if( Enum.PhaseReason[key] ) then ignoredPhases[Enum.PhaseReason[key]] = true end
	end
end

local function isPhased(unit)
	local phase = UnitPhaseReason and Secrets.Read(UnitPhaseReason, unit)
	if( phase == nil ) then return false end
	if( ignoredPhases[phase] and UnitIsVisible(unit) ) then return false end
	return true
end

-- In range result for a list of spells: true/false, a secret boolean, or nil if no spell could check it
local function checkSpells(spells, unit)
	local result
	for i = 1, #spells do
		local inRange = IsSpellInRange(spells[i], unit)
		if( issecretvalue(inRange) ) then
			-- Can't combine a secret with the others; use it if nothing else said yes
			if( result ~= true ) then result = inRange end
			return result
		elseif( inRange == true or inRange == 1 ) then
			return true
		elseif( inRange ~= nil ) then
			result = false
		end
	end

	return result
end

-- true/false, secret boolean, or nil when nothing could tell
local function getInRange(unit)
	local spells
	if( UnitCanAssist("player", unit) ) then
		spells = rangeSpells.friendly
	elseif( UnitCanAttack("player", unit) ) then
		spells = rangeSpells.hostile
	end

	if( spells and #spells > 0 ) then
		local inRange = checkSpells(spells, unit)
		if( inRange ~= nil ) then return inRange end
	end

	-- That didn't work, but they are grouped lets try the actual API for this (40 yards, may be secret)
	if( Secrets.Read(UnitInRaid, unit) or Secrets.Read(UnitInParty, unit) ) then
		local inRange, checkedRange = UnitInRange(unit)
		if( issecretvalue(checkedRange) or issecretvalue(inRange) ) then
			return inRange
		elseif( checkedRange ) then
			return inRange and true or false
		end
	end

	-- Last resort, follow distance; this one isn't allowed on every unit in combat
	if( not InCombatLockdown() ) then
		local ok, inRange = pcall(CheckInteractDistance, unit, INTERACT_FOLLOW)
		if( ok and not issecretvalue(inRange) and inRange ~= nil ) then
			return inRange and true or false
		end
	end

	return nil
end

local function checkRange(self)
	local frame = self.parent
	local config = ShadowUF.db.profile.units[frame.unitType].range

	if( not UnitIsConnected(frame.unit) or isPhased(frame.unit) ) then
		frame:SetRangeAlpha(config.oorAlpha)
		return
	end

	local inRange = getInRange(frame.unit)
	if( issecretvalue(inRange) ) then
		-- Hand the secret straight to the frame; the combat fader owns the alpha while it's faded out
		if( not frame.disableRangeAlpha and pcall(frame.SetAlphaFromBoolean, frame, inRange, config.inAlpha, config.oorAlpha) ) then
			frame.rangeAlpha = nil
		end
	-- Nope, just show in range :(
	elseif( inRange == nil ) then
		frame:SetRangeAlpha(config.inAlpha)
	else
		frame:SetRangeAlpha(inRange and config.inAlpha or config.oorAlpha)
	end
end

-- Is this spell (name or ID) one we can use for range checks?
local function isKnownSpell(spell)
	if( not spell or spell == "" ) then return false end
	if( GetSpellInfo(spell) ) then return true end
	return IsSpellUsable(spell) and true or false
end

local function updateSpellCache(category)
	local list = rangeSpells[category]
	table.wipe(list)

	-- Custom spells from the options win
	for _, key in ipairs({category .. playerClass, category .. "Alt" .. playerClass}) do
		local spell = ShadowUF.db.profile.range[key]
		if( isKnownSpell(spell) ) then
			table.insert(list, spell)
		end
	end
	if( #list > 0 ) then return end

	local defaults = Range[category][playerClass]
	if( not defaults ) then return end

	for _, spellID in ipairs(defaults) do
		local name = GetSpellName(spellID)
		if( name and isKnownSpell(name) ) then
			table.insert(list, name)
		end
	end
end

local function createTimer(frame)
	if( not frame.range.timer ) then
		frame.range.timer = C_Timer.NewTicker(0.5, checkRange)
		frame.range.timer.parent = frame
	end
end

local function cancelTimer(frame)
	if( frame.range and frame.range.timer ) then
		frame.range.timer:Cancel()
		frame.range.timer = nil
	end
end

function Range:ForceUpdate(frame)
	if( Secrets.Read(UnitIsUnit, frame.unit, "player") ) then
		frame:SetRangeAlpha(ShadowUF.db.profile.units[frame.unitType].range.inAlpha)
		cancelTimer(frame)
	else
		createTimer(frame)
		checkRange(frame.range.timer)
	end
end

function Range:OnEnable(frame)
	if( not frame.range ) then
		frame.range = CreateFrame("Frame", nil, frame)
	end

	-- New spells or ranks learned
	frame:RegisterNormalEvent("SPELLS_CHANGED", self, "SpellChecks")
	frame:RegisterUpdateFunc(self, "ForceUpdate")

	createTimer(frame)
end

function Range:OnLayoutApplied(frame)
	self:SpellChecks(frame)
end

function Range:OnDisable(frame)
	frame:UnregisterAll(self)

	if( frame.range ) then
		cancelTimer(frame)
		frame:SetRangeAlpha(1.0)
	end
end


function Range:SpellChecks(frame)
	updateSpellCache("friendly")
	updateSpellCache("hostile")
	if( frame.range and ShadowUF.db.profile.units[frame.unitType].range.enabled ) then
		self:ForceUpdate(frame)
	end
end
