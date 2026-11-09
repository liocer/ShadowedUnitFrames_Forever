--[[
	Combat text (damage/heal feedback on the frame). Originally by Shadowed (Shadowed Unit Frames),
	ported to WoW Forever.

	Forever: UNIT_COMBAT's amount is always secret, and Blizzard's CombatFeedback_OnCombatEvent
	compares it (amount ~= 0), which errors from addon code. This is the same logic written so the
	amount is only ever passed to BreakUpLargeNumbers/SetText. With a secret amount a WOUND can't be
	told apart from a zero-damage hit, so the flags (ABSORB/BLOCK/RESIST) decide.
]]
local Combat = {}
local Secrets = ShadowUF.Secrets
local issecretvalue = Secrets.IsSecret
ShadowUF:RegisterModule(Combat, "combatText", ShadowUF.L["Combat text"])

local FADE_IN, HOLD, FADE_OUT = COMBATFEEDBACK_FADEINTIME or 0.2, COMBATFEEDBACK_HOLDTIME or 0.7, COMBATFEEDBACK_FADEOUTTIME or 0.3
local PHYSICAL = Enum.Damageclass and Enum.Damageclass.MaskPhysical or 1

-- Blizzard's GlobalStrings (not in the generated globals list)
local feedbackText = {}
for _, key in ipairs({"INTERRUPT", "MISS", "RESIST", "DODGE", "PARRY", "BLOCK", "EVADE", "IMMUNE", "DEFLECT", "ABSORB", "REFLECT", "BLOCK_REDUCED"}) do
	feedbackText[key] = _G[key] or key
end
local BLOCK_REDUCED_FORMAT = _G.COMBAT_TEXT_BLOCK_REDUCED

local function onUpdate(self)
	local text = self.feedbackText
	if( not text:IsVisible() ) then return end

	local elapsed = GetTime() - self.feedbackStartTime
	if( elapsed < FADE_IN ) then
		text:SetAlpha(elapsed / FADE_IN)
	elseif( elapsed < FADE_IN + HOLD ) then
		text:SetAlpha(1)
	elseif( elapsed < FADE_IN + HOLD + FADE_OUT ) then
		text:SetAlpha(1 - ((elapsed - HOLD - FADE_IN) / FADE_OUT))
	else
		text:Hide()
	end
end

function Combat:OnEnable(frame)
	if( not frame.combatText ) then
		frame.combatText = CreateFrame("Frame", nil, frame.highFrame)
		frame.combatText:SetFrameStrata("HIGH")
		frame.combatText.feedbackText = frame.combatText:CreateFontString(nil, "ARTWORK")
		frame.combatText.feedbackText:SetPoint("CENTER", frame.combatText, "CENTER", 0, 0)
		frame.combatText:SetFrameLevel(frame.topFrameLevel)

		frame.combatText.feedbackStartTime = 0
		frame.combatText:SetScript("OnUpdate", onUpdate)
		frame.combatText:SetHeight(1)
		frame.combatText:SetWidth(1)
	end

	frame:RegisterUnitEvent("UNIT_COMBAT", self, "Update")
end

function Combat:OnLayoutApplied(frame, config)
	-- Update feedback text
	ShadowUF.Layout:ToggleVisibility(frame.combatText, frame.visibility.combatText)
	if( frame.visibility.combatText ) then
		frame.combatText.feedbackFontHeight = ShadowUF.db.profile.font.size + 1
		frame.combatText.fontPath = ShadowUF.Layout.mediaPath.font

		ShadowUF.Layout:SetupFontString(frame.combatText.feedbackText, 1)
		ShadowUF.Layout:AnchorFrame(frame, frame.combatText, config.combatText)
	end
end

function Combat:OnDisable(frame)
	frame:UnregisterAll(self)
end

-- Text, colour and size multiplier for a UNIT_COMBAT event
local function getFeedback(event, flags, amount, school)
	if( event == "IMMUNE" ) then
		return feedbackText.IMMUNE, 1, 1, 1, 0.75
	elseif( event == "WOUND" ) then
		local hit
		if( issecretvalue(amount) ) then
			hit = flags ~= "ABSORB" and flags ~= "BLOCK" and flags ~= "RESIST"
		else
			hit = amount ~= 0
		end

		if( hit ) then
			local size = ( flags == "CRITICAL" or flags == "CRUSHING" ) and 1.5 or flags == "GLANCING" and 0.75 or 1
			local text = Secrets.BreakUp(amount)
			if( flags == "BLOCK_REDUCED" and BLOCK_REDUCED_FORMAT ) then
				text = string.format(BLOCK_REDUCED_FORMAT, text)
			end

			if( school ~= PHYSICAL ) then
				return text, 1, 1, 0, size
			end
			return text, 1, 1, 1, size
		elseif( flags == "ABSORB" or flags == "BLOCK" or flags == "RESIST" ) then
			return feedbackText[flags], 1, 1, 1, 0.75
		end
		return feedbackText.MISS, 1, 1, 1, 1
	elseif( event == "BLOCK" ) then
		return feedbackText.BLOCK, 1, 1, 1, 0.75
	elseif( event == "HEAL" ) then
		return Secrets.BreakUp(amount), 0, 1, 0, flags == "CRITICAL" and 1.5 or 1
	elseif( event == "ENERGIZE" ) then
		return Secrets.BreakUp(amount), 0.41, 0.8, 0.94, flags == "CRITICAL" and 1.5 or 1
	end

	return feedbackText[event], 1, 1, 1, 1
end

function Combat:Update(frame, event, unit, type, flags, amount, school)
	local combatText = frame.combatText
	local text, r, g, b, size = getFeedback(type, flags, amount, school)
	if( text == nil ) then return end

	local fontSize = ShadowUF.db.profile.font.size
	combatText.feedbackStartTime = GetTime()
	combatText.feedbackText:SetFont(combatText.fontPath, fontSize, "OUTLINE")
	combatText.feedbackText:SetText(text)
	combatText.feedbackText:SetTextColor(r, g, b)
	combatText.feedbackText:SetAlpha(0)
	combatText.feedbackText:Show()

	-- Increasing the font size will make the text look pixelated, however scaling it up will make it look smooth and awesome
	local scale = combatText.feedbackFontHeight * size / fontSize
	if( scale > 0 ) then
		combatText:SetScale(scale)
	end
end
