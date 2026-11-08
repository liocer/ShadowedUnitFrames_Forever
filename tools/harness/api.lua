-- Mock game API: units, auras, spells, groups. H.secretMode makes the
-- restricted APIs return secret values, the way the client does in combat.
local H = HARNESS
local S = H.secret
local apiRules = dofile((debug.getinfo(1, "S").source:match("^@(.*/)") or "./") .. "apirules.lua")
H.secretMode = false
H.lieAboutSecrets = os.getenv("LIE") == "1"
H.inCombat = false

local function maybe(v) if H.secretMode and v ~= nil then return S(v) end return v end

H.units = {
	player = {name = "Rob", class = "DRUID", classID = 11, level = 60, health = 3000, maxHealth = 4000, powerType = 0, power = {[0] = 2000, [1] = 30, [3] = 80, [4] = 3},
		maxPower = {[0] = 4000, [1] = 100, [3] = 100, [4] = 5}, guid = "Player-1-0001", race = "NightElf", sex = 3, player = true, friend = true},
	target = {name = "Hogger", class = "WARRIOR", classID = 1, level = 11, health = 500, maxHealth = 800, powerType = 1, power = {[1] = 10}, maxPower = {[1] = 100},
		guid = "Creature-0-1-2-3-448-0001", classification = "elite", enemy = true, creature = "Humanoid"},
	pet = {name = "Kitty", class = "WARRIOR", level = 58, health = 1000, maxHealth = 1500, powerType = 2, power = {[2] = 50}, maxPower = {[2] = 100}, guid = "Pet-0-1", friend = true},
	party1 = {name = "Ann", class = "PRIEST", classID = 5, level = 60, health = 2000, maxHealth = 2500, powerType = 0, power = {[0] = 3000}, maxPower = {[0] = 5000}, guid = "Player-1-0002", player = true, friend = true},
	party2 = {name = "Bob", class = "ROGUE", classID = 4, level = 59, health = 0, maxHealth = 2500, powerType = 3, power = {[3] = 100}, maxPower = {[3] = 100}, guid = "Player-1-0003", player = true, friend = true, dead = true},
	focus = {name = "Ann", class = "PRIEST", classID = 5, level = 60, health = 2000, maxHealth = 2500, powerType = 0, power = {[0] = 3000}, maxPower = {[0] = 5000}, guid = "Player-1-0002", player = true, friend = true},
}
H.units.targettarget = H.units.player
H.units.raid1 = H.units.player
H.units.raid2 = H.units.party1
H.units.raid3 = H.units.party2
H.units.party1target = H.units.target
H.units.pettarget = H.units.target
H.units.focustarget = H.units.target

-- unit tokens that resolve through "target" chains
local function U(unit)
	if type(unit) ~= "string" then
		if H.secretUnitArg and issecretvalue(unit) then return nil end
		return nil
	end
	unit = unit:lower()
	if unit == "mouseover" then return nil end
	local u = H.units[unit]
	if not u and unit:match("target$") then u = H.units.target end
	return u
end
H.U = U

-- wraps an API so passing it a secret when the client wouldn't allow that errors
local function guard(name, fn)
	local rule = apiRules[name]
	if rule and rule.args ~= "AllowedWhenTainted" then
		return function(...)
			for i = 1, select("#", ...) do
				if issecretvalue((select(i, ...))) then error(name .. " doesn't accept secret arguments from addons", 2) end
			end
			return fn(...)
		end
	end
	return fn
end
H.guard = guard

local api = {}
function api.UnitExists(u) return U(u) ~= nil end
function api.UnitIsVisible(u) return U(u) ~= nil end
function api.UnitGUID(u) local x = U(u) return x and maybe(x.guid) end
function api.UnitName(u) local x = U(u) if x then return maybe(x.name), nil end end
function api.UnitNameUnmodified(u) return api.UnitName(u) end
function api.UnitFullName(u) return api.UnitName(u) end
function api.GetUnitName(u, server) local x = U(u) return x and maybe(x.name) end
function api.UnitPVPName(u) return api.UnitName(u) end
function api.UnitClass(u) local x = U(u) if x then return maybe(x.class:sub(1, 1) .. x.class:sub(2):lower()), maybe(x.class), maybe(x.classID) end end
function api.UnitClassBase(u) local x = U(u) if x then return maybe(x.class), maybe(x.classID) end end
function api.UnitRace(u) local x = U(u) if x then return maybe(x.race or "Human"), maybe(x.race or "Human"), maybe(1) end end
function api.UnitSex(u) return maybe(2) end
function api.UnitLevel(u) local x = U(u) return x and x.level or 0 end
function api.UnitEffectiveLevel(u) return api.UnitLevel(u) end
function api.UnitClassification(u) local x = U(u) return x and x.classification or "normal" end
function api.UnitCreatureType(u) local x = U(u) return x and maybe(x.creature), x and maybe(1) end
function api.UnitCreatureFamily(u) local x = U(u) return x and maybe(x.family), nil end
function api.UnitHealth(u) local x = U(u) return x and maybe(x.health) or 0 end
function api.UnitHealthMax(u) local x = U(u) return x and maybe(x.maxHealth) or 0 end
function api.UnitHealthMissing(u) local x = U(u) return x and maybe(x.maxHealth - x.health) or 0 end
function api.UnitHealthPercent(u, pred, curve)
	local x = U(u)
	local p = x and x.maxHealth > 0 and x.health / x.maxHealth or 0
	if curve then return curve:Evaluate(p) end
	return maybe(p)
