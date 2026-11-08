--[[
	Combat fader. Originally by Shadowed (Shadowed Unit Frames), ported to WoW Forever.

	Forever: health/power can be secret, and a frame's alpha becomes secret once the range
	module applies a secret in-range result with SetAlphaFromBoolean. Nothing secret is ever
	compared here: a secret health/power counts as "not full" (the frame fades in), and a
	secret current alpha is treated as fully visible when a fade starts.
]]
local Fader = {}
local Secrets = ShadowUF.Secrets
local issecretvalue = Secrets.IsSecret
local powerDepletes = {[Enum.PowerType.Mana] = true, [Enum.PowerType.Energy] = true, [Enum.PowerType.Focus] = true}
ShadowUF:RegisterModule(Fader, "fader", ShadowUF.L["Combat fader"])

-- TODO: Remove once Blizzard fixes cooldown wheels not taking parents alpha
local function tempAuraFader(frame, alpha)
	if( not frame.auras or issecretvalue(alpha) ) then return end

	local childAlpha = 0.8 * alpha
	if( frame.auras.buffs ) then
		for id, button in pairs(frame.auras.buffs.buttons) do
			button.cooldown:SetSwipeColor(0, 0, 0, childAlpha)
		end
	end

	if( frame.auras.debuffs ) then
		for id, button in pairs(frame.auras.debuffs.buttons) do
			button.cooldown:SetSwipeColor(0, 0, 0, childAlpha)
		end
	end
end

local function faderUpdate(self, elapsed)
	self.timeElapsed = self.timeElapsed + elapsed
	if( self.timeElapsed >= self.fadeTime ) then
		tempAuraFader(self.parent, self.alphaEnd)
		self.parent:SetAlpha(self.alphaEnd)
		self:Hide()

		if( self.fadeType == "in" ) then
			self.parent:DisableRangeAlpha(false)
		end
		return
	end

	if( self.fadeType == "in" ) then
		self.parent:SetAlpha((self.timeElapsed / self.fadeTime) * (self.alphaEnd - self.alphaStart) + self.alphaStart)
	else
		self.parent:SetAlpha(((self.fadeTime - self.timeElapsed) / self.fadeTime) * (self.alphaStart - self.alphaEnd) + self.alphaEnd)
	end

	tempAuraFader(self.parent, Secrets.Plain(self.parent:GetAlpha(), 1))
end

local function startFading(self, type, alpha, speedyFade)
	if( self.fader.fadeType == type ) then return end
	if( type == "out" ) then
		self:DisableRangeAlpha(true)
	end

	self.fader.fadeTime = speedyFade and 0.15 or type == "in" and 0.25 or type == "out" and 0.75
	self.fader.fadeType = type
	self.fader.timeElapsed = 0
	self.fader.alphaEnd = alpha
	self.fader.alphaStart = Secrets.Plain(self:GetAlpha(), 1)
	self.fader:Show()
end

function Fader:OnEnable(frame)
	if( not frame.fader ) then
		frame.fader = CreateFrame("Frame", nil, frame)
		frame.fader.timeElapsed = 0
		frame.fader.parent = frame
		frame.fader:SetScript("OnUpdate", faderUpdate)
		frame.fader:Hide()
	end

	frame:RegisterNormalEvent("PLAYER_REGEN_ENABLED", self, "Update")
	frame:RegisterNormalEvent("PLAYER_REGEN_DISABLED", self, "Update")
	frame:RegisterUpdateFunc(self, "Update")

	if( InCombatLockdown() ) then
		Fader:PLAYER_REGEN_DISABLED(frame, "PLAYER_REGEN_DISABLED")
	else
		Fader:PLAYER_REGEN_ENABLED(frame, "PLAYER_REGEN_ENABLED")
	end
end

function Fader:OnLayoutApplied(frame)
	if( frame.visibility.fader ) then
		frame.fader.fadeType = nil
		frame:DisableRangeAlpha(false)
	end
end

function Fader:OnDisable(frame)
	frame:UnregisterAll(self)
	frame:SetAlpha(1.0)

	if( frame.fader ) then
		frame.fader.fadeType = nil
		frame.fader:Hide()
	end
end

