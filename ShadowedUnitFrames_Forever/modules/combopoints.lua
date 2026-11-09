--[[
	Combo points, SUF Forever: they live on the target (vanilla style), like Blizzard's
	TargetBoundComboPointBar: GetComboPoints("player", "target"), updated on power events,
	target changes and COMBO_TARGET_CHANGED (points moved to a new target keep their count, so
	no power event fires). Shown for rogues, and for druids in cat form.

	In combat the count may be secret; each point then lights up through its own step curve
	on UnitPowerPercent(player, ComboPoints) (see basecombopoints.lua), as RobUI does.
]]
if( not ShadowUF.ComboPoints ) then return end

local Combo = setmetatable({}, {__index = ShadowUF.ComboPoints})
ShadowUF:RegisterModule(Combo, "comboPoints", ShadowUF.L["Combo points"])

local Secrets = ShadowUF.Secrets
local issecretvalue = Secrets.IsSecret
local COMBO = Enum.PowerType.ComboPoints or 4
local ENERGY = Enum.PowerType.Energy or 3
local MAX_POINTS = MAX_COMBO_POINTS or 5
local playerClass = select(2, UnitClass("player"))
local hasPoints = playerClass == "ROGUE" or playerClass == "DRUID"

local cpConfig = {max = MAX_POINTS, key = "comboPoints", colorKey = "COMBOPOINTS", powerType = COMBO, eventType = "COMBO_POINTS", icon = "Interface\\AddOns\\ShadowedUnitFrames_Forever\\media\\textures\\combo"}

function Combo:OnEnable(frame)
	frame.comboPoints = frame.comboPoints or CreateFrame("Frame", nil, frame)
	frame.comboPoints.cpConfig = cpConfig
	cpConfig.max = self:GetMaxPoints()

	frame:RegisterNormalEvent("UNIT_POWER_UPDATE", self, "Update", "player")
	frame:RegisterNormalEvent("UNIT_POWER_FREQUENT", self, "Update", "player")
	frame:RegisterNormalEvent("UNIT_MAXPOWER", self, "UpdateBarBlocks", "player")
	frame:RegisterNormalEvent("PLAYER_TARGET_CHANGED", self, "UpdateAll")
	frame:RegisterNormalEvent("COMBO_TARGET_CHANGED", self, "UpdateAll")
	if( playerClass == "DRUID" ) then
		frame:RegisterNormalEvent("UPDATE_SHAPESHIFT_FORM", self, "UpdateAll")
	end

	frame:RegisterUpdateFunc(self, "Update")
	frame:RegisterUpdateFunc(self, "UpdateBarBlocks")
end

function Combo:GetComboPointType()
	return "comboPoints"
end

function Combo:GetMaxPoints()
	local max = Secrets.Plain(UnitPowerMax("player", COMBO))
	if( not max or max <= 0 ) then max = MAX_POINTS end
	return math.min(max, MAX_POINTS)
end

-- Druids only have combo points in cat form (energy)
local function isActive()
	if( not hasPoints ) then return false end
	if( playerClass == "DRUID" ) then
		return Secrets.Plain(UnitPowerType("player")) == ENERGY
	end
	return true
end

-- Plain number, or a secret one in combat
function Combo:GetPoints(unit)
	if( not isActive() or not UnitExists("target") ) then return 0 end

	local points = GetComboPoints("player", "target")
	if( not issecretvalue(points) ) then return points or 0 end

	-- The count's secret: the game's percent (and step curves on it) still work
	return points
end

-- Alpha (0 or 1, maybe secret) for point `id` out of `max` when the count is secret
function Combo:GetPointAlpha(id, max)
	local curve = UnitPowerPercent and ShadowUF.ComboPoints.GetStepCurve(id, max)
	if( not curve ) then return 0 end

	local ok, alpha = pcall(UnitPowerPercent, "player", COMBO, false, curve)
	if( not ok ) then return 0 end
	return alpha
end

-- Target / form changes: no power type to filter on
function Combo:UpdateAll(frame)
	ShadowUF.ComboPoints.Update(self, frame)
end

function Combo:Update(frame, event, unit, powerType)
	if( not event or ( unit == frame.unit or unit == "player" ) ) then
		ShadowUF.ComboPoints.Update(self, frame, event, unit, powerType)
	end
end
