--[[
	Aura indicators: small corner squares/icons that track specific auras by name or spell ID,
	plus "boss" and "curable" catch-all filters. Originally by Shadowed (Shadowed Unit Frames),
	ported to WoW Forever.

	Secret values: specific auras are matched by name/spell ID, which only works while the
	aura can be read (out of combat, many NPCs, spells the game never hides), or for auras we
	saw before they turned secret (cached by aura instance ID, see auras.lua). The "curable"
	filter uses the game's "HARMFUL|RAID" filter (debuffs the player can dispel) and works in
	combat. "Missing" indicators only show when we can be sure the aura is missing.
	Configured spell IDs also match other ranks of the same spell (by spell name), since
	Classic spells have one ID per rank.
]]
local Indicators = {}
ShadowUF:RegisterModule(Indicators, "auraIndicators", ShadowUF.L["Aura indicators"])

Indicators.auraFilters = {"boss", "curable"}

local GetSpellTexture = C_Spell.GetSpellTexture
local GetSpellName = C_Spell.GetSpellName
local issecretvalue = issecretvalue or function() return false end

Indicators.auraConfig = setmetatable({}, {
	__index = function(tbl, index)
		local aura = ShadowUF.db.profile.auraIndicators.auras[tostring(index)]
		if( not aura ) then
			tbl[index] = false
		else
			local func, msg = loadstring("return " .. aura)
			if( func ) then
				func = func()
			elseif( msg ) then
				error(msg, 3)
			end

			tbl[index] = func
			if( not tbl[index].group ) then tbl[index].group = "Miscellaneous" end
		end

		return tbl[index]
end})

