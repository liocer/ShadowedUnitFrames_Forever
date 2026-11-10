--[[
	Poised glow, new in SUF Forever.

	Forever gives rogues (level 18) and druids (level 32) the passive Poised: out of combat at
	full energy, the next energy ability costs 10 less. Blizzard's player frame shows it as a
	glow on the end of the energy bar; this does the same on the power bar.

	The passive isn't a buff we can read, so the glow follows its rule instead: the player is
	out of combat, uses energy (cat form for druids), the bar is full and the level is high
	enough. Out of combat power isn't secret; if it ever is, the glow just stays hidden.
]]

local Poised = {}
ShadowUF:RegisterModule(Poised, "poised", ShadowUF.L["Poised glow"])

local Secrets = ShadowUF.Secrets
local ENERGY = Enum.PowerType.Energy
local POISED_LEVEL = {ROGUE = 18, DRUID = 32}
local GLOW_ATLAS = "FullAlert-SoftCurveGlow"
local GLOW_FILE = [[Interface\CastingBar\UI-CastingBar-Spark]]

local function createGlow(frame)
	local holder = CreateFrame("Frame", nil, frame)
	holder:SetAllPoints(frame.powerBar)

	local glow = holder:CreateTexture(nil, "OVERLAY")
	glow:SetBlendMode("ADD")
	if( not ( glow.SetAtlas and glow:SetAtlas(GLOW_ATLAS) ) ) then
		glow:SetTexture(GLOW_FILE)
	end
	holder.glow = glow

	local pulse = glow:CreateAnimationGroup()
	pulse:SetLooping("BOUNCE")
	local fade = pulse:CreateAnimation("Alpha")
	fade:SetFromAlpha(1)
	fade:SetToAlpha(0.35)
	fade:SetDuration(0.8)
	fade:SetSmoothing("IN_OUT")
	holder.pulse = pulse

	holder:Hide()
	return holder
end

function Poised:OnEnable(frame)
	if( frame.unitType ~= "player" ) then return end
	frame.poised = frame.poised or createGlow(frame)

	frame:RegisterUnitEvent("UNIT_POWER_FREQUENT", self, "Update")
	frame:RegisterUnitEvent("UNIT_MAXPOWER", self, "Update")
	frame:RegisterUnitEvent("UNIT_DISPLAYPOWER", self, "Update")
	frame:RegisterNormalEvent("PLAYER_REGEN_DISABLED", self, "Update")
	frame:RegisterNormalEvent("PLAYER_REGEN_ENABLED", self, "Update")
	frame:RegisterNormalEvent("PLAYER_LEVEL_UP", self, "Update")

	frame:RegisterUpdateFunc(self, "Update")
end

function Poised:OnDisable(frame)
	frame:UnregisterAll(self)
	if( frame.poised ) then
		frame.poised.pulse:Stop()
		frame.poised:Hide()
	end
end

-- Puts the glow on the far end of the bar, following its orientation and fill direction
function Poised:OnLayoutApplied(frame)
	local holder = frame.poised
	if( not holder or not frame.visibility.poised or not frame.powerBar ) then return end

	local bar, glow = frame.powerBar, holder.glow
	holder:SetFrameLevel(bar:GetFrameLevel() + 3)

	local config = ShadowUF.db.profile.units[frame.unitType].powerBar
	local vertical, reverse = config.vertical, config.reverse
	local thickness = vertical and bar:GetWidth() or bar:GetHeight()
	local size = math.max(thickness, 4) * 2.5

	glow:ClearAllPoints()
	glow:SetSize(size * 0.6, size)
	glow:SetRotation(vertical and math.pi / 2 or 0)
	if( vertical ) then
		glow:SetPoint("CENTER", bar, reverse and "BOTTOM" or "TOP")
	else
		glow:SetPoint("CENTER", bar, reverse and "LEFT" or "RIGHT")
	end

	self:Update(frame)
end

-- The event that just fired settles combat state; UnitAffectingCombat lags behind REGEN events
local function inCombat(event)
	if( event == "PLAYER_REGEN_DISABLED" ) then return true end
	if( event == "PLAYER_REGEN_ENABLED" ) then return false end
	local combat = UnitAffectingCombat("player")
	return Secrets.IsSecret(combat) or combat
end

local function shouldGlow(frame, event)
	local _, class = UnitClass("player")
	local level = POISED_LEVEL[Secrets.Plain(class)]
	if( not level or UnitLevel("player") < level ) then return false end
	if( not frame.powerBar or not frame.powerBar:IsShown() ) then return false end
	if( inCombat(event) or UnitIsDeadOrGhost("player") ) then return false end
	if( Secrets.Plain(UnitPowerType("player")) ~= ENERGY ) then return false end

	local current, maxPower = UnitPower("player", ENERGY), UnitPowerMax("player", ENERGY)
	if( Secrets.Any(current, maxPower) or not maxPower or maxPower <= 0 ) then return false end
	return current >= maxPower
end

function Poised:Update(frame, event)
	local holder = frame.poised
	if( not holder or not frame.visibility.poised ) then return end

	if( shouldGlow(frame, event) ) then
		local color = ShadowUF.db.profile.powerColors.ENERGY
		holder.glow:SetVertexColor(color.r, color.g, color.b)
		holder:Show()
		if( not holder.pulse:IsPlaying() ) then holder.pulse:Play() end
	else
		holder.pulse:Stop()
		holder:Hide()
	end
end
