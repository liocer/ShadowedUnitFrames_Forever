-- Druid mana bar: your mana while you're in bear or cat form (which use rage / energy).
-- Mana may be secret in combat; it goes straight into the bar.
local Druid = {}
local Secrets = ShadowUF.Secrets
local MANA = Enum.PowerType.Mana
ShadowUF:RegisterModule(Druid, "druidBar", ShadowUF.L["Druid mana bar"], true, "DRUID")

function Druid:OnEnable(frame)
	frame.druidBar = frame.druidBar or ShadowUF.Units:CreateBar(frame)

	frame:RegisterUnitEvent("UNIT_DISPLAYPOWER", self, "PowerChanged")
	frame:RegisterNormalEvent("UPDATE_SHAPESHIFT_FORM", self, "PowerChanged")

	frame:RegisterUpdateFunc(self, "PowerChanged")
	frame:RegisterUpdateFunc(self, "Update")
end

function Druid:OnDisable(frame)
	frame:UnregisterAll(self)
end

function Druid:OnLayoutApplied(frame)
	if( not frame.visibility.druidBar ) then return end

	local color = ShadowUF.db.profile.powerColors.MANA
	frame:SetBarColor("druidBar", color.r, color.g, color.b)
end

function Druid:PowerChanged(frame)
	local powerType = Secrets.Plain(UnitPowerType(frame.unit), MANA)
	local visible = powerType ~= MANA and not frame.inVehicle
	local type = visible and "RegisterUnitEvent" or "UnregisterSingleEvent"

	frame[type](frame, "UNIT_POWER_FREQUENT", self, "Update")
	frame[type](frame, "UNIT_MAXPOWER", self, "Update")
	ShadowUF.Layout:SetBarVisibility(frame, "druidBar", visible)

	if( visible ) then self:Update(frame) end

	-- The cost preview moves between the power and druid mana bars with the form
	if( frame.visibility.powerPrediction and ShadowUF.modules.powerPrediction ) then
		ShadowUF.modules.powerPrediction:Update(frame)
	end
end

function Druid:Update(frame, event, unit, powerType)
	if( powerType and powerType ~= "MANA" ) then return end

	local unitID = frame.unit
	local empty = UnitIsDeadOrGhost(unitID) or not UnitIsConnected(unitID)
	frame.druidBar.exactValues = Secrets.SetBar(frame.druidBar, empty and 0 or UnitPower(unitID, MANA), UnitPowerMax(unitID, MANA), function()
		if( empty ) then return 0 end
		return Secrets.PowerPercent(unitID, MANA)
	end)
end