end
function api.UnitPowerType(u) local x = U(u) if x then return x.powerType, ({[0] = "MANA", [1] = "RAGE", [2] = "FOCUS", [3] = "ENERGY"})[x.powerType] or "MANA" end return 0, "MANA" end
function api.UnitPower(u, t) local x = U(u) if not x then return 0 end t = t or x.powerType return maybe(x.power[t] or 0) end
function api.UnitPowerMax(u, t) local x = U(u) if not x then return 0 end t = t or x.powerType return maybe(x.maxPower[t] or 0) end
function api.UnitPowerMissing(u, t) local x = U(u) if not x then return 0 end t = t or x.powerType return maybe((x.maxPower[t] or 0) - (x.power[t] or 0)) end
function api.UnitPowerPercent(u, t, unmod, curve)
	local x = U(u)
	if not x then return 0 end
	t = t or x.powerType
	local m = x.maxPower[t] or 0
	local p = m > 0 and (x.power[t] or 0) / m or 0
	if curve then return curve:Evaluate(p) end
	return maybe(p)
end
function api.UnitPowerBarID() return 0 end
function api.UnitPartialPower() return maybe(0) end
function api.GetComboPoints() return maybe(H.units.player.power[4] or 0) end
function api.UnitGetIncomingHeals(u, healer) return U(u) and maybe(healer and 100 or 300) end
function api.UnitGetTotalAbsorbs(u) return U(u) and maybe(50) end
function api.UnitGetTotalHealAbsorbs(u) return U(u) and maybe(0) end
function api.UnitIsDead(u) local x = U(u) return x and x.dead or false end
function api.UnitIsGhost(u) return false end
function api.UnitIsDeadOrGhost(u) local x = U(u) return x and x.dead or false end
function api.UnitIsFeignDeath() return false end
function api.UnitIsConnected(u) return U(u) ~= nil end
function api.UnitIsAFK() return false end
function api.UnitIsDND() return false end
function api.UnitIsPlayer(u) local x = U(u) return x and x.player or false end
function api.UnitPlayerControlled(u) local x = U(u) return x and (x.player or u == "pet") or false end
function api.UnitIsUnit(a, b) local x, y = U(a), U(b) return maybe(x ~= nil and x == y) end
function api.UnitIsFriend(a, b) local x, y = U(a), U(b) return (x and y and ((x.friend and y.friend) or (x.enemy and y.enemy))) and true or false end
function api.UnitIsEnemy(a, b) local x, y = U(a), U(b) return (x and y and ((x.friend and y.enemy) or (x.enemy and y.friend))) and true or false end
function api.UnitCanAttack(a, b) return api.UnitIsEnemy(a, b) end
function api.UnitCanAssist(a, b) return api.UnitIsFriend(a, b) end
function api.UnitCanCooperate(a, b) return api.UnitIsFriend(a, b) end
function api.UnitReaction(a, b) local x = U(b) if not x then return nil end return x.enemy and 2 or 5 end
function api.UnitIsTapDenied() return false end
function api.UnitIsPVP() return maybe(false) end
function api.UnitIsPVPFreeForAll() return false end
function api.UnitFactionGroup() return "Alliance", "Alliance" end
function api.UnitAffectingCombat() return H.inCombat end
function api.UnitThreatSituation(u) return maybe(U(u) and 0 or nil) end
function api.UnitDetailedThreatSituation() return maybe(false), maybe(0), maybe(0), maybe(0), maybe(0) end
function api.UnitInRange(u) return maybe(true), maybe(true) end
function api.CheckInteractDistance() return true end
function api.UnitInParty(u) return u == "party1" or u == "party2" or u == "player" end
function api.UnitInRaid(u) return maybe(nil) end
function api.UnitIsGroupLeader(u) return maybe(u == "player") end
function api.UnitIsGroupAssistant() return maybe(false) end
function api.UnitIsRaidOfficer() return maybe(false) end
function api.UnitGroupRolesAssigned() return maybe("NONE") end
function api.UnitHasVehicleUI() return false end
function api.UnitInVehicle() return false end
function api.UnitUsingVehicle() return false end
function api.UnitHasIncomingResurrection() return false end
function api.UnitIsCharmed() return maybe(false) end
function api.UnitIsPossessed() return maybe(false) end
function api.UnitPhaseReason() return maybe(nil) end
function api.UnitInPhase() return true end
function api.UnitIsOtherPlayersPet() return false end
function api.UnitIsQuestBoss() return false end
function api.UnitIsWildBattlePet() return false end
function api.UnitIsBattlePetCompanion() return false end
function api.UnitIsMercenary() return false end
function api.UnitIsTrivial() return false end
function api.UnitSelectionColor() return 1, 0, 0, 1 end
function api.UnitXP() return 1000 end
function api.UnitXPMax() return 5000 end
function api.GetXPExhaustion() return 500 end
function api.IsResting() return false end
function api.GetPetExperience() return 100, 1000 end
function api.GetPetHappiness() return 3, 0, 0 end
function api.HasPetUI() return true, true end
function api.UnitCastingInfo(u) return nil end
function api.UnitChannelInfo(u) return nil end
function api.GetRaidTargetIndex() return maybe(nil) end
function api.GetReadyCheckStatus() return nil end
function api.GetPartyAssignment() return false end
function api.GetLootMethod() return "group", 0, nil end
function api.IsInGroup() return true end
function api.IsInRaid() return false end
function api.GetNumGroupMembers() return 3 end
function api.GetNumSubgroupMembers() return 2 end
function api.GetRaidRosterInfo(i) return nil end
function api.IsInInstance() return false, "none" end
function api.GetInstanceInfo() return "Azeroth", "none", 0, "", 5, 0, false, 0, 0 end
function api.GetZonePVPInfo() return nil end
function api.UnitTokenFromGUID() return nil end
function api.GetShapeshiftForm() return 0 end
function api.GetShapeshiftFormID() return nil end
function api.GetTotemInfo(i) return false, "", 0, 0, nil end
function api.GetWeaponEnchantInfo() return false end
function api.GetInventoryItemTexture() return nil end
function api.GetInventorySlotInfo(n) return 16 end
function api.InCombatLockdown() return H.inCombat end
function api.GetCVar(n) return H.cvars[n] end
function api.GetCVarBool(n) return H.cvars[n] == "1" end
function api.SetCVar(n, v) H.cvars[n] = tostring(v) end
H.cvars = {}
function api.GetLocale() return "enUS" end
function api.GetBuildInfo() return "1.60.1", "70862", "Nov 1 2026", 16001 end
function api.GetRealmName() return "Forever" end
function api.GetNormalizedRealmName() return "Forever" end
function api.GetCurrentRegion() return 3 end
function api.GetCurrentRegionName() return "EU" end
function api.GetFramerate() return 60 end
function api.GetScreenWidth() return 1920 end
function api.GetScreenHeight() return 1080 end
function api.GetPhysicalScreenSize() return 1920, 1080 end
function api.GetCursorPosition() return 0, 0 end
function api.IsShiftKeyDown() return false end
function api.IsControlKeyDown() return false end
function api.IsAltKeyDown() return false end
function api.IsModifierKeyDown() return false end
function api.IsLoggedIn() return true end
function api.GetMaxPlayerLevel() return 60 end
function api.GetMaxLevelForPlayerExpansion() return 60 end
function api.IsXPUserDisabled() return false end
function api.IsPlayerAtEffectiveMaxLevel() return false end
function api.GetActiveTalentGroup() return 1 end
function api.GetNumSpecGroups() return 2 end
function api.GetNumTalentGroups() return 2 end
function api.PlaySound() end
function api.GetMouseFoci() return {} end
function api.GetMouseFocus() return nil end
function api.RegisterStateDriver() end
function api.UnregisterStateDriver() end
function api.RegisterAttributeDriver() end
function api.UnregisterAttributeDriver() end
function api.RegisterUnitWatch(f) end
function api.UnregisterUnitWatch(f) end
function api.SecureHandlerWrapScript() end
function api.SecureHandlerUnwrapScript() end
function api.SecureHandlerSetFrameRef(f, n, r) f:SetFrameRef(n, r) end
function api.SecureHandlerExecute() end
function api.SecureCmdOptionParse() return nil end
function api.SecureButton_GetUnit(self) return self:GetAttribute("unit") end
function api.SecureButton_GetModifiedUnit(self) return self:GetAttribute("unit") end
function api.ToggleDropDownMenu() end
function api.UnitPopup_OpenMenu() end
function api.UnitFrame_OnEnter() end
function api.UnitFrame_OnLeave() end
function api.UnitFrame_UpdateTooltip() end
function api.GameTooltip_SetDefaultAnchor() end
function api.GetSpellTexture() return 136243 end
function api.GetItemInfo() return nil end
function api.GetAddOnMetadata(name, field) return "1.0" end
function api.StaticPopup_Show() end
function api.StaticPopup_Hide() end
function api.InterfaceOptions_AddCategory() end
function api.UIDropDownMenu_Initialize() end
function api.CombatFeedback_Initialize() end
function api.CombatFeedback_OnCombatEvent() end
function api.CombatFeedback_OnUpdate() end
function api.SetPortraitTexture() end
function api.SetRaidTargetIconTexture() end
function api.GetTexCoordsForRole() return 0, 1, 0, 1 end
function api.IsAddOnLoaded(n) return H.loadedAddons[n] or false end
function api.AbbreviateNumbers(n) if issecretvalue(n) then return S(tostring(H.unwrap(n))) end return tostring(n) end
function api.AbbreviateLargeNumbers(n) return api.AbbreviateNumbers(n) end
function api.BreakUpLargeNumbers(n) return api.AbbreviateNumbers(n) end
function api.FormatLargeNumber(n) return api.AbbreviateNumbers(n) end
function api.CreateColor(r, g, b, a) return CreateColorMixin(r, g, b, a) end
function api.GetClassColor(c) local col = RAID_CLASS_COLORS[c] if col then return col.r, col.g, col.b, col.colorStr end return 1, 1, 1, "ffffffff" end
function api.GetDifficultyColor(level) return {r = 1, g = 1, b = 0} end
function api.GetCreatureDifficultyColor(level) return {r = 1, g = 1, b = 0} end
function api.GetQuestDifficultyColor(level) return {r = 1, g = 1, b = 0} end
function api.ShowBossFrameWhenUninteractable() return false end
function api.UnitAura() error("UnitAura doesn't exist on this client") end
H.loadedAddons = {}

