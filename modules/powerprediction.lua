--[[
	Power cost prediction ("spend preview"), new in SUF Forever.

	While the unit casts, the part of its power bar the spell will use is drawn in a darker
	shade at the end of the fill, like Blizzard's player frame (ManaCostPredictionBar). For a
	druid in bear / cat form the mana cost goes on the druid mana bar instead.

	Secret safe: the cost (C_Spell.GetSpellPowerCost) and the power may both be secret. The
	preview is its own StatusBar whose far edge is anchored to the end of the power bar's fill
	and which fills back into it, on the same 0 - max power scale (see incheal.lua), so the
	cost goes straight into SetValue with no maths.

	Casts stopping: a cast's STOP / FAILED / INTERRUPTED / SUCCEEDED only clears the preview
	when it's for the cast being shown (same cast GUID). Pressing another spell mid-cast fires
	UNIT_SPELLCAST_FAILED ("another action is in progress") for a different GUID, which is
	ignored; when the GUIDs are secret and can't be compared, FAILED is ignored and the rest
	clear it. After clearing, whatever the unit is still casting (UnitCastingInfo) is picked up.
]]

local PowerPrediction = {}
ShadowUF:RegisterModule(PowerPrediction, "powerPrediction", ShadowUF.L["Power cost prediction"])

local Secrets = ShadowUF.Secrets
local issecretvalue = Secrets.IsSecret
local MANA = Enum.PowerType.Mana
local DEFAULT_SHADE = 0.6
local getSpellPowerCost = C_Spell and C_Spell.GetSpellPowerCost

function PowerPrediction:OnEnable(frame)
	frame.powerPrediction = frame.powerPrediction or CreateFrame("Frame", nil, frame)
	frame.powerPrediction:Show()

	frame:RegisterUnitEvent("UNIT_SPELLCAST_START", self, "CastStart")
	frame:RegisterUnitEvent("UNIT_SPELLCAST_STOP", self, "CastStop")
	frame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", self, "CastStop")
	frame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", self, "CastStop")
	frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", self, "CastStop")
	frame:RegisterUnitEvent("UNIT_MAXPOWER", self, "Update")
	frame:RegisterUnitEvent("UNIT_DISPLAYPOWER", self, "Update")

	frame:RegisterUpdateFunc(self, "UpdateCast")
end

function PowerPrediction:OnDisable(frame)
	frame:UnregisterAll(self)

	local holder = frame.powerPrediction
	if( holder ) then
		holder.castID, holder.costs = nil, nil
		for _, overlay in pairs(holder.overlays or {}) do
			overlay:Hide()
		end
		holder:Hide()
	end
end

function PowerPrediction:OnLayoutApplied(frame)
	if( not frame.visibility.powerPrediction ) then return end
	self:Update(frame)
end

-- Remembers what the cast costs, by power type. Costs may be secret.
function PowerPrediction:StartCast(frame, castID, spellID)
	local holder = frame.powerPrediction
	holder.castID, holder.costs = castID, nil
	if( not getSpellPowerCost or ( not issecretvalue(spellID) and not spellID ) ) then return end

	local ok, costs = pcall(getSpellPowerCost, spellID)
	if( not ok or issecretvalue(costs) or type(costs) ~= "table" ) then return end

	for _, info in ipairs(costs) do
		local powerType = Secrets.Read(function() return info.type end)
		local cost = info.cost
		if( powerType ~= nil and ( issecretvalue(cost) or ( type(cost) == "number" and cost > 0 ) ) ) then
			holder.costs = holder.costs or {}
			holder.costs[powerType] = cost
		end
	end
end

-- Picks up whatever the unit is casting right now (full updates, unit changes)
function PowerPrediction:UpdateCast(frame)
	local holder = frame.powerPrediction
	holder.castID, holder.costs = nil, nil

	local name, _, _, _, _, _, castID, _, spellID = UnitCastingInfo(frame.unit)
	if( issecretvalue(name) or name ) then
		self:StartCast(frame, castID, spellID)
	end

	self:Update(frame)
end

function PowerPrediction:CastStart(frame, event, unit, castID, spellID)
	self:StartCast(frame, castID, spellID)
	self:Update(frame)
end

function PowerPrediction:CastStop(frame, event, unit, castID)
	local holder = frame.powerPrediction
	if( not holder.costs ) then return end

	local ok, same = pcall(function() return castID == holder.castID end)
	if( ( ok and same ) or ( not ok and event ~= "UNIT_SPELLCAST_FAILED" ) ) then
		-- Still casting something (a queued spell)? Then that's the one to show
		self:UpdateCast(frame)
	end
end

-- The bar's own colour (its background's when inverted), plain numbers
local function getBarColor(frame, key, bar)
	local config = ShadowUF.db.profile.units[frame.unitType][key]
	local ok, r, g, b
	if( config and config.invert ) then
		ok, r, g, b = pcall(bar.background.GetVertexColor, bar.background)
	else
		ok, r, g, b = pcall(bar.GetStatusBarColor, bar)
	end
	if( not ok or Secrets.Any(r, g, b) or not r ) then return 1, 1, 1 end
	return r, g, b
end

function PowerPrediction:ShowCost(frame, key, cost, powerType)
	local holder = frame.powerPrediction
	holder.overlays = holder.overlays or {}
	local bar = frame[key]
	local overlay = holder.overlays[key]

	-- Nothing to show, the bar's hidden, or it fell back to a 0-100 percent scale
	if( not bar or not bar:IsShown() or bar.exactValues == false or powerType == nil or ( not issecretvalue(cost) and not cost ) ) then
		if( overlay ) then overlay:Hide() end
		return
	end

	if( not overlay ) then
		overlay = ShadowUF.IncHeal.CreateOverlay(ShadowUF.IncHeal.CreateClip(bar, 1))
		holder.overlays[key] = overlay
	end

	ShadowUF.IncHeal.UpdateClip(overlay.clip, 1)
	overlay.clip:Show()
	overlay:SetFrameLevel(overlay.clip:GetFrameLevel())
	ShadowUF.IncHeal.AnchorOverlay(overlay, bar, nil, true)

	overlay:SetStatusBarTexture(ShadowUF.Layout.mediaPath.statusbar)
	overlay:GetStatusBarTexture():SetHorizTile(false)

	local config = ShadowUF.db.profile.units[frame.unitType].powerPrediction
	local shade = config and config.shade or DEFAULT_SHADE
	local r, g, b = getBarColor(frame, key, bar)
	overlay:SetStatusBarColor(r * shade, g * shade, b * shade, ShadowUF.db.profile.bars.alpha)

	ShadowUF.IncHeal.SetOverlayValue(overlay, UnitPowerMax(frame.unit, powerType), cost)
	overlay:Show()
end

function PowerPrediction:Update(frame)
	local holder = frame.powerPrediction
	if( not holder or not frame.visibility.powerPrediction ) then return end

	local costs = holder.costs
	local powerType = Secrets.Plain(UnitPowerType(frame.unit))
	if( UnitIsDeadOrGhost(frame.unit) or not UnitIsConnected(frame.unit) ) then costs = nil end

	self:ShowCost(frame, "powerBar", costs and powerType and costs[powerType], powerType)

	-- Druids in forms: the mana cost goes on the druid mana bar
	local druidShown = frame.visibility.druidBar and powerType ~= MANA
	self:ShowCost(frame, "druidBar", druidShown and costs and costs[MANA], MANA)
end
