--[[
	Health bar. Originally by Shadowed; SUF Forever changes for secret values:
	- The bar takes the (maybe secret) health straight into SetMinMaxValues / SetValue.
	- Gradient colouring uses the original maths when health is readable, and a colour curve
	  evaluated by the game (UnitHealthPercent with a colour curve) when it's secret.
	- Dispel colouring finds a debuff the player can dispel with the game's own "HARMFUL|RAID"
	  filter (which works on secret auras) and gets its colour from
	  C_UnitAuras.GetAuraDispelTypeColor when the dispel type is secret.
]]

local Health = {}
ShadowUF:RegisterModule(Health, "healthBar", ShadowUF.L["Health bar"], true)
local Secrets = ShadowUF.Secrets
local issecretvalue = Secrets.IsSecret

-- The original gradient maths, for a readable 0 - 1 percent
local function gradientFromPercent(percent)
	local colors = ShadowUF.db.profile.healthColors
	if( percent >= 1 ) then return colors.green.r, colors.green.g, colors.green.b end
	if( percent <= 0 ) then return colors.red.r, colors.red.g, colors.red.b end

	local sR, sG, sB, eR, eG, eB
	local modifier = percent * 2
	if( percent > 0.50 ) then
		sR, sG, sB = colors.green.r, colors.green.g, colors.green.b
		eR, eG, eB = colors.yellow.r, colors.yellow.g, colors.yellow.b

		modifier = modifier - 1
	else
		sR, sG, sB = colors.yellow.r, colors.yellow.g, colors.yellow.b
		eR, eG, eB = colors.red.r, colors.red.g, colors.red.b
	end

	local inverseModifier = 1 - modifier
	return eR * inverseModifier + sR * modifier, eG * inverseModifier + sG * modifier, eB * inverseModifier + sB * modifier
end

-- The same gradient as a colour curve (red at 0, yellow at 50%, green at 100%), rebuilt
-- whenever the colours in the options change
local gradientCurve
local curveColors = {}
local function getGradientCurve()
	local colors = ShadowUF.db.profile.healthColors
	local changed = not gradientCurve
	for i, key in ipairs({"red", "yellow", "green"}) do
		local c = colors[key]
		local saved = curveColors[i]
		if( not saved or saved.r ~= c.r or saved.g ~= c.g or saved.b ~= c.b ) then
			curveColors[i] = {r = c.r, g = c.g, b = c.b}
			changed = true
		end
	end

	if( changed ) then
		gradientCurve = Secrets.CreateColorCurve({
			{0, curveColors[1].r, curveColors[1].g, curveColors[1].b},
			{0.5, curveColors[2].r, curveColors[2].g, curveColors[2].b},
			{1, curveColors[3].r, curveColors[3].g, curveColors[3].b},
		}) or false
	end

	return gradientCurve or nil
end

-- Gradient colour for the unit's health. The r, g, b returned may be secret (in combat);
-- they can go straight into SetStatusBarColor / SetVertexColor but nothing else.
local function getGradientColorAny(unit)
	local current, maxHealth = UnitHealth(unit), UnitHealthMax(unit)
	if( not issecretvalue(current) and not issecretvalue(maxHealth) ) then
		return gradientFromPercent(maxHealth > 0 and current / maxHealth or 0)
	end

	local curve = UnitHealthPercent and getGradientCurve()
	if( curve ) then
		local ok, r, g, b = pcall(function()
			local color = UnitHealthPercent(unit, false, curve)
			return color:GetRGB()
		end)
		if( ok ) then return r, g, b end
	end

	local colors = ShadowUF.db.profile.healthColors
	return colors.yellow.r, colors.yellow.g, colors.yellow.b
end

-- Plain numbers only (for tags such as [hp:color] that do maths on them): when health is
-- secret this falls back to the yellow (50%) colour.
local function getGradientColor(unit)
	local current, maxHealth = UnitHealth(unit), UnitHealthMax(unit)
	if( issecretvalue(current) or issecretvalue(maxHealth) ) then
		local colors = ShadowUF.db.profile.healthColors
		return colors.yellow.r, colors.yellow.g, colors.yellow.b
	end
	return gradientFromPercent(maxHealth > 0 and current / maxHealth or 0)
end

Health.getGradientColor = getGradientColor
Health.getGradientColorAny = getGradientColorAny

-- Dispel types: SUF's colours (Blizzard's old DebuffTypeColor) and the game's dispel type IDs,
-- which is what C_UnitAuras.GetAuraDispelTypeColor feeds into the curve as x.
local dispelColors = {
	none = {r = 0.80, g = 0, b = 0},
	Magic = {r = 0.20, g = 0.60, b = 1.00},
	Curse = {r = 0.60, g = 0.00, b = 1.00},
	Disease = {r = 0.60, g = 0.40, b = 0},
	Poison = {r = 0.00, g = 0.60, b = 0},
	Bleed = {r = 0.80, g = 0, b = 0},
	Enrage = {r = 0.80, g = 0, b = 0},
}
local dispelIDs = {{0, "none"}, {1, "Magic"}, {2, "Curse"}, {3, "Disease"}, {4, "Poison"}, {9, "Enrage"}, {11, "Bleed"}}
Health.dispelColors = dispelColors

