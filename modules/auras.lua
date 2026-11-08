--[[
	Buff and debuff icons. Originally by Shadowed (Shadowed Unit Frames), ported to WoW Forever.

	Secret values: in combat the game hides most aura fields from addons (name, spellId,
	applications, duration, expirationTime, dispelName, sourceUnit, ...). The aura instance
	ID stays readable, so everything here works off instance IDs:
	- categories ("your auras", "curable/castable", ...) come from the game's own filter
	  strings ("HELPFUL|PLAYER", "HARMFUL|RAID", ...) via C_UnitAuras.GetUnitAuraInstanceIDs,
	- timers come from duration objects (C_UnitAuras.GetAuraDuration +
	  Cooldown:SetCooldownFromDurationObject),
	- stack text from C_UnitAuras.GetAuraApplicationDisplayCount,
	- border colours from C_UnitAuras.GetAuraDispelTypeColor with a colour curve,
	- name/spell ID white/black/override lists only apply while an aura can be read, or to
	  auras we already saw while they were readable (cached by instance ID). Otherwise the
	  aura falls through to the normal category filters.
	When nothing is secret (out of combat, most NPCs) everything behaves like upstream SUF.
]]
local Auras = {}
ShadowUF.Auras = Auras

local playerUnits = {player = true, vehicle = true, pet = true}
local mainHand, offHand, tempEnchantScan = {time = 0}, {time = 0}
local issecretvalue = issecretvalue or function() return false end
local pcall, pairs, ipairs, type, tostring = pcall, pairs, ipairs, type, tostring
-- CancelUnitBuff and GetInventoryItemTexture aren't in the API docs, but Blizzard_BuffFrame calls them on this build
local CancelUnitBuff = CancelUnitBuff -- luacheck: ignore 113
local GetInventoryItemTexture = GetInventoryItemTexture -- luacheck: ignore 113
ShadowUF:RegisterModule(Auras, "auras", ShadowUF.L["Auras"])

-- The plain value, or nil if it's secret
local function plain(value)
	if( issecretvalue(value) ) then return nil end
	return value
end

---------------------------------------------------------------------------
-- Shared helpers (also used by the aura indicators and highlight modules)
---------------------------------------------------------------------------

-- DebuffTypeColor is gone in this client. These are the classic DebuffTypeColor values.
Auras.debuffColors = {
	none = {r = 0.80, g = 0, b = 0},
	Magic = {r = 0.20, g = 0.60, b = 1.00},
	Curse = {r = 0.60, g = 0.00, b = 1.00},
	Disease = {r = 0.60, g = 0.40, b = 0},
	Poison = {r = 0.00, g = 0.60, b = 0},
}
Auras.debuffColors[""] = Auras.debuffColors.none