-- Classic-era default auras, replacing upstream's retail list (Monk, Hellfire Citadel, ...).
-- Keys are the rank 1 spell ID; every rank matches through the spell name.
-- indicator = "" means the aura is listed but not shown until the user picks an indicator.
Indicators.defaultAuras = {
	-- Priest
	["139"] = [[{r=0.23921568627451, group="Priest", indicator="tr", g=1, player=true, alpha=1, duration=true, b=0.39607843137255, priority=10, icon=false, iconTexture="Interface\\Icons\\Spell_Holy_Renew"}]],
	["17"] = [[{r=1, group="Priest", indicator="tl", g=0.41960784313725, player=false, alpha=1, duration=true, b=0.5843137254902, priority=20, icon=false, iconTexture="Interface\\Icons\\Spell_Holy_PowerWordShield"}]],
	["6788"] = [[{b=0.29019607843137, group="Priest", indicator="tl", alpha=1, player=false, g=0.56862745098039, duration=true, r=0.83921568627451, priority=10, icon=false, iconTexture="Interface\\Icons\\Spell_Holy_AshesToAshes"}]],
	["1243"] = [[{r=1, group="Priest", indicator="", g=1, b=1, alpha=1, priority=0, iconTexture="Interface\\Icons\\Spell_Holy_WordFortitude"}]],
	["21562"] = [[{r=1, group="Priest", indicator="", g=1, b=1, alpha=1, priority=0, iconTexture="Interface\\Icons\\Spell_Holy_PrayerOfFortitude"}]],
	["14752"] = [[{r=0.8, group="Priest", indicator="", g=0.8, b=1, alpha=1, priority=0, iconTexture="Interface\\Icons\\Spell_Holy_DivineSpirit"}]],
	["27681"] = [[{r=0.8, group="Priest", indicator="", g=0.8, b=1, alpha=1, priority=0, iconTexture="Interface\\Icons\\Spell_Holy_PrayerofSpirit"}]],
	["976"] = [[{r=0.5, group="Priest", indicator="", g=0, b=0.5, alpha=1, priority=0, iconTexture="Interface\\Icons\\Spell_Shadow_AntiShadow"}]],
	["27683"] = [[{r=0.5, group="Priest", indicator="", g=0, b=0.5, alpha=1, priority=0, iconTexture="Interface\\Icons\\Spell_Holy_PrayerofShadowProtection"}]],
	["6346"] = [[{r=1, group="Priest", indicator="", g=0.6, b=0, alpha=1, priority=0, duration=true, iconTexture="Interface\\Icons\\Spell_Holy_Excorcism"}]],
	["10060"] = [[{r=0, group="Priest", indicator="c", g=0, b=0, duration=true, priority=0, icon=true, iconTexture="Interface\\Icons\\Spell_Holy_PowerInfusion"}]],
	["14893"] = [[{r=0.9, group="Priest", indicator="", g=0.9, b=0.5, alpha=1, priority=0, duration=true, iconTexture="Interface\\Icons\\Spell_Holy_LayOnHands"}]],
	["552"] = [[{r=0.6, group="Priest", indicator="", g=0.4, b=0, alpha=1, priority=0, player=true, duration=true, iconTexture="Interface\\Icons\\Spell_Nature_NullifyDisease"}]],
	["586"] = [[{r=0, group="Priest", indicator="", g=0.85882352941176, selfColor={alpha=1, b=1, g=0.93725490196078, r=0, }, alpha=1, priority=0, b=1, iconTexture="Interface\\Icons\\Spell_Magic_LesserInvisibilty"}]],
	-- Druid
	["774"] = [[{r=0.57647058823529, group="Druid", indicator="tr", g=0.28235294117647, player=true, duration=true, b=0.6156862745098, priority=100, alpha=1, iconTexture="Interface\\Icons\\Spell_Nature_Rejuvenation"}]],
	["8936"] = [[{r=0.12156862745098, group="Druid", indicator="br", g=0.45882352941176, player=true, duration=true, b=0.12156862745098, priority=100, alpha=1, iconTexture="Interface\\Icons\\Spell_Nature_ResistNature"}]],
	["1126"] = [[{r=1, group="Druid", indicator="", g=0.49, b=0.04, alpha=1, priority=0, iconTexture="Interface\\Icons\\Spell_Nature_Regeneration"}]],
	["21849"] = [[{r=1, group="Druid", indicator="", g=0.49, b=0.04, alpha=1, priority=0, iconTexture="Interface\\Icons\\Spell_Nature_Regeneration"}]],
	["467"] = [[{r=0.6, group="Druid", indicator="", g=0.4, b=0.2, alpha=1, priority=0, iconTexture="Interface\\Icons\\Spell_Nature_Thorns"}]],
	["2893"] = [[{r=0, group="Druid", indicator="", g=0.6, b=0, alpha=1, priority=0, player=true, duration=true, iconTexture="Interface\\Icons\\Spell_Nature_NullifyPoison_02"}]],
	["29166"] = [[{r=0, group="Druid", indicator="c", g=0, b=0, duration=true, priority=0, icon=true, iconTexture="Interface\\Icons\\Spell_Nature_Lightning"}]],
	-- Mage
	["1459"] = [[{r=0.41, group="Mage", indicator="", g=0.8, b=0.94, alpha=1, priority=0, iconTexture="Interface\\Icons\\Spell_Holy_MagicalSentry"}]],
	["23028"] = [[{r=0.41, group="Mage", indicator="", g=0.8, b=0.94, alpha=1, priority=0, iconTexture="Interface\\Icons\\Spell_Holy_ArcaneIntellect"}]],
	["1008"] = [[{r=0.2, group="Mage", indicator="", g=0.6, b=1, alpha=1, priority=0, iconTexture="Interface\\Icons\\Spell_Holy_FlashHeal"}]],
	["604"] = [[{r=0.2, group="Mage", indicator="", g=0.2, b=0.6, alpha=1, priority=0, iconTexture="Interface\\Icons\\Spell_Nature_AbolishMagic"}]],
	-- Paladin
	["19740"] = [[{r=0.96, group="Paladin", indicator="", g=0.3, b=0.3, alpha=1, priority=0, iconTexture="Interface\\Icons\\Spell_Holy_FistOfJustice"}]],
	["19742"] = [[{r=0.3, group="Paladin", indicator="", g=0.5, b=1, alpha=1, priority=0, iconTexture="Interface\\Icons\\Spell_Holy_SealOfWisdom"}]],
	["20217"] = [[{r=0.96, group="Paladin", indicator="", g=0.55, b=0.73, alpha=1, priority=0, iconTexture="Interface\\Icons\\Spell_Magic_MageArmor"}]],
	["1038"] = [[{r=0.8, group="Paladin", indicator="", g=0.8, b=0.8, alpha=1, priority=0, iconTexture="Interface\\Icons\\Spell_Holy_SealOfSalvation"}]],
	["19977"] = [[{r=1, group="Paladin", indicator="", g=1, b=0.6, alpha=1, priority=0, iconTexture="Interface\\Icons\\Spell_Holy_PrayerOfHealing02"}]],
	["20911"] = [[{r=0.6, group="Paladin", indicator="", g=0.6, b=0.3, alpha=1, priority=0, iconTexture="Interface\\Icons\\Spell_Nature_LightningShield"}]],
	["25782"] = [[{r=0.96, group="Paladin", indicator="", g=0.3, b=0.3, alpha=1, priority=0, iconTexture="Interface\\Icons\\Spell_Holy_GreaterBlessingofKings"}]],
	["25894"] = [[{r=0.3, group="Paladin", indicator="", g=0.5, b=1, alpha=1, priority=0, iconTexture="Interface\\Icons\\Spell_Holy_GreaterBlessingofWisdom"}]],
	["25898"] = [[{r=0.96, group="Paladin", indicator="", g=0.55, b=0.73, alpha=1, priority=0, iconTexture="Interface\\Icons\\Spell_Magic_GreaterBlessingofKings"}]],
	["25895"] = [[{r=0.8, group="Paladin", indicator="", g=0.8, b=0.8, alpha=1, priority=0, iconTexture="Interface\\Icons\\Spell_Holy_GreaterBlessingofSalvation"}]],
	["25890"] = [[{r=1, group="Paladin", indicator="", g=1, b=0.6, alpha=1, priority=0, iconTexture="Interface\\Icons\\Spell_Holy_GreaterBlessingofLight"}]],
	["25899"] = [[{r=0.6, group="Paladin", indicator="", g=0.6, b=0.3, alpha=1, priority=0, iconTexture="Interface\\Icons\\Spell_Holy_GreaterBlessingofSanctuary"}]],
	["1022"] = [[{r=0, group="Paladin", indicator="c", g=0, player=false, duration=true, b=0, priority=0, icon=true, iconTexture="Interface\\Icons\\Spell_Holy_SealOfProtection"}]],
	["1044"] = [[{r=0, group="Paladin", indicator="", g=0, player=false, duration=true, b=0, priority=0, icon=true, iconTexture="Interface\\Icons\\Spell_Holy_SealOfValor"}]],
	["642"] = [[{r=0, group="Paladin", indicator="c", g=0, player=false, duration=true, b=0, priority=0, icon=true, iconTexture="Interface\\Icons\\Spell_Holy_DivineIntervention"}]],
	["25771"] = [[{r=0.8, group="Paladin", indicator="", g=0.2, b=0.2, alpha=1, priority=0, duration=true, iconTexture="Interface\\Icons\\Spell_Holy_RemoveCurse"}]],
	-- Shaman
	["16177"] = [[{r=0.14, group="Shaman", indicator="", g=0.35, b=1, alpha=1, priority=0, duration=true, iconTexture="Interface\\Icons\\Spell_Nature_UndyingStrength"}]],
	["29203"] = [[{r=0.3, group="Shaman", indicator="", g=0.7, b=1, alpha=1, priority=0, duration=true, iconTexture="Interface\\Icons\\Spell_Nature_HealingWay"}]],
	-- Warrior
	["6673"] = [[{r=0.78, group="Warrior", indicator="", g=0.61, b=0.43, alpha=1, priority=0, iconTexture="Interface\\Icons\\Ability_Warrior_BattleShout"}]],
	-- Warlock
	["20707"] = [[{indicator = '', group = "Warlock", priority = 10, r = 0.42, g = 0.21, b = 0.65}]],
	-- Food
	["19705"] = [[{r=0.80392156862745, group="Food", indicator="", g=0.76470588235294, missing=true, duration=true, priority=0, alpha=1, b=0.24313725490196}]],
	-- Warsong Gulch flags
	["23333"] = [[{icon=true, b=0, priority=0, r=0, group="PvP Flags", indicator="bl", g=0, iconTexture="Interface\\Icons\\INV_BannerPVP_01"}]],
	["23335"] = [[{r=0, group="PvP Flags", indicator="bl", g=0, duration=false, b=0, priority=0, icon=true, iconTexture="Interface\\Icons\\INV_BannerPVP_02"}]],
}