local dispelCurve
local function getDispelCurve()
	if( dispelCurve == nil ) then
		dispelCurve = false
		if( C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor ) then
			local ok, curve = pcall(function()
				local c = C_CurveUtil.CreateColorCurve()
				if( Enum.LuaCurveType ) then c:SetType(Enum.LuaCurveType.Step) end
				for _, point in ipairs(dispelIDs) do
					local color = dispelColors[point[2]]
					c:AddPoint(point[1], CreateColor(color.r, color.g, color.b, 1))
				end
				return c
			end)
			dispelCurve = ok and curve or false
		end
	end
	return dispelCurve or nil
end

-- First debuff on the unit the player can dispel
local function findDispellable(unit)
	-- The game's own "the player can dispel this" filter; works on secret auras too
	local aura = C_UnitAuras.GetAuraDataByIndex(unit, 1, "HARMFUL|RAID")
	if( aura and not issecretvalue(aura) ) then return aura end

	-- SUF's own list of what the player can cure, for readable auras
	if( next(ShadowUF.Units.canCure) ) then
		for id = 1, 40 do
			aura = C_UnitAuras.GetAuraDataByIndex(unit, id, "HARMFUL")
			if( not aura or issecretvalue(aura) ) then break end

			local dispelName = aura.dispelName
			if( ShadowUF.Units:CanCure(dispelName) ) then
				return aura
			end
		end
	end
end

function Health:OnEnable(frame)
	if( not frame.healthBar ) then
		frame.healthBar = ShadowUF.Units:CreateBar(frame)
	end

	frame:RegisterUnitEvent("UNIT_HEALTH", self, "Update")
	frame:RegisterUnitEvent("UNIT_MAXHEALTH", self, "Update")
	frame:RegisterUnitEvent("UNIT_CONNECTION", self, "Update")
	frame:RegisterUnitEvent("UNIT_FACTION", self, "UpdateColor")
	frame:RegisterUnitEvent("UNIT_THREAT_SITUATION_UPDATE", self, "UpdateColor")
	frame:RegisterUnitEvent("UNIT_TARGETABLE_CHANGED", self, "UpdateColor")

	if( frame.unit == "pet" ) then
		frame:RegisterUnitEvent("UNIT_POWER_UPDATE", self, "UpdateColor")
	end

	if ( ShadowUF.db.profile.units[frame.unitType].healthBar.colorDispel ) then
		frame:RegisterUnitEvent("UNIT_AURA", self, "UpdateAura")
		frame:RegisterUpdateFunc(self, "UpdateAura")
	end

	frame:RegisterUpdateFunc(self, "UpdateColor")
	frame:RegisterUpdateFunc(self, "Update")
end

function Health:OnDisable(frame)
	frame:UnregisterAll(self)
end

function Health:UpdateAura(frame)
	local bar = frame.healthBar
	local hadDebuff = bar.hasDebuff
	bar.hasDebuff = nil

	if( UnitIsFriend(frame.unit, "player") ) then
		local aura = findDispellable(frame.unit)
		if( aura ) then
			local dispelName = aura.dispelName
			if( not issecretvalue(dispelName) ) then
				if( dispelName and dispelColors[dispelName] ) then
					bar.hasDebuff = dispelName
					bar.debuffColor = dispelColors[dispelName]
				end
			else
				-- Secret dispel type: let the game turn it into a colour
				local auraInstanceID = aura.auraInstanceID
				local curve = getDispelCurve()
				if( curve and C_UnitAuras.GetAuraDispelTypeColor and not issecretvalue(auraInstanceID) and auraInstanceID ) then
					local ok, r, g, b = pcall(function()
						local color = C_UnitAuras.GetAuraDispelTypeColor(frame.unit, auraInstanceID, curve)
						return color:GetRGB()
					end)
					if( ok ) then
						bar.hasDebuff = "aura" .. auraInstanceID
						bar.secretDebuffColor = bar.secretDebuffColor or {}
						bar.secretDebuffColor.r, bar.secretDebuffColor.g, bar.secretDebuffColor.b = r, g, b
						bar.debuffColor = bar.secretDebuffColor
					end
				end
			end
		end
	end

	if( hadDebuff ~= bar.hasDebuff ) then
		self:UpdateColor(frame)
	end
end