-- Dispel type IDs as used by C_UnitAuras.GetAuraDispelTypeColor (the curve's x value)
local dispelTypeIDs = {none = 0, Magic = 1, Curse = 2, Disease = 3, Poison = 4, Enrage = 9, Bleed = 11}
Auras.dispelTypeIDs = dispelTypeIDs

-- Step colour curve: dispel type ID -> colour, so a secret dispel type still gives a colour
local dispelCurve
function Auras:GetDispelColorCurve()
	if( dispelCurve ~= nil ) then return dispelCurve or nil end
	dispelCurve = false
	if( not C_CurveUtil or not C_CurveUtil.CreateColorCurve or not CreateColor ) then return nil end

	local ok, curve = pcall(function()
		local c = C_CurveUtil.CreateColorCurve()
		if( Enum.LuaCurveType and Enum.LuaCurveType.Step ) then c:SetType(Enum.LuaCurveType.Step) end
		local none = Auras.debuffColors.none
		local points = {
			{0, none}, {1, Auras.debuffColors.Magic}, {2, Auras.debuffColors.Curse}, {3, Auras.debuffColors.Disease},
			{4, Auras.debuffColors.Poison}, {5, none}, {9, none}, {11, none}, {12, none},
		}
		for _, point in ipairs(points) do
			c:AddPoint(point[1], CreateColor(point[2].r, point[2].g, point[2].b, 1))
		end
		return c
	end)

	if( ok and curve ) then dispelCurve = curve end
	return dispelCurve or nil
end

-- Border colour for an aura's dispel type, r, g, b (may be secret numbers).
-- dispelName is the known (non secret) dispel type if we have one, auraData the raw aura.
function Auras:GetDispelColor(unit, auraData, dispelName)
	if( dispelName == nil and auraData ) then
		dispelName = auraData.dispelName
		if( issecretvalue(dispelName) ) then
			local id, curve = auraData.auraInstanceID, self:GetDispelColorCurve()
			if( curve and id and not issecretvalue(id) and C_UnitAuras.GetAuraDispelTypeColor ) then
				local ok, r, g, b = pcall(function()
					local color = C_UnitAuras.GetAuraDispelTypeColor(unit, id, curve)
					return color.r, color.g, color.b
				end)
				if( ok ) then return r, g, b end
			end

			dispelName = nil
		end
	end

	local color = dispelName and self.debuffColors[dispelName] or self.debuffColors.none
	return color.r, color.g, color.b
end

-- Fills tbl with [auraInstanceID] = true for every aura that passes the filter.
-- Returns nil if the game couldn't answer (API missing, bad filter).
function Auras:GetFilterSet(unit, filter, tbl)
	tbl = tbl or {}
	for k in pairs(tbl) do tbl[k] = nil end
	if( not C_UnitAuras.GetUnitAuraInstanceIDs ) then return nil end

	local ok, ids = pcall(C_UnitAuras.GetUnitAuraInstanceIDs, unit, filter)
	if( not ok or type(ids) ~= "table" ) then return nil end
	for _, id in ipairs(ids) do
		if( not issecretvalue(id) ) then tbl[id] = true end
	end
	return tbl
end

-- Whether a single aura passes a filter string; nil if it can't be told
function Auras:PassesFilter(unit, auraInstanceID, filter)
	if( not auraInstanceID or issecretvalue(auraInstanceID) or not C_UnitAuras.IsAuraFilteredOutByInstanceID ) then return nil end
	local ok, filtered = pcall(C_UnitAuras.IsAuraFilteredOutByInstanceID, unit, auraInstanceID, filter)
	if( not ok or issecretvalue(filtered) ) then return nil end
	return not filtered
end

-- Stack count text ("" for less than 2 stacks); may be a secret string, which SetText accepts
function Auras:GetStackText(unit, auraData)
	local count = auraData.applications
	if( not issecretvalue(count) ) then
		return count and count > 1 and count or ""
	end

	local id = auraData.auraInstanceID
	if( id and not issecretvalue(id) and C_UnitAuras.GetAuraApplicationDisplayCount ) then
		local ok, text = pcall(C_UnitAuras.GetAuraApplicationDisplayCount, unit, id, 2)
		if( ok and text ) then return text end
	end
	return ""
end

-- Starts a cooldown swipe for the aura. Returns false if the aura has no timer (as far as we can tell).
function Auras:SetCooldown(cooldown, unit, auraData)
	local duration, expiration = auraData.duration, auraData.expirationTime
	if( not issecretvalue(duration) and not issecretvalue(expiration) ) then
		if( duration and expiration and duration > 0 and expiration > 0 ) then
			cooldown:SetCooldown(expiration - duration, duration)
			cooldown:Show()
			return true
		end
		cooldown:Hide()
		return false
	end

	-- Secret: let the game feed the swipe from a duration object, it clears itself for permanent auras
	local id = auraData.auraInstanceID
	if( id and not issecretvalue(id) and C_UnitAuras.GetAuraDuration and cooldown.SetCooldownFromDurationObject ) then
		local ok = pcall(function()
			local durationObject = C_UnitAuras.GetAuraDuration(unit, id)
			cooldown:Show()
			cooldown:SetCooldownFromDurationObject(durationObject, true)
		end)
		if( ok ) then return true end
	end

	cooldown:Hide()
	return false
end

-- Readable copy of the parts of an aura that filtering needs. Fields are nil when secret.
-- `info` is the table we kept for this aura instance ID (or a new one): if the aura was
-- readable before (out of combat) and is secret now, the old readable values are kept and
-- info.cached is set, so name lists still apply to it in combat.
local function readAura(info, auraData)
	local name, spellID = auraData.name, auraData.spellId
	if( not issecretvalue(name) and not issecretvalue(spellID) ) then
		info.name = name
		info.spellID = spellID and tostring(spellID)
		info.boss = plain(auraData.isBossAura)
		info.stealable = plain(auraData.isStealable)
		info.dispelName = plain(auraData.dispelName)
		info.dispelKnown = not issecretvalue(auraData.dispelName)
		local source = plain(auraData.sourceUnit)
		info.fromPlayer = (source and playerUnits[source]) or plain(auraData.isFromPlayerOrPlayerPet) or nil
		info.readable = true
		info.cached = nil
	elseif( info.readable or info.cached ) then
		info.readable = nil
		info.cached = true
	else
		info.name, info.spellID = nil, nil
		info.boss = plain(auraData.isBossAura)
		info.stealable = plain(auraData.isStealable)
		info.dispelName = plain(auraData.dispelName)
		info.dispelKnown = not issecretvalue(auraData.dispelName)
		info.fromPlayer = plain(auraData.isFromPlayerOrPlayerPet)
	end

	return info
end
Auras.ReadAura = readAura

function Auras:OnEnable(frame)
	frame.auras = frame.auras or {}
	frame.auras.shown = frame.auras.shown or {}
	frame.auras.known = frame.auras.known or {}
	frame.auras.seen = frame.auras.seen or {}
	frame.auras.sets = frame.auras.sets or {buffs = {}, debuffs = {}}

	frame:RegisterNormalEvent("PLAYER_ENTERING_WORLD", self, "Update")
	frame:RegisterUnitEvent("UNIT_AURA", self, "UpdateAuras")
	frame:RegisterUpdateFunc(self, "Update")

	self:UpdateFilter(frame)
end

function Auras:OnDisable(frame)
	frame:UnregisterAll(self)
end

-- Aura positioning code
-- Definitely some of the more unusual code I've done, not sure I really like this method
-- but it does allow more flexibility with how things are anchored without me having to hardcode the 10 different growth methods
local function load(text)
	local result, err = loadstring(text)
	if( err ) then
		error(err, 3)
		return nil
	end

	return result()
end

local positionData = setmetatable({}, {
	__index = function(tbl, index)
		local data = {}
		local columnGrowth = ShadowUF.Layout:GetColumnGrowth(index)
		local auraGrowth = ShadowUF.Layout:GetAuraGrowth(index)
		data.xMod = (columnGrowth == "RIGHT" or auraGrowth == "RIGHT") and 1 or -1
		data.yMod = (columnGrowth ~= "TOP" and auraGrowth ~= "TOP") and -1 or 1

		local auraX, colX, auraY, colY, xOffset, yOffset, initialXOffset, initialYOffset = 0, 0, 0, 0, "", "", "", ""
		if( columnGrowth == "LEFT" or columnGrowth == "RIGHT" ) then
			colX = 1
			xOffset = " + offset"
			initialXOffset = string.format(" + (%d * offset)", data.xMod)
			auraY = 3
			data.isSideGrowth = true
		elseif( columnGrowth == "TOP" or columnGrowth == "BOTTOM" ) then
			colY = 2
			yOffset = " + offset"
			initialYOffset = string.format(" + (%d * offset)", data.yMod)
			auraX = 2
		end

		data.initialAnchor = load(string.format([[return function(button, offset)
			button:ClearAllPoints()
			button:SetPoint(button.point, button.anchorTo, button.relativePoint, button.xOffset%s, button.yOffset%s)
			button.anchorOffset = offset
		end]], initialXOffset, initialYOffset))
		data.column = load(string.format([[return function(button, positionTo, offset)
			button:ClearAllPoints()
			button:SetPoint("%s", positionTo, "%s", %d * (%d%s), %d * (%d%s)) end
		]], ShadowUF.Layout:ReverseDirection(columnGrowth), columnGrowth, data.xMod, colX, xOffset, data.yMod, colY, yOffset))
		data.aura = load(string.format([[return function(button, positionTo)
			button:ClearAllPoints()
			button:SetPoint("%s", positionTo, "%s", %d, %d) end
		]], ShadowUF.Layout:ReverseDirection(auraGrowth), auraGrowth, data.xMod * auraX, data.yMod * auraY))

		tbl[index] = data
		return tbl[index]
	end,
})

local function positionButton(id,  group, config)
	local position = positionData[group.forcedAnchorPoint or config.anchorPoint]
	local button = group.buttons[id]
	button.isAuraAnchor = nil

	-- Alright, in order to find out where an aura group is going to be anchored to certain buttons need
	-- to be flagged as suitable anchors visually, this speeds it up because this data is cached and doesn't
	-- have to be recalculated unless auras are specifically changed
	if( id > 1 ) then
		if( position.isSideGrowth and id <= config.perRow ) then
			button.isAuraAnchor = true
		end

		if( id % config.perRow == 1 or config.perRow == 1 ) then
			position.column(button, group.buttons[id - config.perRow], 0)

			if( not position.isSideGrowth ) then
				button.isAuraAnchor = true
			end
		else
			position.aura(button, group.buttons[id - 1])
		end
	else
		button.isAuraAnchor = true
		button.point = ShadowUF.Layout:GetPoint(config.anchorPoint)
		button.relativePoint = ShadowUF.Layout:GetRelative(config.anchorPoint)
		button.xOffset = config.x + (position.xMod * ShadowUF.db.profile.backdrop.inset)
		button.yOffset = config.y + (position.yMod * ShadowUF.db.profile.backdrop.inset)
		button.anchorTo = group.anchorTo

		position.initialAnchor(button, 0)
	end
end


local columnsHaveScale = {}
local function positionAllButtons(group, config)
	local position = positionData[group.forcedAnchorPoint or config.anchorPoint]

	-- Figure out which columns have scaling so we can work out positioning
	local columnID = 0
	for id, button in pairs(group.buttons) do
		if( id % config.perRow == 1 or config.perRow == 1 ) then
			columnID = columnID + 1
			columnsHaveScale[columnID] = nil
		end

		if( not columnsHaveScale[columnID] and button.isSelfScaled ) then
			local size = math.ceil(button:GetSize() * button:GetScale())
			columnsHaveScale[columnID] = columnsHaveScale[columnID] and math.max(size, columnsHaveScale[columnID]) or size
		end
	end

	columnID = 1
	for id, button in pairs(group.buttons) do
		if( id > 1 ) then
			if( id % config.perRow == 1 or config.perRow == 1 ) then
				columnID = columnID + 1

				local anchorButton = group.buttons[id - config.perRow]
				local previousScale, currentScale = columnsHaveScale[columnID - 1], columnsHaveScale[columnID]
				local offset = 0
				-- Previous column has a scaled aura, and the button we are anchoring to is not scaled
				if( previousScale and not anchorButton.isSelfScaled ) then
					offset = (previousScale / 4)
				end

				-- Current column has a scaled aura, and the button isn't scaled
				if( currentScale and not button.isSelfScaled ) then
					offset = offset + (currentScale / 4)
				end

				-- Current anchor is scaled, previous is not
				if( button.isSelfScaled and not anchorButton.isSelfScaled ) then
					offset = offset - (currentScale / 6)
				end

				-- At least one of them is scaled
				if( ( not button.isSelfScaled or not anchorButton.isSelfScaled ) and offset > 0 ) then
					offset = offset + 1
				end

				position.column(button, anchorButton, math.ceil(offset))
			else
				position.aura(button, group.buttons[id - 1])
			end
		else
			-- If the initial column is self scaled, but the initial anchor isn't, will have to reposition it
			local offset = 0
			if( columnsHaveScale[columnID] ) then
				offset = math.ceil(columnsHaveScale[columnID] / 8)
				if( button.isSelfScaled ) then
					offset = -(offset / 2)
				else
					offset = offset + 2
				end

				offset = offset
			end

			if( offset ~= button.anchorOffset ) then
				position.initialAnchor(button, offset)
			end
		end
	end
end

-- Aura button functions
local function setAuraTooltip(self)
	if( self.auraInstanceID and C_UnitAuras.GetAuraDataByAuraInstanceID ) then
		-- Secret auras can't be read by addons at all; the tooltip may refuse them too
		if( self.filter == "HARMFUL" and GameTooltip.SetUnitDebuffByAuraInstanceID ) then
			pcall(GameTooltip.SetUnitDebuffByAuraInstanceID, GameTooltip, self.unit, self.auraInstanceID, self.filter)
			return
		elseif( self.filter == "HELPFUL" and GameTooltip.SetUnitBuffByAuraInstanceID ) then
			pcall(GameTooltip.SetUnitBuffByAuraInstanceID, GameTooltip, self.unit, self.auraInstanceID, self.filter)
			return
		end
	end

	pcall(GameTooltip.SetUnitAura, GameTooltip, self.unit, self.auraID, self.filter)
end

-- Updates the X seconds left on aura tooltip while it's shown
local tooltipElapsed = 0
local function updateTooltip(self, elapsed)
	tooltipElapsed = tooltipElapsed + elapsed
	if( tooltipElapsed < 0.20 ) then return end
	tooltipElapsed = 0

	if( not GameTooltip:IsForbidden() and GameTooltip:IsOwned(self) ) then
		setAuraTooltip(self)
	end
end

local function showTooltip(self)
	if( not ShadowUF.db.profile.locked ) then return end
	if( GameTooltip:IsForbidden() ) then return end

	GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
	if( self.filter == "TEMP" ) then
		GameTooltip:SetInventoryItem("player", self.auraID)
		self:SetScript("OnUpdate", nil)
	else
		setAuraTooltip(self)
		tooltipElapsed = 0
		self:SetScript("OnUpdate", updateTooltip)
	end
end

local function hideTooltip(self)
	self:SetScript("OnUpdate", nil)
	if not GameTooltip:IsForbidden() then
		GameTooltip:Hide()
	end
end

local function isPlayerUnit(unit)
	if( unit == "player" or unit == "vehicle" ) then return true end
	local ok, isUnit = pcall(UnitIsUnit, unit, "player")
	return ok and not issecretvalue(isUnit) and isUnit or false
end

-- Right click cancels your own buffs (and weapon enchants), out of combat only like the default buff frame
local function cancelAura(self, mouse)
	if( mouse ~= "RightButton" or InCombatLockdown() or not isPlayerUnit(self.parent.unit) ) then
		return
	end

	if( self.filter == "TEMP" ) then
		if( C_PaperDollInfo and C_PaperDollInfo.CancelTemporaryEnchantment ) then
			C_PaperDollInfo.CancelTemporaryEnchantment(self.auraID)
		elseif( CancelItemTempEnchantment ) then
			CancelItemTempEnchantment(self.auraID - 15)
		end
		return
	end

	if( self.filter ~= "HELPFUL" or not self.auraID ) then return end

	if( CancelUnitBuff ) then
		CancelUnitBuff(self.parent.unit, self.auraID, self.filter)
	elseif( self.auraInstanceID and C_UnitAuras.CancelAuraByInstanceID ) then
		C_UnitAuras.CancelAuraByInstanceID(self.parent.unit, self.auraInstanceID)
	end
end

local function updateButton(id, group, config)
	local button = group.buttons[id]
	if( not button ) then
		group.buttons[id] = CreateFrame("Button", nil, group)

		button = group.buttons[id]
		button:SetScript("OnEnter", showTooltip)
		button:SetScript("OnLeave", hideTooltip)
		button:RegisterForClicks("RightButtonUp")

		button.cooldown = CreateFrame("Cooldown", group.parent:GetName() .. "Aura" .. group.type .. id .. "Cooldown", button, "CooldownFrameTemplate")
		button.cooldown:SetAllPoints(button)
		button.cooldown:SetReverse(true)
		button.cooldown:SetDrawEdge(false)
		button.cooldown:SetDrawSwipe(true)
		button.cooldown:SetSwipeColor(0, 0, 0, 0.8)
		button.cooldown:Hide()

		button.stack = button:CreateFontString(nil, "OVERLAY")
		button.stack:SetFont("Interface\\AddOns\\ShadowedUnitFrames_Forever\\media\\fonts\\Myriad Condensed Web.ttf", 10, "OUTLINE")
		button.stack:SetShadowColor(0, 0, 0, 1.0)
		button.stack:SetShadowOffset(0.50, -0.50)
		button.stack:SetHeight(1)
		button.stack:SetWidth(1)
		button.stack:SetAllPoints(button)
		button.stack:SetJustifyV("BOTTOM")
		button.stack:SetJustifyH("RIGHT")

		button.border = button:CreateTexture(nil, "OVERLAY")
		button.border:SetPoint("CENTER", button)

		button.icon = button:CreateTexture(nil, "BACKGROUND")
		button.icon:SetAllPoints(button)
		button.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	end

	if( ShadowUF.db.profile.auras.borderType == "" ) then
		button.border:Hide()
	elseif( ShadowUF.db.profile.auras.borderType == "blizzard" ) then
		button.border:SetTexture("Interface\\Buttons\\UI-Debuff-Overlays")
		button.border:SetTexCoord(0.296875, 0.5703125, 0, 0.515625)
		button.border:Show()
	else
		button.border:SetTexture("Interface\\AddOns\\ShadowedUnitFrames_Forever\\media\\textures\\border-" .. ShadowUF.db.profile.auras.borderType)
		button.border:SetTexCoord(0, 1, 0, 1)
		button.border:Show()
	end

	-- Set the button sizing
	button.cooldown.noCooldownCount = ShadowUF.db.profile.omnicc
	button.cooldown:SetHideCountdownNumbers(ShadowUF.db.profile.blizzardcc)
	button:SetHeight(config.size)
	button:SetWidth(config.size)
	button.border:SetHeight(config.size + 1)
	button.border:SetWidth(config.size + 1)
	button.stack:SetFont("Interface\\AddOns\\ShadowedUnitFrames_Forever\\media\\fonts\\Myriad Condensed Web.ttf", math.floor((config.size * 0.60) + 0.5), "OUTLINE")

	button:SetScript("OnClick", cancelAura)
	button.parent = group.parent
	button:ClearAllPoints()
	button:Hide()

	-- Position the button quickly
	positionButton(id, group, config)
end

-- Let the mover access this for creating aura things
Auras.updateButton = updateButton

-- Create an aura anchor as well as the buttons to contain it
local function updateGroup(self, type, config, reverseConfig)
	self.auras[type] = self.auras[type] or CreateFrame("Frame", nil, self.highFrame)

	local group = self.auras[type]
	group.buttons = group.buttons or {}

	group.maxAuras = config.perRow * config.maxRows
	group.totalAuras = 0
	group.temporaryEnchants = 0
	group.lastTemporary = 0
	group.type = type
	group.parent = self
	group.anchorTo = self
	group:SetFrameLevel(self.highFrame:GetFrameLevel() + 1)
	group:Show()

	-- If debuffs are anchored to buffs, debuffs need to grow however buffs do
	if( config.anchorOn and reverseConfig.enabled ) then
		group.forcedAnchorPoint = reverseConfig.anchorPoint
	else
		group.forcedAnchorPoint = nil
	end

	if( self.unit == "player" ) then
		mainHand.time = 0
		offHand.time = 0
		mainHand.has = nil
		offHand.has = nil

		group:SetScript("OnUpdate", config.temporary and tempEnchantScan or nil)
	else
		group:SetScript("OnUpdate", nil)
	end

	-- Update filters used for the anchor
	group.filter = group.type == "buffs" and "HELPFUL" or group.type == "debuffs" and "HARMFUL" or ""

	for id in pairs(group.buttons) do
		updateButton(id, group, config)
	end
end

-- Update aura positions based off of configuration
function Auras:OnLayoutApplied(frame, config)
	if( frame.auras ) then
		if( frame.auras.buffs ) then
			for _, button in pairs(frame.auras.buffs.buttons) do
				button:Hide()
			end
		end
		if( frame.auras.debuffs ) then
			for _, button in pairs(frame.auras.debuffs.buttons) do
				button:Hide()
			end
		end
	end

	if( not frame.visibility.auras ) then return end

	if( config.auras.buffs.enabled ) then
		updateGroup(frame, "buffs", config.auras.buffs, config.auras.debuffs)
	end

	if( config.auras.debuffs.enabled ) then
		updateGroup(frame, "debuffs", config.auras.debuffs, config.auras.buffs)
	end

	-- Anchor an aura group to another aura group
	frame.auras.anchorAurasOn = nil
	if( config.auras.buffs.enabled and config.auras.debuffs.enabled ) then
		if( config.auras.buffs.anchorOn ) then
			frame.auras.anchorAurasOn = frame.auras.debuffs
			frame.auras.anchorAurasChild = frame.auras.buffs
		elseif( config.auras.debuffs.anchorOn ) then
			frame.auras.anchorAurasOn = frame.auras.buffs
			frame.auras.anchorAurasChild = frame.auras.debuffs
		end
	end

	-- Check if either auras are anchored to each other
	if( config.auras.buffs.anchorPoint == config.auras.debuffs.anchorPoint and config.auras.buffs.enabled and config.auras.debuffs.enabled and not config.auras.buffs.anchorOn and not config.auras.debuffs.anchorOn ) then
		frame.auras.anchor = frame.auras[config.auras.buffs.prioritize and "buffs" or "debuffs"]
		frame.auras.primary = config.auras.buffs.prioritize and "buffs" or "debuffs"
		frame.auras.secondary = frame.auras.primary == "buffs" and "debuffs" or "buffs"
	else
		frame.auras.anchor = nil
	end

	self:UpdateFilter(frame)
end

-- Temporary enchant support
-- Returns hasEnchant, timeLeft (ms), charges, enchantID for an inventory slot (16 main hand, 17 off hand)
local function getTemporaryEnchant(slot)
	if( C_PaperDollInfo and C_PaperDollInfo.GetTemporaryEnchantmentInfo ) then
		local ok, info = pcall(C_PaperDollInfo.GetTemporaryEnchantmentInfo, slot)
		if( ok ) then
			if( type(info) == "table" ) then
				return true, plain(info.remainingTimeMs) or 0, plain(info.chargesRemaining) or 0, plain(info.enchantID)
			end
			return false
		end
	end

	if( C_Item and C_Item.GetWeaponEnchantInfo and Enum.WeaponSlot ) then
		local ok, enchants = pcall(C_Item.GetWeaponEnchantInfo, slot == 16 and Enum.WeaponSlot.MainHand or Enum.WeaponSlot.OffHand)
		if( ok and type(enchants) == "table" ) then
			for _, enchant in pairs(enchants) do
				if( plain(enchant.hasEnchant) ) then
					return true, plain(enchant.timeLeft) or 0, plain(enchant.charges) or 0, plain(enchant.enchantID)
				end
			end
			return false
		end
	end

	if( GetWeaponEnchantInfo ) then
		local hasMain, mainTimeLeft, mainCharges, mainEnchantId, hasOff, offTimeLeft, offCharges, offEnchantId = GetWeaponEnchantInfo()
		if( slot == 16 ) then
			return hasMain, mainTimeLeft or 0, mainCharges or 0, mainEnchantId
		end
		return hasOff, offTimeLeft or 0, offCharges or 0, offEnchantId
	end

	return false
end

local timeElapsed = 0
local function updateTemporaryEnchant(frame, slot, tempData, hasEnchant, enchantId, timeLeft, charges)
	-- If there's less than a 750 millisecond differences in the times, we don't need to bother updating.
	-- Any sort of enchant takes more than 0.750 seconds to cast so it's impossible for the user to have two
	-- temporary enchants with that little difference, as totems don't really give pulsing auras anymore.
	charges = charges or 0
	if( tempData.has and tempData.enchantId == enchantId and ( timeLeft < tempData.time and ( tempData.time - timeLeft ) < 750 ) ) then return false end

	-- Some trickys magic, we can't get the start time of temporary enchants easily.
	-- So will save the first time we find when a new enchant is added
	if( timeLeft > tempData.time or not tempData.has ) then
		tempData.startTime = GetTime()
	end

	tempData.has = hasEnchant
	tempData.time = timeLeft
	tempData.charges = charges
	tempData.enchantId = enchantId

	local config = ShadowUF.db.profile.units[frame.parent.unitType].auras[frame.type]

	-- Create any buttons we need
	if( #(frame.buttons) < frame.temporaryEnchants ) then
		updateButton(frame.temporaryEnchants, frame, config)
	end

	local button = frame.buttons[frame.temporaryEnchants]

	-- Purple border
	button.border:SetVertexColor(0.50, 0, 0.50)

	-- Show the cooldown ring
	if( not ShadowUF.db.profile.auras.disableCooldown and timeLeft > 0 ) then
		button.cooldown:SetCooldown(tempData.startTime, timeLeft / 1000)
		button.cooldown:Show()
	else
		button.cooldown:Hide()
	end

	-- Enlarge our own auras
	if( config.enlarge.SELF ) then
		button.isSelfScaled = true
		button:SetScale(config.selfScale)
	else
		button.isSelfScaled = nil
		button:SetScale(1)
	end

	-- Size it
	button:SetHeight(config.size)
	button:SetWidth(config.size)
	button.border:SetHeight(config.size + 1)
	button.border:SetWidth(config.size + 1)

	-- Stack + icon + show! Never understood why, auras sometimes return 1 for stack even if they don't stack
	button.auraID = slot
	button.auraInstanceID = nil
	button.filter = "TEMP"
	button.unit = nil
	button.columnHasScaled = nil
	button.previousHasScale = nil
	button.icon:SetTexture(GetInventoryItemTexture("player", slot))
	button.stack:SetText(charges > 1 and charges or "")
	button:Show()
end

-- Unfortunately, temporary enchants have basically no support beyond hacks. So we will hack!
tempEnchantScan = function(self, elapsed)
	if( self.parent.unit == self.parent.vehicleUnit and self.lastTemporary > 0 ) then
		mainHand.has = false
		offHand.has = false

		self.temporaryEnchants = 0
		self.lastTemporary = 0

		Auras:Update(self.parent)
		return
	end

	timeElapsed = timeElapsed + elapsed
	if( timeElapsed < 0.50 ) then return end
	timeElapsed = timeElapsed - 0.50

	local hasMain, mainTimeLeft, mainCharges, mainEnchantId = getTemporaryEnchant(16)
	local hasOff, offTimeLeft, offCharges, offEnchantId = getTemporaryEnchant(17)
	self.temporaryEnchants = 0

	if( hasMain ) then
		self.temporaryEnchants = self.temporaryEnchants + 1
		updateTemporaryEnchant(self, 16, mainHand, hasMain, mainEnchantId, mainTimeLeft or 0, mainCharges)
		mainHand.time = mainTimeLeft or 0
	end

	mainHand.has = hasMain

	if( hasOff and self.temporaryEnchants < self.maxAuras ) then
		self.temporaryEnchants = self.temporaryEnchants + 1
		updateTemporaryEnchant(self, 17, offHand, hasOff, offEnchantId, offTimeLeft or 0, offCharges)
		offHand.time = offTimeLeft or 0
	end

	offHand.has = hasOff

	-- Update if totals changed
	if( self.lastTemporary ~= self.temporaryEnchants ) then
		self.lastTemporary = self.temporaryEnchants
		Auras:Update(self.parent)
	end
end

-- Nice and simple, don't need to do a full update because either this is called in an OnEnable or
-- the zone monitor will handle it all cleanly. The fun part of this code is aura filtering itself takes 10 seconds
-- but making the configuration clean takes two weeks and another 2-3 days of implementing
-- This isn't actually filled with data, it's just to stop any errors from triggering if no filter is added
local filterDefault = {}
function Auras:UpdateFilter(frame)
	local zone = select(2, IsInInstance()) or "none"
	if( zone == "scenario" ) then zone = "party" end
	if( zone == "interior" ) then zone = "neighborhood" end

	local white = ShadowUF.db.profile.filters.zonewhite[zone .. frame.unitType]
	local black = ShadowUF.db.profile.filters.zoneblack[zone .. frame.unitType]
	local override = ShadowUF.db.profile.filters.zoneoverride[zone .. frame.unitType]
	frame.auras.whitelist = white and ShadowUF.db.profile.filters.whitelists[white] or filterDefault
	frame.auras.blacklist = black and ShadowUF.db.profile.filters.blacklists[black] or filterDefault
	frame.auras.overridelist = override and ShadowUF.db.profile.filters.overridelists[override] or filterDefault
end

-- Category of an aura: "player", "boss", "raid" (curable/castable/removable) or "misc".
-- sets.player / sets.raid come from the game's filter strings and work with secret auras.
local function categorizeAura(type, isFriendly, auraInstanceID, info, sets)
	-- Player casted it
	if( sets.player and sets.player[auraInstanceID] or not sets.player and info.fromPlayer ) then
		return "player"
	-- Boss aura (unknown while secret, unless we saw it before combat)
	elseif( info.boss ) then
		return "boss"
	elseif( type == "debuffs" ) then
		-- Can dispel it: HARMFUL|RAID only returns debuffs the player can dispel
		if( isFriendly and ( sets.raid and sets.raid[auraInstanceID] or not sets.raid and info.dispelName and ShadowUF.Units:CanCure(info.dispelName) ) ) then
			return "raid"
		-- Can be stolen/purged (dispellable)
		elseif( info.stealable ) then
			return "raid"
		end
	-- Can apply it ourselves: HELPFUL|RAID only returns buffs the player can cast
	elseif( sets.raid and sets.raid[auraInstanceID] ) then
		return "raid"
	end

	return "misc"
end

local function listHas(list, info)
	return list[info.name] or ( info.spellID and list[info.spellID] )
end

local function renderAura(parent, frame, type, config, index, filter, isFriendly, auraData, info, sets)
	local auraInstanceID = auraData.auraInstanceID
	if( issecretvalue(auraInstanceID) ) then auraInstanceID = nil end

	-- Name/spell ID lists only work while we know what the aura is, otherwise it falls through to the category filters
	local known = info.name ~= nil
	if( known ) then
		-- Do our initial list check to see if we can quick filter it out
		if( parent.whitelist[type] and not listHas(parent.whitelist, info) ) then return end
		if( parent.blacklist[type] and listHas(parent.blacklist, info) ) then return end
	end

	-- Now do our type filter
	local category = categorizeAura(type, isFriendly, auraInstanceID, info, sets)
	local curable = isFriendly and type == "debuffs" and category == "raid" and not info.stealable
	local removable = not isFriendly and ( info.stealable or ( sets.dispellable and auraInstanceID and sets.dispellable[auraInstanceID] ) )

	-- check override and type filters
	if( not ( known and parent.overridelist[type] and listHas(parent.overridelist, info) ) and not config.show[category] and (not config.show.relevant or (type == "debuffs") ~= isFriendly) ) then return end

	-- Create any buttons we need
	frame.totalAuras = frame.totalAuras + 1
	if( #(frame.buttons) < frame.totalAuras ) then
		updateButton(frame.totalAuras, frame, ShadowUF.db.profile.units[frame.parent.unitType].auras[frame.type])
	end

	-- Show debuff border, or a special colored border if it's stealable
	local button = frame.buttons[frame.totalAuras]
	local unit = frame.parent.unit
	if( removable and not ShadowUF.db.profile.auras.disableColor ) then
		button.border:SetVertexColor(ShadowUF.db.profile.auraColors.removable.r, ShadowUF.db.profile.auraColors.removable.g, ShadowUF.db.profile.auraColors.removable.b)
	elseif( ( not isFriendly or type == "debuffs" ) and not ShadowUF.db.profile.auras.disableColor ) then
		if( info.dispelKnown ) then
			button.border:SetVertexColor(Auras:GetDispelColor(unit, nil, info.dispelName or "none"))
		else
			button.border:SetVertexColor(Auras:GetDispelColor(unit, auraData))
		end
	else
		button.border:SetVertexColor(0.60, 0.60, 0.60)
	end

	-- Show the cooldown ring
	button.showTimer = not ShadowUF.db.profile.auras.disableCooldown and ( config.timers.ALL or ( category == "player" and config.timers.SELF ) or ( category == "boss" and config.timers.BOSS ) )
	if( button.showTimer ) then
		Auras:SetCooldown(button.cooldown, unit, auraData)
	else
		button.cooldown:Hide()
	end

	-- Enlarge auras
	if( ( category == "player" and config.enlarge.SELF ) or ( category == "boss" and config.enlarge.BOSS ) or ( config.enlarge.REMOVABLE and ( removable or curable ) ) ) then
		button.isSelfScaled = true
		button:SetScale(config.selfScale)
	else
		button.isSelfScaled = nil
		button:SetScale(1)
	end

	-- Size it
	button:SetHeight(config.size)
	button:SetWidth(config.size)
	button.border:SetHeight(config.size + 1)
	button.border:SetWidth(config.size + 1)

	-- Stack + icon + show! Never understood why, auras sometimes return 1 for stack even if they don't stack
	button.auraID = index
	button.auraInstanceID = auraInstanceID
	button.filter = filter
	button.unit = unit
	button.columnHasScaled = nil
	button.previousHasScale = nil
	button.icon:SetTexture(auraData.icon)
	button.stack:SetText(Auras:GetStackText(unit, auraData))
	button:Show()

	if( auraInstanceID ) then
		parent.shown[auraInstanceID] = button
	end
end

-- Refreshes an aura that is already shown (stacks/timer changed) without rescanning the unit
local function refreshButton(button)
	if( not button.auraInstanceID or not button:IsShown() ) then return false end
	local auraData = ShadowUF.Secrets.AuraByInstance(button.unit, button.auraInstanceID)
	if( not auraData ) then return false end

	button.icon:SetTexture(auraData.icon)
	button.stack:SetText(Auras:GetStackText(button.unit, auraData))
	if( button.showTimer ) then
		Auras:SetCooldown(button.cooldown, button.unit, auraData)
	end
	return true
end

-- Scan for auras
local function scan(parent, frame, type, config, displayConfig, filter)
	if( frame.totalAuras >= frame.maxAuras or not config.enabled ) then return end

	local unit = frame.parent.unit

	-- UnitIsFriend returns true during a duel, which breaks stealable/curable detection
	local isFriendly = not UnitIsEnemy(unit, "player")

	-- Ask the game which auras are ours and which we can cure/cast, this works with secret auras
	parent.sets = parent.sets or {buffs = {}, debuffs = {}}
	local sets = parent.sets[type]
	sets.player = Auras:GetFilterSet(unit, filter .. "|PLAYER", sets.playerTbl)
	sets.playerTbl = sets.playerTbl or sets.player
	sets.raid = Auras:GetFilterSet(unit, filter .. "|RAID", sets.raidTbl)
	sets.raidTbl = sets.raidTbl or sets.raid
	sets.dispellable = nil
	local checkedDispellable

	local known, seen = parent.known, parent.seen
	local index = 0
	while( true ) do
		local auraData
		auraData, index = ShadowUF.Secrets.NextAura(unit, index, filter)
		if( issecretvalue(auraData) or not auraData ) then break end

		local auraInstanceID = auraData.auraInstanceID
		if( issecretvalue(auraInstanceID) ) then auraInstanceID = nil end

		local info = auraInstanceID and ( seen[auraInstanceID] or known[auraInstanceID] ) or {}
		readAura(info, auraData)
		if( auraInstanceID ) then seen[auraInstanceID] = info end

		-- Purgeable buffs on enemies: isStealable is secret in combat, so ask the game instead
		if( not checkedDispellable and not info.readable and not info.cached and type == "buffs" and not isFriendly ) then
			checkedDispellable = true
			sets.dispellable = Auras:GetFilterSet(unit, "HELPFUL|RAID_PLAYER_DISPELLABLE", sets.dispellableTbl)
			sets.dispellableTbl = sets.dispellableTbl or sets.dispellable
		end

		renderAura(parent, frame, type, config, index, filter, isFriendly, auraData, info, sets)

		-- Too many auras shown, break out
		-- Get down
		if( frame.totalAuras >= frame.maxAuras ) then break end
	end

	for i=frame.totalAuras + 1, #(frame.buttons) do frame.buttons[i]:Hide() end

	-- The default 1.30 scale doesn't need special handling, after that it does
	if( config.selfScale > 1.30 ) then
		positionAllButtons(frame, displayConfig)
	end
end

Auras.scan = scan

local function anchorGroupToGroup(frame, config, group, childConfig, childGroup)
	-- Child group has nothing in it yet, so don't care
	if( not childGroup.buttons[1] ) then return end

	-- Group we want to anchor to has nothing in it, takeover the postion
	if( group.totalAuras == 0 ) then
		local position = positionData[config.anchorPoint]
		childGroup.buttons[1]:ClearAllPoints()
		childGroup.buttons[1]:SetPoint(ShadowUF.Layout:GetPoint(config.anchorPoint), group.anchorTo, ShadowUF.Layout:GetRelative(config.anchorPoint), config.x + (position.xMod * ShadowUF.db.profile.backdrop.inset), config.y + (position.yMod * ShadowUF.db.profile.backdrop.inset))
		return
	end

	local anchorTo
	for i=#(group.buttons), 1, -1 do
		local button = group.buttons[i]
		if( button.isAuraAnchor and button:IsVisible() ) then
			anchorTo = button
			break
		end
	end

	local position = positionData[childGroup.forcedAnchorPoint or childConfig.anchorPoint]
	if( position.isSideGrowth ) then
		position.aura(childGroup.buttons[1], anchorTo)
	else
		position.column(childGroup.buttons[1], anchorTo, 2)
	end
end

Auras.anchorGroupToGroup = anchorGroupToGroup

-- Do an update and figure out what we need to scan
function Auras:Update(frame)
	local config = ShadowUF.db.profile.units[frame.unitType].auras
	local auras = frame.auras
	if( not auras.shown ) then
		auras.shown, auras.known, auras.seen = {}, {}, {}
	end

	for k in pairs(auras.shown) do auras.shown[k] = nil end
	for k in pairs(auras.seen) do auras.seen[k] = nil end

	if( auras.anchor ) then
		auras.anchor.totalAuras = auras.anchor.temporaryEnchants

		scan(auras, auras.anchor, auras.primary, config[auras.primary], config[auras.primary], auras[auras.primary].filter)
		scan(auras, auras.anchor, auras.secondary, config[auras.secondary], config[auras.primary], auras[auras.secondary].filter)
	else
		if( config.buffs.enabled and auras.buffs ) then
			auras.buffs.totalAuras = auras.buffs.temporaryEnchants
			scan(auras, auras.buffs, "buffs", config.buffs, config.buffs, auras.buffs.filter)
		end

		if( config.debuffs.enabled and auras.debuffs ) then
			auras.debuffs.totalAuras = 0
			scan(auras, auras.debuffs, "debuffs", config.debuffs, config.debuffs, auras.debuffs.filter)
		end

		if( auras.anchorAurasOn ) then
			anchorGroupToGroup(frame, config[auras.anchorAurasOn.type], auras.anchorAurasOn, config[auras.anchorAurasChild.type], auras.anchorAurasChild)
		end
	end

	-- Only keep what we know about auras that are still on the unit
	auras.known, auras.seen = auras.seen, auras.known
end

-- Works out from UNIT_AURA's updateInfo whether anything shown changed. Returns true when a full scan is needed.
local function applyIncremental(frame, updateInfo)
	if( issecretvalue(updateInfo.isFullUpdate) or updateInfo.isFullUpdate ) then return true end

	local added = updateInfo.addedAuras
	if( issecretvalue(added) or ( added and #added > 0 ) ) then return true end

	-- Removing an aura we don't show can't change what is shown
	local shown = frame.auras.shown
	local removed = updateInfo.removedAuraInstanceIDs
	if( issecretvalue(removed) ) then return true end
	if( removed ) then
		for _, id in ipairs(removed) do
			if( issecretvalue(id) or shown[id] ) then return true end
		end
	end

	local updated = updateInfo.updatedAuraInstanceIDs
	if( issecretvalue(updated) ) then return true end
	if( updated ) then
		for _, id in ipairs(updated) do
			if( issecretvalue(id) ) then return true end
			local button = shown[id]
			if( button and not refreshButton(button) ) then return true end
		end
	end

	return false
end

function Auras:UpdateAuras(frame, event, unit, updateInfo)
	if( not frame.auras or not frame.auras.shown or not updateInfo or issecretvalue(updateInfo) or type(updateInfo) ~= "table" ) then
		return self:Update(frame)
	end

	local ok, needsFull = pcall(applyIncremental, frame, updateInfo)
	if( not ok or needsFull ) then
		self:Update(frame)
	end
end