-- The defaults live in ShadowedUnitFrames.lua (LoadUnitDefaults); swap the retail list for ours
if( ShadowUF.LoadUnitDefaults ) then
	hooksecurefunc(ShadowUF, "LoadUnitDefaults", function(self)
		if( self.defaults and self.defaults.profile and self.defaults.profile.auraIndicators ) then
			self.defaults.profile.auraIndicators.auras = CopyTable(Indicators.defaultAuras)
		end
	end)
end

local backdropTbl = {bgFile = "Interface\\Addons\\ShadowedUnitFrames_Forever\\media\\textures\\backdrop", edgeFile = "Interface\\Addons\\ShadowedUnitFrames_Forever\\media\\textures\\backdrop", tile = true, tileSize = 1, edgeSize = 1}

-- Spell name -> configured aura key, so every rank of a configured spell ID matches
local nameToKey, nameMapCount = {}, -1
local function updateNameMap()
	local count = 0
	for _ in pairs(ShadowUF.db.profile.auraIndicators.auras) do count = count + 1 end
	if( count == nameMapCount ) then return end

	nameMapCount = count
	for k in pairs(nameToKey) do nameToKey[k] = nil end
	for key in pairs(ShadowUF.db.profile.auraIndicators.auras) do
		local spellID = tonumber(key)
		local name = spellID and GetSpellName(spellID)
		if( name and not issecretvalue(name) and not nameToKey[name] ) then
			nameToKey[name] = key
		end
	end
