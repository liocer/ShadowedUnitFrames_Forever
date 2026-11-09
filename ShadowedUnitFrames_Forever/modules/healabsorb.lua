-- Heal absorbs: drawn over the end of the health, the way Blizzard's frames show them (the
-- part of the health incoming heals have to fill back in first). With incoming heals shown
-- the two cancel out: this bar shows what's left of the absorb after the heals land.
-- Secret safe: see incheal.lua for how the overlay bars work.
local HealAbsorb = setmetatable({["frameKey"] = "healAbsorb", ["colorKey"] = "healAbsorb", ["frameLevelMod"] = 1, ["inward"] = true}, {__index = ShadowUF.IncHeal})
ShadowUF:RegisterModule(HealAbsorb, "healAbsorb", ShadowUF.L["Healing absorb"])

function HealAbsorb:OnEnable(frame)
	frame:RegisterUnitEvent("UNIT_MAXHEALTH", self, "UpdateFrame")
	frame:RegisterUnitEvent("UNIT_HEALTH", self, "UpdateFrame")
	frame:RegisterUnitEvent("UNIT_HEAL_ABSORB_AMOUNT_CHANGED", self, "UpdateFrame")
	frame:RegisterUnitEvent("UNIT_HEAL_PREDICTION", self, "UpdateFrame")
	frame:RegisterUnitEvent("UNIT_CONNECTION", self, "UpdateFrame")

	frame:RegisterUpdateFunc(self, "UpdateFrame")
end

function HealAbsorb:UpdateFrame(frame)
	if( not frame.visibility[self.frameKey] or not frame.visibility.healthBar or not frame[self.frameKey] ) then return end

	local _, _, healAbsorbs = ShadowUF.IncHeal.GetAmounts(frame)
	self:PositionBar(frame, healAbsorbs)
end
