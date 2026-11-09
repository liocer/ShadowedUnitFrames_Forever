-- Damage absorbs (shields), drawn after the incoming heals (or after the health when those
-- are off). Secret safe: see incheal.lua for how the overlay bars work.
local IncAbsorb = setmetatable({["frameKey"] = "incAbsorb", ["colorKey"] = "incAbsorb", ["frameLevelMod"] = 3}, {__index = ShadowUF.IncHeal})
ShadowUF:RegisterModule(IncAbsorb, "incAbsorb", ShadowUF.L["Incoming absorbs"])

function IncAbsorb:OnEnable(frame)
	frame:RegisterUnitEvent("UNIT_MAXHEALTH", self, "UpdateFrame")
	frame:RegisterUnitEvent("UNIT_HEALTH", self, "UpdateFrame")
	frame:RegisterUnitEvent("UNIT_ABSORB_AMOUNT_CHANGED", self, "UpdateFrame")
	frame:RegisterUnitEvent("UNIT_CONNECTION", self, "UpdateFrame")

	frame:RegisterUpdateFunc(self, "UpdateFrame")
end

-- Starts where the incoming heals end, if they're shown
function IncAbsorb:GetAnchorTexture(frame)
	if( frame.visibility.incHeal and frame.incHeal ) then
		return frame.incHeal:GetStatusBarTexture()
	end
	return nil
end

function IncAbsorb:OnLayoutApplied(frame)
	if( not frame.visibility[self.frameKey] or not frame.visibility.healthBar ) then
		ShadowUF.IncHeal.OnLayoutApplied(self, frame)
		return
	end

	-- The heal amounts change where this bar starts (and how much heal absorbs eat into them)
	if( frame.visibility.incHeal ) then
		frame:RegisterUnitEvent("UNIT_HEAL_PREDICTION", self, "UpdateFrame")
	else
		frame:UnregisterSingleEvent("UNIT_HEAL_PREDICTION", self, "UpdateFrame")
	end

	ShadowUF.IncHeal.OnLayoutApplied(self, frame)
end

function IncAbsorb:UpdateFrame(frame)
	if( not frame.visibility[self.frameKey] or not frame.visibility.healthBar or not frame[self.frameKey] ) then return end

	local _, absorbs = ShadowUF.IncHeal.GetAmounts(frame)
	self:PositionBar(frame, absorbs)
end