end

-- Forces the name map to be rebuilt (configuration changed)
function Indicators:ResetNameMap()
	nameMapCount = -1
end

-- The config key for an aura we can read: exact name, exact spell ID, linked aura, or another rank
local function findAuraKey(name, spellID)
	local auras = ShadowUF.db.profile.auraIndicators.auras
	if( auras[name] ) then return name end
	if( spellID and auras[spellID] ) then return spellID end

	local linked = ShadowUF.db.profile.auraIndicators.linked
	local link = linked and ( linked[name] or ( spellID and linked[spellID] ) )
	if( link and auras[link] ) then return link end

	return nameToKey[name]
end

-- Is a configured aura one the game never hides? Then not seeing it means it really isn't there.
local neverSecret = {}
local function isNeverSecret(key)
	if( neverSecret[key] ~= nil ) then return neverSecret[key] end
	local result = false
	if( C_Secrets and C_Secrets.ShouldSpellAuraBeSecret ) then
		local ok, secret = pcall(C_Secrets.ShouldSpellAuraBeSecret, tonumber(key) or key)
		result = ok and not issecretvalue(secret) and secret == false or false
	end
	neverSecret[key] = result
	return result
end

function Indicators:OnEnable(frame)
	-- Not going to create the indicators we want here, will do that when we do the layout stuff
	frame.auraIndicators = frame.auraIndicators or CreateFrame("Frame", nil, frame)
	frame.auraIndicators:SetFrameLevel(4)
	frame.auraIndicators:Show()
	frame.auraIndicators.known = frame.auraIndicators.known or {}
	frame.auraIndicators.seen = frame.auraIndicators.seen or {}

	-- Of course, watch for auras
	frame:RegisterUnitEvent("UNIT_AURA", self, "UpdateAuras")
	frame:RegisterUpdateFunc(self, "UpdateAuras")