-- While we're in combat, we don't care about the other events so we might as well unregister them
function Fader:PLAYER_REGEN_ENABLED(frame, event)
	self:Update(frame, event)
	frame:RegisterNormalEvent("PLAYER_TARGET_CHANGED", self, "Update")
	frame:RegisterNormalEvent("UNIT_SPELLCAST_CHANNEL_START", self, "CastStart")
	frame:RegisterNormalEvent("UNIT_SPELLCAST_CHANNEL_STOP", self, "CastStop")
	frame:RegisterNormalEvent("UNIT_SPELLCAST_START", self, "CastStart")
	frame:RegisterNormalEvent("UNIT_SPELLCAST_STOP", self, "CastStop")
	frame:RegisterUnitEvent("UNIT_HEALTH", self, "Update")
	frame:RegisterUnitEvent("UNIT_MAXHEALTH", self, "Update")
	frame:RegisterUnitEvent("UNIT_POWER_FREQUENT", self, "Update")
	frame:RegisterUnitEvent("UNIT_MAXPOWER", self, "Update")
end

function Fader:PLAYER_REGEN_DISABLED(frame, event)
	self:Update(frame, event)
	frame:UnregisterSingleEvent("PLAYER_TARGET_CHANGED", self)
	frame:UnregisterSingleEvent("UNIT_SPELLCAST_CHANNEL_START", self)
	frame:UnregisterSingleEvent("UNIT_SPELLCAST_CHANNEL_STOP", self)
	frame:UnregisterSingleEvent("UNIT_SPELLCAST_START", self)
	frame:UnregisterSingleEvent("UNIT_SPELLCAST_STOP", self)
	frame:UnregisterSingleEvent("UNIT_HEALTH", self)
	frame:UnregisterSingleEvent("UNIT_POWER_FREQUENT", self)
	frame:UnregisterSingleEvent("UNIT_MAXHEALTH", self)
	frame:UnregisterSingleEvent("UNIT_MAXPOWER", self)
end


-- Cast GUIDs are only compared when they aren't secret (the player's own normally aren't)
local activeCastID
function Fader:CastStart(frame, event, unit, id)
	if( unit ~= "player" ) then return end
	if( issecretvalue(id) ) then
		id = true
	elseif( activeCastID == id ) then
		return
	end
	activeCastID = id

	frame.fader.playerCasting = true
	self:Update(frame)
end

function Fader:CastStop(frame, event, unit, id)
	if( unit ~= "player" or activeCastID == nil ) then return end
	if( not issecretvalue(id) and activeCastID ~= true and activeCastID ~= id ) then return end
	activeCastID = nil

	frame.fader.playerCasting = nil
	self:Update(frame)
end


-- Plain answer to "is this below max?"; secret (or unknown) values count as not full
local function notFull(cur, max)
	if( issecretvalue(cur) or issecretvalue(max) or cur == nil or max == nil ) then return true end
	return cur ~= max
end

local function powerNotFull(unit)
	local powerType = UnitPowerType(unit)
	if( issecretvalue(powerType) or not powerDepletes[powerType] ) then return false end
	return notFull(UnitPower(unit), UnitPowerMax(unit))
end

function Fader:Update(frame, event)
	-- In combat, fade back in
	if( InCombatLockdown() or event == "PLAYER_REGEN_DISABLED" ) then
		startFading(frame, "in", ShadowUF.db.profile.units[frame.unitType].fader.combatAlpha)
	-- Player is casting, fade in
	elseif( frame.fader.playerCasting ) then
		startFading(frame, "in", ShadowUF.db.profile.units[frame.unitType].fader.combatAlpha, true)
	-- Ether mana or energy is not at 100%, fade in
	elseif( powerNotFull(frame.unit) ) then
		startFading(frame, "in", ShadowUF.db.profile.units[frame.unitType].fader.combatAlpha)
	-- Health is not at max, fade in
	elseif( notFull(UnitHealth(frame.unit), UnitHealthMax(frame.unit)) ) then
		startFading(frame, "in", ShadowUF.db.profile.units[frame.unitType].fader.combatAlpha)
	-- Targetting somebody, fade in
	elseif( frame.unitType == "player" and UnitExists("target") ) then
		startFading(frame, "in", ShadowUF.db.profile.units[frame.unitType].fader.combatAlpha)
	-- Nothing else? Fade out!
	else
		startFading(frame, "out", ShadowUF.db.profile.units[frame.unitType].fader.inactiveAlpha)
	end
end