for name, fn in pairs(api) do _G[name] = guard(name, fn) end

-- ColorMixin
local ColorMixin = {}
ColorMixin.__index = ColorMixin
function ColorMixin:GetRGB() return self.r, self.g, self.b end
function ColorMixin:GetRGBA() return self.r, self.g, self.b, self.a end
function ColorMixin:GetRGBAsBytes() return self.r * 255, self.g * 255, self.b * 255 end
function ColorMixin:GenerateHexColor() return "ffffffff" end
function ColorMixin:GenerateHexColorMarkup() return "|cffffffff" end
function ColorMixin:WrapTextInColorCode(t) return "|cffffffff" .. t .. "|r" end
function ColorMixin:SetRGB(r, g, b) self.r, self.g, self.b = r, g, b end
function ColorMixin:SetRGBA(r, g, b, a) self.r, self.g, self.b, self.a = r, g, b, a end
function ColorMixin:IsEqualTo(o) return self.r == o.r and self.g == o.g and self.b == o.b end
function CreateColorMixin(r, g, b, a) return setmetatable({r = r, g = g, b = b, a = a or 1, colorStr = "ffffffff"}, ColorMixin) end
CreateColor = CreateColorMixin
_G.ColorMixin = ColorMixin
function CreateFromMixins(...) local t = {} for i = 1, select("#", ...) do for k, v in pairs((select(i, ...))) do t[k] = v end end return t end
function Mixin(t, ...) for i = 1, select("#", ...) do for k, v in pairs((select(i, ...))) do t[k] = v end end return t end
CreateAndInitFromMixin = function(m, ...) local t = CreateFromMixins(m) if t.Init then t:Init(...) end return t end