end

function Indicators:OnDisable(frame)
	frame:UnregisterAll(self)
	frame.auraIndicators:Hide()
end

function Indicators:OnLayoutApplied(frame)
	if( not frame.auraIndicators ) then return end
	self:ResetNameMap()

	-- Create indicators
	local id = 1
	for key, indicatorConfig in pairs(ShadowUF.db.profile.auraIndicators.indicators) do
		-- Create indicator as needed
		local indicator = frame.auraIndicators["indicator-" .. id]
		if( not indicator ) then
			indicator = CreateFrame("Frame", nil, frame.auraIndicators, BackdropTemplateMixin and "BackdropTemplate" or nil)
			indicator:SetFrameLevel(frame.topFrameLevel + 2)
			indicator.texture = indicator:CreateTexture(nil, "OVERLAY")
			indicator.texture:SetPoint("CENTER", indicator)
			indicator:SetBackdrop(backdropTbl)
			indicator:SetBackdropColor(0, 0, 0, 1)
			indicator:SetBackdropBorderColor(0, 0, 0, 0)

			indicator.cooldown = CreateFrame("Cooldown", nil, indicator, "CooldownFrameTemplate")
			indicator.cooldown:SetReverse(true)
			indicator.cooldown:SetPoint("CENTER", 0, -1)
			indicator.cooldown:SetHideCountdownNumbers(true)

			indicator.stack = indicator:CreateFontString(nil, "OVERLAY")
			indicator.stack:SetFont("Interface\\AddOns\\ShadowedUnitFrames_Forever\\media\\fonts\\Myriad Condensed Web.ttf", 12, "OUTLINE")
			indicator.stack:SetShadowColor(0, 0, 0, 1.0)
			indicator.stack:SetShadowOffset(0.8, -0.8)
			indicator.stack:SetPoint("BOTTOMRIGHT", indicator, "BOTTOMRIGHT", 1, 0)
			indicator.stack:SetWidth(18)
			indicator.stack:SetHeight(10)
			indicator.stack:SetJustifyH("RIGHT")

			frame.auraIndicators["indicator-" .. id] = indicator
		end

		-- Quick access
		indicator.filters = ShadowUF.db.profile.auraIndicators.filters[key]
		indicator.config = ShadowUF.db.profile.units[frame.unitType].auraIndicators

		-- Set up the sizing options
		indicator:SetAlpha(indicatorConfig.alpha)
		indicator:SetHeight(indicatorConfig.height)
		indicator.texture:SetWidth(indicatorConfig.width - 1)
		indicator:SetWidth(indicatorConfig.width)
		indicator.texture:SetHeight(indicatorConfig.height - 1)
		indicator.cooldown:SetSize(indicatorConfig.width, indicatorConfig.height)

		ShadowUF.Layout:AnchorFrame(frame, indicator, indicatorConfig)

		-- Let the auras module quickly access indicators without having to use index
		frame.auraIndicators[key] = indicator

		id = id + 1
	end
end

local playerClass = select(2, UnitClass("player"))
local filterMap = {}
for _, key in pairs(Indicators.auraFilters) do filterMap[key] = "filter-" .. key end

-- Stores what an indicator should show. auraData may hold secret values; they are only
-- handed to widgets/APIs that accept them in UpdateIndicators.
local function assign(indicator, unit, auraData, info, priority, showIcon, showDuration, showStack, color)
	indicator.priority = priority
	indicator.showIcon = showIcon
	indicator.showDuration = showDuration
	indicator.showStack = showStack
	indicator.unit = unit
	indicator.auraData = auraData
	indicator.spellIcon = auraData.icon
	indicator.spellName = info and info.name
	indicator.colorR = color and color.r
	indicator.colorG = color and color.g
	indicator.colorB = color and color.b
end