function Health:UpdateColor(frame)
	frame.healthBar.hasReaction = nil
	frame.healthBar.hasPercent = nil
	frame.healthBar.wasOffline = nil

	local color
	local unit = frame.unit
	local config = ShadowUF.db.profile.units[frame.unitType].healthBar
	local reactionType = config.reactionType
	if( not UnitIsConnected(unit) ) then
		frame.healthBar.wasOffline = true
		frame:SetBarColor("healthBar", ShadowUF.db.profile.healthColors.offline.r, ShadowUF.db.profile.healthColors.offline.g, ShadowUF.db.profile.healthColors.offline.b)
		return
	elseif( config.colorDispel and frame.healthBar.hasDebuff and frame.healthBar.debuffColor ) then
		color = frame.healthBar.debuffColor
	elseif( config.colorAggro and Secrets.Plain(UnitThreatSituation(frame.unit)) == 3 ) then
		frame:SetBarColor("healthBar", ShadowUF.db.profile.healthColors.aggro.r, ShadowUF.db.profile.healthColors.aggro.g, ShadowUF.db.profile.healthColors.aggro.b)
		return
	elseif( frame.inVehicle ) then
		color = ShadowUF.db.profile.classColors.VEHICLE
	elseif( not UnitPlayerControlled(unit) and UnitIsTapDenied(unit) and UnitCanAttack("player", unit) ) then
		color = ShadowUF.db.profile.healthColors.tapped
	elseif( not UnitPlayerOrPetInRaid(unit) and not UnitPlayerOrPetInParty(unit) and ( ( ( reactionType == "player" or reactionType == "both" ) and UnitPlayerControlled(unit) and not UnitIsFriend(unit, "player") ) or ( ( reactionType == "npc" or reactionType == "both" )  and not UnitPlayerControlled(unit) ) ) ) then
		if( not UnitIsFriend(unit, "player") and UnitPlayerControlled(unit) ) then
			if( UnitCanAttack("player", unit) ) then
				color = ShadowUF.db.profile.healthColors.hostile
			else
				color = ShadowUF.db.profile.healthColors.enemyUnattack
			end
		else
			local reaction = Secrets.Plain(UnitReaction(unit, "player"))
			if( reaction ) then
				if( reaction > 4 ) then
					color = ShadowUF.db.profile.healthColors.friendly
				elseif( reaction == 4 ) then
					color = ShadowUF.db.profile.healthColors.neutral
				else
					color = ShadowUF.db.profile.healthColors.hostile
				end
			end
		end
	elseif( config.colorType == "class" and (UnitIsPlayer(unit) or unit == "pet") ) then
		local class = (unit == "pet") and "PET" or Secrets.Plain(frame:UnitClassToken())
		color = class and ShadowUF.db.profile.classColors[class]
	elseif( config.colorType == "playerclass" and unit == "pet") then
		local class = select(2, UnitClass("player"))
		color = class and ShadowUF.db.profile.classColors[class]
	elseif( config.colorType == "playerclass" and (frame.unitType == "partypet" or frame.unitType == "raidpet" or frame.unitType == "arenapet") and (frame.parent or frame.unitType == "raidpet") ) then
		local unit2
		if frame.unitType == "raidpet" then
			local id = string.match(frame.unit, "raidpet(%d+)")
			if id then
				unit2 = "raid" .. id
			end
		elseif frame.parent then
			unit2 = frame.parent.unit
		end
		if unit2 then
			local class = Secrets.Plain((select(2, UnitClass(unit2))))
			color = class and ShadowUF.db.profile.classColors[class]
		end
	elseif( config.colorType == "static" ) then
		color = ShadowUF.db.profile.healthColors.static
	end

	if( color ) then
		frame:SetBarColor("healthBar", color.r, color.g, color.b)
	else
		frame.healthBar.hasPercent = true
		frame:SetBarColor("healthBar", getGradientColorAny(unit))
	end
end

function Health:Update(frame)
	local unit = frame.unit
	local bar = frame.healthBar
	local isOffline = not UnitIsConnected(unit)
	frame.isDead = UnitIsDeadOrGhost(unit)

	local maxHealth = UnitHealthMax(unit)
	bar.currentHealth = UnitHealth(unit)

	-- Offline fills the bar, dead empties it; health and max may be secret, the bar takes them
	local value = bar.currentHealth
	if( isOffline ) then
		value = maxHealth
	elseif( frame.isDead ) then
		value = 0
	end

	bar.exactValues = Secrets.SetBar(bar, value, maxHealth, function()
		if( isOffline ) then return 100 end
		if( frame.isDead ) then return 0 end
		return Secrets.HealthPercent(unit)
	end)

	-- Unit is offline, fill bar up + grey it
	if( isOffline ) then
		bar.wasOffline = true
		frame.unitIsOnline = nil
		frame:SetBarColor("healthBar", ShadowUF.db.profile.healthColors.offline.r, ShadowUF.db.profile.healthColors.offline.g, ShadowUF.db.profile.healthColors.offline.b)
	-- The unit was offline, but they no longer are so we need to do a forced color update
	elseif( bar.wasOffline ) then
		bar.wasOffline = nil
		self:UpdateColor(frame)
	-- Color health by percentage
	elseif( bar.hasPercent ) then
		frame:SetBarColor("healthBar", getGradientColorAny(unit))
	end
end