-- Curves
local Curve = {}
Curve.__index = Curve
function Curve:SetType(t) self.type = t end
function Curve:GetType() return self.type end
function Curve:AddPoint(x, y) table.insert(self.points, {x = x, y = y}) table.sort(self.points, function(a, b) return a.x < b.x end) end
function Curve:ClearPoints() self.points = {} end
function Curve:GetPointCount() return #self.points end
function Curve:HasSecretValues() return false end
function Curve:Evaluate(x)
	local secretIn = issecretvalue(x)
	x = H.unwrap(x)
	local pts = self.points
	if #pts == 0 then return 0 end
	local y
	if x <= pts[1].x then y = pts[1].y
	elseif x >= pts[#pts].x then y = pts[#pts].y
	else
		for i = 1, #pts - 1 do
			local a, b = pts[i], pts[i + 1]
			if x >= a.x and x <= b.x then
				if self.type == 1 then y = a.y
				else
					local t = (x - a.x) / (b.x - a.x)
					if type(a.y) == "table" then
						y = CreateColor(a.y.r + (b.y.r - a.y.r) * t, a.y.g + (b.y.g - a.y.g) * t, a.y.b + (b.y.b - a.y.b) * t, 1)
					else
						y = a.y + (b.y - a.y) * t
					end
				end
				break
			end
		end
	end
	if H.secretMode or secretIn then
		if type(y) == "table" then return CreateColor(S(y.r), S(y.g), S(y.b), S(y.a or 1)) end
		return S(y)
	end
	return y
end
function Curve:EvaluateUnpacked(x) local c = self:Evaluate(x) return c.r, c.g, c.b, c.a end
local function newCurve() return setmetatable({points = {}, type = 0}, Curve) end
C_CurveUtil = {CreateCurve = newCurve, CreateColorCurve = newCurve,
	EvaluateColorFromBoolean = function(b, t, f) return t end, EvaluateColorValueFromBoolean = function(b, t, f) return t end}

-- Duration objects
local Duration = {}
Duration.__index = Duration
function Duration:GetRemainingDuration() return maybe(5) end
function Duration:GetTotalDuration() return maybe(10) end
function Duration:GetStartTime() return maybe(H.time) end
function Duration:GetEndTime() return maybe(H.time + 10) end
function Duration:IsZero() return maybe(false) end
function Duration:HasSecretValues() return H.secretMode end
function Duration:SetTimeFromStart() end
function Duration:SetTimeSpan() end
function Duration:Reset() end
C_DurationUtil = {CreateDuration = function() return setmetatable({}, Duration) end}

-- Auras: player has Mark of the Wild + Rejuvenation; target has a debuff
H.auras = {
	player = {
		{name = "Mark of the Wild", icon = 136078, applications = 0, dispelName = "Magic", duration = 1800, expirationTime = 2800, sourceUnit = "player", isHelpful = true, spellId = 9885, auraInstanceID = 1, isFromPlayerOrPlayerPet = true, canApplyAura = true, isStealable = false, nameplateShowPersonal = false, isBossAura = false, isRaid = false, charges = 0, maxCharges = 0, timeMod = 1},
		{name = "Rejuvenation", icon = 136081, applications = 0, duration = 12, expirationTime = 1010, sourceUnit = "player", isHelpful = true, spellId = 25299, auraInstanceID = 2, isFromPlayerOrPlayerPet = true, canApplyAura = true, isBossAura = false, isRaid = true, charges = 0, maxCharges = 0, timeMod = 1},
		{name = "Curse of Agony", icon = 136139, applications = 2, dispelName = "Curse", duration = 24, expirationTime = 1020, sourceUnit = "target", isHarmful = true, spellId = 11713, auraInstanceID = 3, isFromPlayerOrPlayerPet = false, isBossAura = false, isRaid = true, charges = 0, maxCharges = 0, timeMod = 1},
	},
	target = {
		{name = "Rake", icon = 132122, applications = 0, duration = 9, expirationTime = 1005, sourceUnit = "player", isHarmful = true, spellId = 9904, auraInstanceID = 10, isFromPlayerOrPlayerPet = true, isBossAura = false, isRaid = false, charges = 0, maxCharges = 0, timeMod = 1},
	},
}
-- Like the real client: a tainted read of a secret aura raises an error
local function secretAura(a)
	if not a then return nil end
	if not H.secretMode then return a end
	error("GetAuraDataByIndex(): Auras cannot be accessed when secret while tainted by 'ShadowedUnitFrames_Forever'", 3)
end
local function aurasFor(unit, filter)
	local list = H.auras[unit] or H.auras[unit and unit:match("^party%d") and "player" or ""] or {}
	local out = {}
	local wantHelp = filter and filter:find("HELPFUL")
	local wantHarm = filter and filter:find("HARMFUL")
	for _, a in ipairs(list) do
		if (not wantHelp or a.isHelpful) and (not wantHarm or a.isHarmful) and (not (filter and filter:find("PLAYER")) or a.isFromPlayerOrPlayerPet)
			and (not (filter and filter:find("RAID")) or a.isRaid) then
			table.insert(out, a)
		end
	end
	return out
end
C_UnitAuras = {
	GetAuraDataByIndex = function(unit, i, filter) return secretAura(aurasFor(unit, filter or "HELPFUL")[i]) end,
	GetBuffDataByIndex = function(unit, i, filter) return secretAura(aurasFor(unit, "HELPFUL" .. (filter and ("|" .. filter) or ""))[i]) end,
	GetDebuffDataByIndex = function(unit, i, filter) return secretAura(aurasFor(unit, "HARMFUL" .. (filter and ("|" .. filter) or ""))[i]) end,
	GetAuraDataByAuraInstanceID = function(unit, id)
		for _, a in ipairs(H.auras[unit] or {}) do if a.auraInstanceID == id then return secretAura(a) end end
	end,
	GetUnitAuras = function(unit, filter, max) local out = {} for i, a in ipairs(aurasFor(unit, filter)) do out[i] = secretAura(a) end return out end,
	GetUnitAuraInstanceIDs = function(unit, filter) local out = {} for i, a in ipairs(aurasFor(unit, filter)) do out[i] = a.auraInstanceID end return out end,
	GetAuraSlots = function() return nil end,
	GetAuraDataBySlot = function() return nil end,
	GetAuraDataBySpellName = function(unit, name, filter)
		if H.secretMode then error("GetAuraDataBySpellName requires non-secret aura") end
		for _, a in ipairs(aurasFor(unit, filter)) do if a.name == name then return a end end
	end,
	GetPlayerAuraBySpellID = function(id) for _, a in ipairs(H.auras.player) do if a.spellId == id then return secretAura(a) end end end,
	GetUnitAuraBySpellID = function(unit, id) for _, a in ipairs(H.auras[unit] or {}) do if a.spellId == id then return secretAura(a) end end end,
	IsAuraFilteredOutByInstanceID = function(unit, id, filter)
		for _, a in ipairs(aurasFor(unit, filter)) do if a.auraInstanceID == id then return false end end
		return true
	end,
	GetAuraDuration = function(unit, id) return setmetatable({}, Duration) end,
	GetAuraApplicationDisplayCount = function(unit, id, minC, maxC) return maybe("") end,
	GetAuraDispelTypeColor = function(unit, id, curve) return CreateColor(maybe(1), maybe(0), maybe(0), maybe(1)) end,
	DoesAuraHaveExpirationTime = function() return maybe(true) end,
	GetAuraBaseDuration = function() return maybe(10) end,
	CancelAuraByAuraInstanceID = function() end,
	WantsAlteredForm = function() return false end,
	GetCooldownAuraBySpellID = function() return nil end,
	AuraIsPrivate = function() return false end,
}
AuraUtil = {
	UnpackAuraData = function(a)
		if not a then return nil end
		return a.name, a.icon, a.applications, a.dispelName, a.duration, a.expirationTime, a.sourceUnit, a.isStealable, a.nameplateShowPersonal, a.spellId,
			a.canApplyAura, a.isBossAura, a.isFromPlayerOrPlayerPet, a.nameplateShowAll, a.timeMod
	end,
	ForEachAura = function(unit, filter, max, fn, usePacked)
		for i, a in ipairs(aurasFor(unit, filter)) do
			local stop
			if usePacked then stop = fn(secretAura(a)) else stop = fn(AuraUtil.UnpackAuraData(secretAura(a))) end
			if stop then break end
		end
	end,
	FindAuraByName = function(name, unit, filter)
		for _, a in ipairs(aurasFor(unit, filter)) do if a.name == name then return AuraUtil.UnpackAuraData(secretAura(a)) end end
	end,
	AuraUpdateChangedType = {None = 0, Debuff = 1, Buff = 2, Dispel = 3},
}

C_Secrets = {
	HasSecretRestrictions = function() return true end,
	ShouldAurasBeSecret = function() return H.secretMode end,
	ShouldUnitAuraIndexBeSecret = function() return H.secretMode and not H.lieAboutSecrets end,
	ShouldUnitAuraInstanceBeSecret = function() return H.secretMode and not H.lieAboutSecrets end,
	ShouldSpellAuraBeSecret = function() return H.secretMode end,
	ShouldUnitSpellCastingBeSecret = function() return H.secretMode end,
	ShouldUnitIdentityBeSecret = function() return H.secretMode end,
	ShouldUnitHealthBeSecret = function() return H.secretMode end,
	ShouldUnitPowerBeSecret = function() return H.secretMode end,
	ShouldCooldownsBeSecret = function() return H.secretMode end,
	ShouldTotemSlotBeSecret = function() return H.secretMode end,
	ShouldTotemSpellBeSecret = function() return H.secretMode end,
	GetSpellAuraSecrecy = function() return H.secretMode and 2 or 0 end,
	GetPowerTypeSecrecy = function() return H.secretMode and 2 or 0 end,
	CanCompareUnitTokens = function() return not H.secretMode end,
}

-- Spells
local knownSpells = {
	[774] = "Rejuvenation", [25299] = "Rejuvenation", [5185] = "Healing Touch", [5176] = "Wrath", [2782] = "Remove Curse", [8946] = "Cure Poison",
	[2893] = "Abolish Poison", [1082] = "Claw", [9849] = "Claw", [6795] = "Growl", [33786] = "Cyclone",
}
C_Spell = {
	GetSpellInfo = function(id)
		local name = knownSpells[id]
		if type(id) == "string" then for sid, n in pairs(knownSpells) do if n == id then name, id = n, sid end end end
		if not name then return nil end
		return {name = name, iconID = 136243, spellID = id, castTime = 0, minRange = 0, maxRange = 30, originalIconID = 136243}
	end,
	GetSpellName = function(id) return knownSpells[id] end,
	GetSpellTexture = function(id) return 136243 end,
	GetSpellPowerCost = function(id) return {{type = 0, cost = maybe(100), minCost = 100, name = "MANA"}} end,
	IsSpellInRange = function(spell, unit) return maybe(true) end,
	SpellHasRange = function() return true end,
	DoesSpellExist = function(id) return knownSpells[id] ~= nil end,
	GetSpellCooldown = function() return {startTime = 0, duration = 0, isEnabled = true, modRate = 1} end,
	IsSpellUsable = function() return true, false end,
	GetSpellIDForSpellIdentifier = function(id) return id end,
	GetSpellLink = function() return nil end,
	GetSpellDescription = function() return "" end,
}
C_SpellBook = {
	IsSpellKnown = function(id) return id == 2782 or id == 8946 or id == 5185 or id == 5176 or id == 1082 end,
	IsSpellInSpellBook = function(id) return C_SpellBook.IsSpellKnown(id) end,
	IsSpellKnownOrInSpellBook = function(id) return C_SpellBook.IsSpellKnown(id) end,
	GetSpellBookItemInfo = function() return nil end,
	FindSpellBookSlotForSpell = function() return nil end,
	GetNumSpellBookSkillLines = function() return 0 end,
}
C_AddOns = {
	LoadAddOn = function(name) return H.loadAddon(name) end,
	IsAddOnLoaded = function(name) return H.loadedAddons[name] or false, H.loadedAddons[name] or false end,
	GetAddOnMetadata = function(name, field) return field == "Version" and "1.0.0-forever" or "x" end,
	GetAddOnInfo = function(name) return name, name, "", true, nil, "INSECURE", false end,
	GetAddOnEnableState = function() return 2 end,
	EnableAddOn = function() end, DisableAddOn = function() end,
	IsAddOnLoadOnDemand = function() return true end,
	GetNumAddOns = function() return 2 end,
	DoesAddOnExist = function(name) return name == "ShadowedUnitFrames_Forever" or name == "ShadowedUF_Forever_Options" end,
}
C_PartyInfo = {GetLootMethod = function() return 0, nil, nil end, IsPartyInJoinableInstance = function() return false end, GetMinLevel = function() return 1 end}
C_IncomingSummon = {HasIncomingSummon = function() return false end, IncomingSummonStatus = function() return 0 end}
C_StringUtil = {
	AbbreviateNumbers = _G.AbbreviateNumbers, AbbreviateLargeNumbers = _G.AbbreviateNumbers, BreakUpLargeNumbers = _G.AbbreviateNumbers,
	TruncateWhenZero = function(n) return tostring(n) end, RoundToNearestString = function(n) return tostring(n) end, FloorToNearestString = function(n) return tostring(n) end,
	WrapString = function(infix, prefix, suffix) return (prefix or "") .. infix .. (suffix or "") end,
	StripHyperlinks = function(t) return t end,
}
C_ClassColor = {GetClassColor = function(c) local col = RAID_CLASS_COLORS[c] return col and CreateColor(col.r, col.g, col.b) end}
C_CVar = {GetCVar = GetCVar, GetCVarBool = GetCVarBool, SetCVar = SetCVar, RegisterCVar = function() end, GetCVarDefault = function() return "0" end}
C_PvP = {IsPVPMap = function() return false end, IsRatedMap = function() return false end, IsWarModeDesired = function() return false end, IsArena = function() return false end, IsBattleground = function() return false end}
C_Map = {GetBestMapForUnit = function() return 1429 end}
C_PetBattles = {IsInBattle = function() return false end}
C_UnitPowerBarAlt = nil
C_LossOfControl = {GetActiveLossOfControlDataCount = function() return 0 end}
C_GameRules = {GetActiveGameMode = function() return 0 end, IsHardcoreActive = function() return false end}
C_Texture = {GetAtlasInfo = function() return {file = 1, leftTexCoord = 0, rightTexCoord = 1, topTexCoord = 0, bottomTexCoord = 1, width = 16, height = 16} end}
C_UI = {Reload = function() end}
C_SpecializationInfo = {GetSpecialization = nil, GetActiveSpecGroup = function() return 1 end, CanPlayerUseTalentUI = function() return true end, GetNumSpecializationsForClassID = function() return 0 end}
C_ChatInfo = {RegisterAddonMessagePrefix = function() return true end}
C_Item = {GetItemInfo = function() return nil end, GetItemIconByID = function() return 0 end}
C_EncodingUtil = nil
C_Container = {}
C_Reputation = {GetWatchedFactionData = function() return nil end}
GetWatchedFactionInfo = nil

-- Constants
Enum = setmetatable({
	PowerType = {HealthCost = -2, None = -1, Mana = 0, Rage = 1, Focus = 2, Energy = 3, ComboPoints = 4, Runes = 5, RunicPower = 6, SoulShards = 7, LunarPower = 8,
		HolyPower = 9, Alternate = 10, Maelstrom = 11, Chi = 12, Insanity = 13, ArcaneCharges = 16, Fury = 17, Pain = 18, Essence = 19, NumPowerTypes = 26},
	LuaCurveType = {Linear = 0, Step = 1, Cosine = 2, Cubic = 3},
	StatusBarInterpolation = {Immediate = 0, ExponentialEaseOut = 1},
	StatusBarTimerDirection = {ElapsedTime = 0, RemainingTime = 1},
	UnitDamageAbsorbClampMode = {}, UnitHealAbsorbClampMode = {}, UnitIncomingHealClampMode = {}, UnitHealAbsorbMode = {}, UnitMaximumHealthMode = {},
	SecretAspect = {},
	PhaseReason = {Phasing = 0, Sharding = 1, WarMode = 2, ChromieTime = 3, TimerunningHwt = 4},
	SummonStatus = {None = 0, Pending = 1, Accepted = 2, Declined = 3},
	GameMode = {Standard = 0, Plunderstorm = 1, WoWHack = 2},
	TooltipDataType = {Unit = 2},
}, {__index = function(t, k) local e = setmetatable({}, {__index = function() return 0 end}) rawset(t, k, e) return e end})

RAID_CLASS_COLORS = {}
for c, rgb in pairs({WARRIOR = {0.78, 0.61, 0.43}, MAGE = {0.25, 0.78, 0.92}, ROGUE = {1, 0.96, 0.41}, DRUID = {1, 0.49, 0.04}, HUNTER = {0.67, 0.83, 0.45},
	SHAMAN = {0, 0.44, 0.87}, PRIEST = {1, 1, 1}, WARLOCK = {0.53, 0.53, 0.93}, PALADIN = {0.96, 0.55, 0.73}}) do
	RAID_CLASS_COLORS[c] = CreateColor(rgb[1], rgb[2], rgb[3])
	RAID_CLASS_COLORS[c].colorStr = "ffffffff"
end
CLASS_SORT_ORDER = {"WARRIOR", "PALADIN", "PRIEST", "SHAMAN", "DRUID", "ROGUE", "MAGE", "WARLOCK", "HUNTER"}
LOCALIZED_CLASS_NAMES_MALE, LOCALIZED_CLASS_NAMES_FEMALE = {}, {}
for _, c in ipairs(CLASS_SORT_ORDER) do LOCALIZED_CLASS_NAMES_MALE[c] = c:sub(1, 1) .. c:sub(2):lower() LOCALIZED_CLASS_NAMES_FEMALE[c] = LOCALIZED_CLASS_NAMES_MALE[c] end
CLASS_ICON_TCOORDS = {}
for _, c in ipairs(CLASS_SORT_ORDER) do CLASS_ICON_TCOORDS[c] = {0, 0.25, 0, 0.25} end
PowerBarColor = {MANA = {r = 0, g = 0, b = 1}, RAGE = {r = 1, g = 0, b = 0}, FOCUS = {r = 1, g = 0.5, b = 0.25}, ENERGY = {r = 1, g = 1, b = 0},
	COMBO_POINTS = {r = 1, g = 0.96, b = 0.41}, HAPPINESS = {r = 0, g = 1, b = 1}, AMMOSLOT = {r = 0.8, g = 0.6, b = 0}, FUEL = {r = 0, g = 0.55, b = 0.5}}
PowerBarColor[0], PowerBarColor[1], PowerBarColor[2], PowerBarColor[3], PowerBarColor[4] = PowerBarColor.MANA, PowerBarColor.RAGE, PowerBarColor.FOCUS, PowerBarColor.ENERGY, PowerBarColor.COMBO_POINTS
DEBUFF_TYPE_COLORS = nil
FACTION_BAR_COLORS = {}
for i = 1, 8 do FACTION_BAR_COLORS[i] = {r = 1, g = 1, b = 0} end
MAX_PARTY_MEMBERS, MAX_RAID_MEMBERS, MAX_BOSS_FRAMES, MAX_COMBO_POINTS, MAX_TOTEMS, NUM_RAID_GROUPS = 4, 40, 8, 5, 4, 8
MAX_RAID_GROUPS = 8
WOW_PROJECT_MAINLINE, WOW_PROJECT_CLASSIC, WOW_PROJECT_CAMELOT, WOW_PROJECT_ID = 1, 2, 18, 18
LE_EXPANSION_CLASSIC, LE_EXPANSION_MISTS_OF_PANDARIA, LE_EXPANSION_LEVEL_CURRENT = 0, 4, 0
function ClassicExpansionAtLeast() return true end
STANDARD_TEXT_FONT, UNIT_NAME_FONT, DAMAGE_TEXT_FONT, NAMEPLATE_FONT = "Fonts\\FRIZQT__.TTF", "Fonts\\FRIZQT__.TTF", "Fonts\\FRIZQT__.TTF", "Fonts\\FRIZQT__.TTF"
UISpecialFrames, UIPanelWindows = {}, {}
SlashCmdList = {}
RAID_TARGET_ICON_LIST = {}
ICON_LIST = {}
TOOLTIP_DEFAULT_COLOR = {r = 1, g = 1, b = 1}
NORMAL_FONT_COLOR = CreateColor(1, 0.82, 0)
HIGHLIGHT_FONT_COLOR = CreateColor(1, 1, 1)
RED_FONT_COLOR = CreateColor(1, 0.1, 0.1)
GREEN_FONT_COLOR = CreateColor(0.1, 1, 0.1)
GRAY_FONT_COLOR = CreateColor(0.5, 0.5, 0.5)
YELLOW_FONT_COLOR = CreateColor(1, 1, 0)
WHITE_FONT_COLOR = CreateColor(1, 1, 1)
DISABLED_FONT_COLOR = CreateColor(0.5, 0.5, 0.5)
CUSTOM_CLASS_COLORS = nil

-- Blizzard frames SUF might hide (the camelot names)
local function frame(name, parent) local f = CreateFrame("Frame", name, parent or UIParent) return f end
PlayerFrame = frame("PlayerFrame")
PlayerFrame.PlayerFrameContent = {PlayerFrameContentMain = frame(nil, PlayerFrame), PlayerFrameContentContextual = frame(nil, PlayerFrame)}
PlayerFrame.PlayerFrameContainer = frame(nil, PlayerFrame)
PetFrame = frame("PetFrame")
TargetFrame = frame("TargetFrame")
TargetFrame.totFrame = frame("TargetFrameToT", TargetFrame)
TargetFrame.spellbarAnchor = frame(nil, TargetFrame)
FocusFrame = frame("FocusFrame")
FocusFrame.totFrame = frame("FocusFrameToT", FocusFrame)
PartyFrame = frame("PartyFrame")
for i = 1, 4 do PartyFrame["MemberFrame" .. i] = frame("PartyMemberFrame" .. i, PartyFrame) end
CompactPartyFrame = frame("CompactPartyFrame")
CompactRaidFrameManager = frame("CompactRaidFrameManager")
CompactRaidFrameContainer = frame("CompactRaidFrameContainer")
function CompactRaidFrameManager_SetSetting() end
BossTargetFrameContainer = frame("BossTargetFrameContainer")
for i = 1, 8 do _G["Boss" .. i .. "TargetFrame"] = frame("Boss" .. i .. "TargetFrame") end
PlayerCastingBarFrame = frame("PlayerCastingBarFrame")
CastingBarFrame = PlayerCastingBarFrame
PetCastingBarFrame = frame("PetCastingBarFrame")
ComboFrame = frame("ComboFrame")
BuffFrame = frame("BuffFrame")
DebuffFrame = frame("DebuffFrame")
TemporaryEnchantFrame = nil
TotemFrame = nil
RuneFrame = nil
AlternatePowerBar = nil
PlayerFrameAlternatePowerBarArea = nil
EditModeManagerFrame = frame("EditModeManagerFrame")
EditModeManagerFrame.AccountSettings = {}
function EditModeManagerFrame:UseRaidStylePartyFrames() return false end
Settings = {RegisterAddOnCategory = function() end, RegisterCanvasLayoutCategory = function(f, n) return {GetID = function() return 1 end, ID = 1} end, OpenToCategory = function() end}
SettingsPanel = frame("SettingsPanel")
InterfaceOptionsFramePanelContainer = frame("InterfaceOptionsFramePanelContainer")
GameMenuFrame = frame("GameMenuFrame")
UIErrorsFrame = frame("UIErrorsFrame")
function UIErrorsFrame:AddMessage() end
MinimapCluster = frame("MinimapCluster")
StaticPopupDialogs = {}
CONFIGMODE_CALLBACKS = nil

-- Pools on Blizzard frames
local function pool(members)
	return {EnumerateActive = function() local i = 0 return function() i = i + 1 if members[i] then return members[i], true end end end,
		ReleaseAll = function() end, Acquire = function() return CreateFrame("Button") end, GetNumActive = function() return #members end}
end
PartyFrame.PartyMemberFramePool = pool({PartyFrame.MemberFrame1, PartyFrame.MemberFrame2, PartyFrame.MemberFrame3, PartyFrame.MemberFrame4})
function CreateFramePool() return pool({}) end
function CreateObjectPool() return pool({}) end
COMBATFEEDBACK_FADEINTIME, COMBATFEEDBACK_HOLDTIME, COMBATFEEDBACK_FADEOUTTIME = 0.2, 0.7, 0.3