local function checkFilterAura(frame, type, isFriendly, auraData, info, curableSet)
	local category
	local auraInstanceID = auraData.auraInstanceID
	if( issecretvalue(auraInstanceID) ) then auraInstanceID = nil end

	if( isFriendly and type == "debuffs" and auraInstanceID and curableSet and curableSet[auraInstanceID] ) then
		category = "curable"
	elseif( isFriendly and type == "debuffs" and not curableSet and info.dispelName and ShadowUF.Units:CanCure(info.dispelName) ) then
		category = "curable"
	elseif( info.boss ) then
		category = "boss"
	else
		return
	end

	local applied = false

	for key, config in pairs(ShadowUF.db.profile.auraIndicators.indicators) do
		local indicator = frame.auraIndicators[key]
		if( indicator and indicator.enabled and indicator.config.enabled and indicator.filters[category].enabled and not ShadowUF.db.profile.units[frame.unitType].auraIndicators[filterMap[category]] ) then
			assign(indicator, frame.unit, auraData, info, indicator.filters[category].priority, true, indicator.filters[category].duration, config.showStack, nil)
			applied = true
		end
	end

	return applied
end

local function checkSpecificAura(frame, auraData, info)
	-- Can't tell what it is
	if( not info.name ) then return end

	local key = findAuraKey(info.name, info.spellID)
	if( not key ) then return end

	local auraConfig = Indicators.auraConfig[key]
	if( not auraConfig ) then return end

	-- Only player auras
	if( auraConfig.player and not info.fromPlayer ) then return end

	local indicator = frame.auraIndicators[auraConfig.indicator]

	-- No indicator or not enabled
	if( not indicator or not indicator.enabled ) then return end
	-- Missing aura only
	if( auraConfig.missing ) then return end

	-- Disabled on a class level
	local disabled = ShadowUF.db.profile.auraIndicators.disabled[playerClass]
	if( disabled and ( disabled[key] or disabled[info.name] ) ) then return end
	-- Disabled aura group by unit
	if( ShadowUF.db.profile.units[frame.unitType].auraIndicators[auraConfig.group] ) then return end

	-- If the indicator is not restricted to the player only, then will give the player a slightly higher priority
	local priority = auraConfig.priority or 0
	local color = auraConfig
	if( not auraConfig.player and info.fromPlayer ) then
		priority = priority + 0.1
		color = auraConfig.selfColor or auraConfig
	end

	if( priority <= indicator.priority ) then return end

	assign(indicator, frame.unit, auraData, info, priority, auraConfig.icon, auraConfig.duration, ShadowUF.db.profile.auraIndicators.indicators[auraConfig.indicator].showStack, color)
	return true
end

-- What we found on the unit this scan: aura keys and names, and whether anything was unreadable
local auraList = {}
local scanState = {unreadable = false}
local curableTbl = {}

local function scanAuras(frame, filter, type)
	local unit = frame.unit
	local isFriendly = not UnitIsEnemy(unit, "player")
	local Auras = ShadowUF.Auras
	local known, seen = frame.auraIndicators.known, frame.auraIndicators.seen

	-- Debuffs the player can dispel, straight from the game; fine with secret auras
	local curableSet
	if( type == "debuffs" and isFriendly and Auras ) then
		curableSet = Auras:GetFilterSet(unit, "HARMFUL|RAID", curableTbl)
	end

	local index = 0
	while( true ) do
		local auraData
		auraData, index = ShadowUF.Secrets.NextAura(unit, index, filter)
		if( issecretvalue(auraData) or not auraData ) then return end

		local auraInstanceID = auraData.auraInstanceID
		if( issecretvalue(auraInstanceID) ) then auraInstanceID = nil end

		local info = auraInstanceID and ( seen[auraInstanceID] or known[auraInstanceID] ) or {}
		if( Auras and Auras.ReadAura ) then
			Auras.ReadAura(info, auraData)
		end
		if( auraInstanceID ) then seen[auraInstanceID] = info end

		local result = checkFilterAura(frame, type, isFriendly, auraData, info, curableSet)
		if( not result ) then
			checkSpecificAura(frame, auraData, info)
		end

		if( info.name ) then
			auraList[info.name] = true
			local key = findAuraKey(info.name, info.spellID)
			if( key ) then auraList[key] = true end
		else
			scanState.unreadable = true
		end
	end
