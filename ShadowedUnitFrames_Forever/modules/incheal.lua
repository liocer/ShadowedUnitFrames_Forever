--[[
	Incoming heals, plus the shared code for the absorb / heal absorb bars (incabsorb.lua,
	healabsorb.lua) and the power cost preview (powerprediction.lua).

	Originally by Shadowed. SUF Forever rewrite: in combat the game hands us secret health
	and heal values, which can't be compared or added together in Lua. So instead of sizing
	bars by hand, every prediction bar is its own StatusBar whose edge is anchored to the end
	of the health fill texture (or of the bar before it), on the same 0 - max health scale.
	The game positions everything, a secret amount just goes into SetValue, and a clip frame
	the size of the health bar times the "Outside bar limit" (cap) setting cuts off whatever
	runs past it.

	The amounts come from the game's own heal prediction calculator when it exists
	(CreateUnitHealPredictionCalculator + UnitGetDetailedHealPrediction), which works out the
	heal absorb / incoming heal reductions the way Blizzard's frames show them.
]]

local IncHeal = {["frameKey"] = "incHeal", ["colorKey"] = "inc", ["frameLevelMod"] = 2}
ShadowUF.IncHeal = IncHeal
ShadowUF:RegisterModule(IncHeal, "incHeal", ShadowUF.L["Incoming heals"])

local Secrets = ShadowUF.Secrets
local issecretvalue = Secrets.IsSecret

---------------------------------------------------------------------------
-- Overlay helpers (also used by powerprediction.lua)
---------------------------------------------------------------------------

-- Keeps a clip frame (and the overlays in it) the right size for its bar
local function updateClipSize(clip)
	local bar = clip.bar
	local cap = clip.cap or 1
	local vertical = bar:GetOrientation() == "VERTICAL"
	clip:ClearAllPoints()
	if( vertical ) then
		local side = bar:GetReverseFill() and "TOP" or "BOTTOM"
		clip:SetPoint(side .. "LEFT", bar, side .. "LEFT")
		clip:SetPoint(side .. "RIGHT", bar, side .. "RIGHT")
		clip:SetHeight(math.max(1, bar:GetHeight() * cap))
	else
		local side = bar:GetReverseFill() and "RIGHT" or "LEFT"
		clip:SetPoint("TOP" .. side, bar, "TOP" .. side)
		clip:SetPoint("BOTTOM" .. side, bar, "BOTTOM" .. side)
		clip:SetWidth(math.max(1, bar:GetWidth() * cap))
	end

	-- Overlays are as long as the bar itself, so they share its 0 - max scale
	for overlay in pairs(clip.overlays) do
		if( vertical ) then
			overlay:SetHeight(math.max(1, bar:GetHeight()))
		else
			overlay:SetWidth(math.max(1, bar:GetWidth()))
		end
	end
end

local function barSizeChanged(bar)
	for clip in pairs(bar.sufClips) do
		updateClipSize(clip)
	end
end

-- A frame that clips its children to `bar` stretched by `cap` (1 = the bar itself) from the
-- bar's start, so prediction bars can run that far past the end of the bar and no further.
function IncHeal.CreateClip(bar, cap)
	local clip = CreateFrame("Frame", nil, bar)
	clip.bar = bar
	clip.cap = cap or 1
	clip.overlays = {}
	clip:SetFrameLevel(bar:GetFrameLevel() + 1)
	pcall(clip.SetClipsChildren, clip, true)

	if( not bar.sufClips ) then
		bar.sufClips = {}
		bar:HookScript("OnSizeChanged", barSizeChanged)
	end
	bar.sufClips[clip] = true

	updateClipSize(clip)
	return clip
end

-- Re-reads the cap and the bar's orientation / fill direction
function IncHeal.UpdateClip(clip, cap)
	clip.cap = cap or 1
	clip:SetFrameLevel(clip.bar:GetFrameLevel() + 1)
	updateClipSize(clip)
end

function IncHeal.CreateOverlay(clip)
	local overlay = CreateFrame("StatusBar", nil, clip)
	overlay:SetFrameLevel(clip:GetFrameLevel())
	overlay:SetMinMaxValues(0, 1)
	overlay:SetValue(0)
	clip.overlays[overlay] = true
	overlay.clip = clip
	return overlay
end

