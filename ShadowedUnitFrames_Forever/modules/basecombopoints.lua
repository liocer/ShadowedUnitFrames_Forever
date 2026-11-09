--[[
	Shared code for point displays (combo points), shown as a bar of blocks or as icons.
	Originally by Shadowed. SUF Forever: the point count may be secret in combat. Then each
	point's alpha comes from its own step curve evaluated by the game on the points percent
	(GetPointAlpha in the module, e.g. UnitPowerPercent with a step at that point), so no Lua
	comparisons happen on the secret count.
]]
local Combo = {isComboPoints = true}
ShadowUF.ComboPoints = Combo
local Secrets = ShadowUF.Secrets
local issecretvalue = Secrets.IsSecret

-- Step curves: curve i is 0 below i points out of max and 1 from there on
local stepCurves = {}
function Combo.GetStepCurve(id, max)
	stepCurves[max] = stepCurves[max] or {}
	local curve = stepCurves[max][id]
	if( curve == nil ) then
		curve = Secrets.CreateStepCurve((id - 0.5) / max) or false
		stepCurves[max][id] = curve
	end
	return curve or nil
end

local function createIcons(config, pointsFrame)
	local point, relativePoint, x, y
	local pointsConfig = pointsFrame.cpConfig

	if( config.growth == "LEFT" ) then
		point, relativePoint = "BOTTOMRIGHT", "BOTTOMLEFT"
		x = config.spacing
	elseif( config.growth == "UP" ) then
		point, relativePoint = "BOTTOMLEFT", "TOPLEFT"
		y = config.spacing
	elseif( config.growth == "DOWN" ) then
		point, relativePoint = "TOPLEFT", "BOTTOMLEFT"
		y = config.spacing
	else
		point, relativePoint = "BOTTOMLEFT", "BOTTOMRIGHT"
		x = config.spacing
	end

	x = x or 0
	y = y or 0

	for id=1, pointsConfig.max do
		pointsFrame.icons[id] = pointsFrame.icons[id] or pointsFrame:CreateTexture(nil, "OVERLAY")
		local texture = pointsFrame.icons[id]
		texture:SetTexture(pointsConfig.icon)
		texture:SetSize(config.size or 16, config.size or 16)

		if( id > 1 ) then
			texture:ClearAllPoints()
			texture:SetPoint(point, pointsFrame.icons[id - 1], relativePoint, x, y)
		else
			texture:ClearAllPoints()
			texture:SetPoint("CENTER", pointsFrame, "CENTER", 0, 0)
		end
	end
end

local function createBlocks(config, pointsFrame)
	local pointsConfig = pointsFrame.cpConfig
	if pointsConfig.max == 0 then return end
	pointsFrame.visibleBlocks = pointsConfig.max

	-- Position bars, the 5 accounts for borders
	local blockWidth = (pointsFrame:GetWidth() - ((pointsConfig.max / (pointsConfig.grouping or 1)) - 1)) / pointsConfig.max
	for id=1, pointsConfig.max do
		pointsFrame.blocks[id] = pointsFrame.blocks[id] or pointsFrame:CreateTexture(nil, "OVERLAY")
		local texture = pointsFrame.blocks[id]
		local color = ShadowUF.db.profile.powerColors[pointsConfig.colorKey or "COMBOPOINTS"]
		texture:SetVertexColor(color.r, color.g, color.b, color.a)
		texture:SetHorizTile(false)
		texture:SetTexture(ShadowUF.Layout.mediaPath.statusbar)
		texture:SetHeight(pointsFrame:GetHeight())
		texture:SetWidth(blockWidth)
		texture:ClearAllPoints()

		if not texture.background and config.background then
			texture.background = pointsFrame:CreateTexture(nil, "BORDER")
			texture.background:SetHeight(1)
			texture.background:SetWidth(1)
			texture.background:SetAllPoints(texture)
			texture.background:SetHorizTile(false)
			texture.background:SetVertexColor(color.r, color.g, color.b, ShadowUF.db.profile.bars.backgroundAlpha)
			texture.background:SetTexture(ShadowUF.Layout.mediaPath.statusbar)
		end

		if texture.background then
			texture.background:SetShown(config.background)
		end

		local offset = 1
		if pointsConfig.grouping and ((id - 1) % pointsConfig.grouping ~= 0) then
			offset = 0
		end
		if( config.growth == "LEFT" ) then
			if( id > 1 ) then
				texture:SetPoint("TOPRIGHT", pointsFrame.blocks[id - 1], "TOPLEFT", -offset, 0)
			else
				texture:SetPoint("TOPRIGHT", pointsFrame, "TOPRIGHT", 0, 0)
			end
		else
			if( id > 1 ) then
				texture:SetPoint("TOPLEFT", pointsFrame.blocks[id - 1], "TOPRIGHT", offset, 0)
			else
				texture:SetPoint("TOPLEFT", pointsFrame, "TOPLEFT", 0, 0)
			end
		end
	end