end

function Indicators:UpdateIndicators(frame)
	local Auras = ShadowUF.Auras
	for key in pairs(ShadowUF.db.profile.auraIndicators.indicators) do
		local indicator = frame.auraIndicators[key]
		if( indicator and indicator.enabled and indicator.priority and indicator.priority > -1 ) then
			local auraData = indicator.auraData

			-- Show a cooldown ring
			if( indicator.showDuration and auraData and Auras ) then
				Auras:SetCooldown(indicator.cooldown, indicator.unit, auraData)
			else
				indicator.cooldown:Hide()
			end

			-- Show either the icon, or a solid color
			if( indicator.showIcon and indicator.spellIcon ) then
				indicator.texture:SetTexture(indicator.spellIcon)
				indicator:SetBackdropColor(0, 0, 0, 0)
			else
				indicator.texture:SetColorTexture(indicator.colorR or 0, indicator.colorG or 0, indicator.colorB or 0)
				indicator:SetBackdropColor(0, 0, 0, 1)
			end

			-- Show aura stack
			if( indicator.showStack and auraData and Auras ) then
				indicator.stack:SetText(Auras:GetStackText(indicator.unit, auraData))
				indicator.stack:Show()
			else
				indicator.stack:Hide()
			end

			indicator:Show()
		elseif( indicator ) then
			indicator:Hide()
		end
	end
end

function Indicators:UpdateAuras(frame)
	for k in pairs(auraList) do auraList[k] = nil end
	scanState.unreadable = false
	updateNameMap()

	for key, config in pairs(ShadowUF.db.profile.auraIndicators.indicators) do
		local indicator = frame.auraIndicators[key]
		if( indicator ) then
			indicator.priority = -1
			indicator.auraData = nil

			if( UnitIsEnemy(frame.unit, "player") ) then
				indicator.enabled = config.hostile
			else
				indicator.enabled = config.friendly
			end
		end
	end

	-- If they are dead, don't bother showing any indicators yet
	if( UnitIsDeadOrGhost(frame.unit) or not UnitIsConnected(frame.unit) ) then
		self:UpdateIndicators(frame)
		return
	end

	-- Scan auras
	local indicators = frame.auraIndicators
	for k in pairs(indicators.seen) do indicators.seen[k] = nil end
	scanAuras(frame, "HELPFUL", "buffs")
	scanAuras(frame, "HARMFUL", "debuffs")
	indicators.known, indicators.seen = indicators.seen, indicators.known

	-- Check for any indicators that are triggered due to something missing.
	-- If some auras couldn't be read we only trust "missing" for spells the game never hides.
	local disabled = ShadowUF.db.profile.auraIndicators.disabled[playerClass]
	for name in pairs(ShadowUF.db.profile.auraIndicators.missing) do
		local aura = self.auraConfig[name]
		if( aura and not auraList[name] and ( not scanState.unreadable or isNeverSecret(name) ) ) then
			local spellName = tonumber(name) and GetSpellName(tonumber(name))
			if( not spellName or issecretvalue(spellName) or not auraList[spellName] ) then
				local indicator = frame.auraIndicators[aura.indicator]
				if( indicator and indicator.enabled and (aura.priority or 0) > indicator.priority and not ( disabled and disabled[name] ) ) then
					indicator.priority = aura.priority or 0
					indicator.showIcon = aura.icon
					indicator.showDuration = false
					indicator.showStack = false
					indicator.auraData = nil
					indicator.spellIcon = aura.iconTexture or GetSpellTexture(tonumber(name) or name)
					indicator.colorR = aura.r
					indicator.colorG = aura.g
					indicator.colorB = aura.b
				end
			end
		end
	end

	-- Now force the indicators to update
	self:UpdateIndicators(frame)
end