-- Anchors `overlay` to the end of `anchor` (a fill texture, by default the bar's own),
-- following the bar's orientation and fill direction.
--   inward = false: starts where the fill ends and grows away from it (incoming heals)
--   inward = true: ends where the fill ends and grows back into it (heal absorbs, costs)
-- The overlay is as long as the bar and uses the same 0 - max scale, so the (maybe
-- secret) amount goes straight into SetValue with no maths.
function IncHeal.AnchorOverlay(overlay, bar, anchor, inward)
	anchor = anchor or bar:GetStatusBarTexture()
	local vertical = bar:GetOrientation() == "VERTICAL"
	local reverse = bar:GetReverseFill() and true or false
	inward = inward and true or false

	overlay:SetOrientation(vertical and "VERTICAL" or "HORIZONTAL")
	overlay:SetReverseFill(reverse ~= inward)
	overlay:ClearAllPoints()

	if( vertical ) then
		local endSide = reverse and "BOTTOM" or "TOP"
		local ownSide = inward and endSide or (reverse and "TOP" or "BOTTOM")
		overlay:SetPoint(ownSide .. "LEFT", anchor, endSide .. "LEFT")
		overlay:SetPoint(ownSide .. "RIGHT", anchor, endSide .. "RIGHT")
		overlay:SetHeight(math.max(1, bar:GetHeight()))
	else
		local endSide = reverse and "LEFT" or "RIGHT"
		local ownSide = inward and endSide or (reverse and "RIGHT" or "LEFT")
		overlay:SetPoint("TOP" .. ownSide, anchor, "TOP" .. endSide)
		overlay:SetPoint("BOTTOM" .. ownSide, anchor, "BOTTOM" .. endSide)
		overlay:SetWidth(math.max(1, bar:GetWidth()))
	end
end

-- Puts a (maybe secret) amount on the overlay, on the 0 - max scale. nil counts as nothing.
function IncHeal.SetOverlayValue(overlay, max, amount)
	if( not issecretvalue(amount) and amount == nil ) then amount = 0 end
	if( not issecretvalue(max) and ( max == nil or max <= 0 ) ) then max = 1 end

	local ok = pcall(overlay.SetMinMaxValues, overlay, 0, max)
	ok = ok and pcall(overlay.SetValue, overlay, amount)
	if( not ok ) then
		overlay:SetMinMaxValues(0, 1)
		overlay:SetValue(0)
	end
	return ok
end

---------------------------------------------------------------------------
-- Heal prediction amounts
---------------------------------------------------------------------------

local calculators = setmetatable({}, {__mode = "k"})
local hasCalculator = CreateUnitHealPredictionCalculator and UnitGetDetailedHealPrediction and Enum.UnitHealAbsorbMode and true

local function getCalculator(frame)
	local calc = calculators[frame]
	if( calc == nil ) then
		local ok
		ok, calc = pcall(function()
			local c = CreateUnitHealPredictionCalculator()
			-- Clamping is done by the clip frames (SUF's "Outside bar limit" setting),
			-- so let the game hand over everything up to max health.
			c:SetIncomingHealClampMode(Enum.UnitIncomingHealClampMode.MaximumHealth)
			c:SetDamageAbsorbClampMode(Enum.UnitDamageAbsorbClampMode.MaximumHealth)
			c:SetHealAbsorbClampMode(Enum.UnitHealAbsorbClampMode.CurrentHealth)
			return c
		end)
		calc = ok and calc or false
		calculators[frame] = calc
	end
	return calc or nil
end

-- Incoming heals, damage absorbs and heal absorbs on the frame's unit (each may be secret,
-- or nil). With the heal absorb bar shown, heals and heal absorbs cancel each other out the
-- way Blizzard's frames show them: whichever is bigger is shown, less the other.
-- Also returns my own share of the incoming heals.
function IncHeal.GetAmounts(frame)
	local unit = frame.unit
	local calc = hasCalculator and getCalculator(frame)
	if( calc ) then
		local ok, heals, absorbs, healAbsorbs, myHeals = pcall(function()
			calc:SetHealAbsorbMode(frame.visibility.healAbsorb and Enum.UnitHealAbsorbMode.ReducedByIncomingHeals or Enum.UnitHealAbsorbMode.Total)
			UnitGetDetailedHealPrediction(unit, "player", calc)
			local h, mine = calc:GetIncomingHeals()
			local a = calc:GetDamageAbsorbs()
			local ha = calc:GetHealAbsorbs()
			return h, a, ha, mine
		end)
		if( ok ) then return heals, absorbs, healAbsorbs, myHeals end
	end

	-- No calculator: the raw numbers, no cancelling out
	local heals = UnitGetIncomingHeals and UnitGetIncomingHeals(unit)
	local absorbs = UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(unit)
	local healAbsorbs = UnitGetTotalHealAbsorbs and UnitGetTotalHealAbsorbs(unit)
	local myHeals = UnitGetIncomingHeals and UnitGetIncomingHeals(unit, "player")
	return heals, absorbs, healAbsorbs, myHeals
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------

-- Heal absorbs draw over the end of the health instead of after it
IncHeal.inward = false

function IncHeal:OnEnable(frame)
	frame:RegisterUnitEvent("UNIT_MAXHEALTH", self, "UpdateFrame")
	frame:RegisterUnitEvent("UNIT_HEALTH", self, "UpdateFrame")
	frame:RegisterUnitEvent("UNIT_HEAL_PREDICTION", self, "UpdateFrame")
	frame:RegisterUnitEvent("UNIT_CONNECTION", self, "UpdateFrame")

	frame:RegisterUpdateFunc(self, "UpdateFrame")
end

function IncHeal:OnDisable(frame)
	frame:UnregisterAll(self)
	if( frame[self.frameKey] ) then
		frame[self.frameKey]:Hide()
	end
end

-- The fill texture this bar starts at the end of; nil = the health bar's own
function IncHeal:GetAnchorTexture(frame)
	return nil
end

-- Creates (once) and lays out this module's overlay on the health bar
function IncHeal:SetupOverlay(frame)
	local healthBar = frame.healthBar
	local config = ShadowUF.db.profile.units[frame.unitType][self.frameKey]
	local cap = self.inward and 1 or math.max(1, config.cap or 1.30)

	local bar = frame[self.frameKey]
	if( not bar ) then
		bar = IncHeal.CreateOverlay(IncHeal.CreateClip(healthBar, cap))
		frame[self.frameKey] = bar
	else
		IncHeal.UpdateClip(bar.clip, cap)
	end

	-- Just above the health bar so it draws over its background, but under the text (highFrame)
	local level = healthBar:GetFrameLevel() + 1
	bar.clip:SetFrameLevel(level)
	bar:SetFrameLevel(level)
	bar.clip:Show()

	bar:SetStatusBarTexture(ShadowUF.Layout.mediaPath.statusbar)
	bar:GetStatusBarTexture():SetHorizTile(false)
	local color = ShadowUF.db.profile.healthColors[self.colorKey]
	bar:SetStatusBarColor(color.r, color.g, color.b, ShadowUF.db.profile.bars.alpha)

	IncHeal.AnchorOverlay(bar, healthBar, self:GetAnchorTexture(frame), self.inward)
	bar:Show()
	return bar
end

function IncHeal:OnLayoutApplied(frame)
	if( not frame.visibility[self.frameKey] ) then return end
	if( not frame.visibility.healthBar or not frame.healthBar ) then
		if( frame[self.frameKey] ) then frame[self.frameKey]:Hide() end
		return
	end

	-- Heal absorbs eat into the incoming heals shown
	if( self == IncHeal ) then
		if( frame.visibility.healAbsorb ) then
			frame:RegisterUnitEvent("UNIT_HEAL_ABSORB_AMOUNT_CHANGED", self, "UpdateFrame")
		else
			frame:UnregisterSingleEvent("UNIT_HEAL_ABSORB_AMOUNT_CHANGED", self, "UpdateFrame")
		end
	end

	self:SetupOverlay(frame)
	self:UpdateFrame(frame)
end

-- Shows `amount` (maybe secret) on this module's bar
function IncHeal:PositionBar(frame, amount)
	local bar = frame[self.frameKey]
	if( not bar ) then return end

	if( not UnitIsConnected(frame.unit) or UnitIsDeadOrGhost(frame.unit) ) then
		amount = 0
	end

	bar.total = amount
	IncHeal.SetOverlayValue(bar, UnitHealthMax(frame.unit), amount)
end

function IncHeal:UpdateFrame(frame)
	if( not frame.visibility[self.frameKey] or not frame.visibility.healthBar or not frame[self.frameKey] ) then return end

	local heals = IncHeal.GetAmounts(frame)
	self:PositionBar(frame, heals)
end