end

function Combo:OnLayoutApplied(frame, config)
	local key = self:GetComboPointType()
	local pointsFrame = frame[key]
	if( not pointsFrame ) then return end

	pointsFrame:SetFrameLevel(frame.topFrameLevel + 1)

	local pointsConfig = pointsFrame.cpConfig
	config = config[key]

	-- Not a bar so set the containers frame configuration
	if( config and not config.isBar ) then
		ShadowUF.Layout:ToggleVisibility(pointsFrame, frame.visibility[key])
	end

	if( not frame.visibility[key] ) then return end

	-- Hide the active combo points
	if( pointsFrame.points ) then
		for _, texture in pairs(pointsFrame.points) do
			texture:Hide()
			texture:ClearAllPoints()
		end
	end

	-- Setup for bar display!
	if( config.isBar ) then
		pointsFrame.blocks = pointsFrame.blocks or {}
		pointsFrame.points = pointsFrame.blocks

		createBlocks(config, pointsFrame, pointsConfig.max)

	-- guess not, will have to do icons :(
	else
		pointsFrame.icons = pointsFrame.icons or {}
		pointsFrame.points = pointsFrame.icons

		createIcons(config, pointsFrame, pointsConfig.max)

		-- Position the main frame
		pointsFrame:SetSize(0.1, 0.1)

		ShadowUF.Layout:AnchorFrame(frame, pointsFrame, config)
	end
end

function Combo:OnDisable(frame)
	frame:UnregisterAll(self)
end

function Combo:UpdateBarBlocks(frame, event, unit, powerType)
	local key = self:GetComboPointType()
	local pointsFrame = frame[key]
	if( not pointsFrame or not pointsFrame.cpConfig.eventType or not pointsFrame.blocks ) then return end
	if( event and powerType ~= pointsFrame.cpConfig.eventType ) then return end

	local max = self.GetMaxPoints and self:GetMaxPoints() or UnitPowerMax("player", pointsFrame.cpConfig.powerType)
	max = Secrets.Plain(max, pointsFrame.cpConfig.max)
	if( not max or max == 0 or pointsFrame.visibleBlocks == max ) then return end

	pointsFrame.cpConfig.max = max

	if( not ShadowUF.db.profile.units[frame.unitType][key].isBar ) then
		createIcons(ShadowUF.db.profile.units[frame.unitType][key], pointsFrame)
		pointsFrame.visibleBlocks = max
		return
	else
		createBlocks(ShadowUF.db.profile.units[frame.unitType][key], pointsFrame)
		pointsFrame.visibleBlocks = max
	end

	local blockWidth = (pointsFrame:GetWidth() - (max - 1)) / max
	for id=1, max do
		pointsFrame.blocks[id]:SetWidth(blockWidth)
		pointsFrame.blocks[id]:Show()
	end

	for id=max+1, #pointsFrame.blocks do
		pointsFrame.blocks[id]:Hide()
	end

end

function Combo:Update(frame, event, unit, powerType)
	local key = self:GetComboPointType()
	-- Anything power based will have an eventType to filter on
	if( event and frame[key].cpConfig.eventType and frame[key].cpConfig.eventType ~= powerType ) then return end

	if( not frame[key].points ) then return end
	local points = self:GetPoints(unit)
	local config = ShadowUF.db.profile.units[frame.unitType][key]

	-- Secret count: every point is shown and lit (alpha 1) or not (alpha 0) by its step curve.
	-- The bar can't be hidden on a secret count, so it stays up.
	if( issecretvalue(points) ) then
		if( config.isBar ) then
			ShadowUF.Layout:SetBarVisibility(frame, key, true)
		end

		local max = frame[key].cpConfig.max or 5
		for id, pointTexture in pairs(frame[key].points) do
			-- GetPointAlpha returns 0 - 1, maybe secret; SetAlpha takes it as is
			pointTexture:Show()
			if( not self.GetPointAlpha or not pcall(pointTexture.SetAlpha, pointTexture, self:GetPointAlpha(id, max)) ) then
				pointTexture:SetAlpha(0)
			end
		end
		return
	end

	points = points or 0

	-- Bar display, hide it if we don't have any combo points
	if( config.isBar ) then
		ShadowUF.Layout:SetBarVisibility(frame, key, config.showAlways or points > 0)
	end

	for id, pointTexture in pairs(frame[key].points) do
		pointTexture:SetAlpha(1)
		if( id <= points ) then
			pointTexture:Show()
		else
			pointTexture:Hide()
		end
	end
end

function Combo:OnLayoutWidgets(frame)
	local key = self:GetComboPointType()
	if( not frame.visibility[key] or not ShadowUF.db.profile.units[frame.unitType][key].isBar or not frame[key].blocks) then return end

	local height = frame[key]:GetHeight()
	for _, block in pairs(frame[key].blocks) do
		block:SetHeight(height)
	end
end
