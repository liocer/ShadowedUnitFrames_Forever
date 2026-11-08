--[[
	Totem bar (shamans). Originally by Shadowed; SUF Forever keeps only the shaman bar (the
	druid / monk / mage / warlock / death knight variants were retail spec features).

	Secret safe: when C_Secrets.ShouldTotemSlotBeSecret says a slot's info is secret,
	GetTotemInfo's values can't be tested. The bar then runs off the game's duration object
	(GetTotemDuration + StatusBar:SetTimerDuration counting down on its own), and is shown or
	faded with SetAlphaFromBoolean on the secret "have totem" flag. Readable slots keep SUF's
	original OnUpdate timer, which the [totem:timer] tag reads (block.endTime).
]]

local Totems = {}
local totemColors = {}
local MAX_TOTEMS = MAX_TOTEMS or 4
local Secrets = ShadowUF.Secrets
local issecretvalue = Secrets.IsSecret

ShadowUF:RegisterModule(Totems, "totemBar", ShadowUF.L["Totem bar"], true, "SHAMAN")

ShadowUF.BlockTimers:Inject(Totems, "TOTEM_TIMER")
ShadowUF.DynamicBlocks:Inject(Totems)

local function slotIsSecret(slot)
	if( C_Secrets and C_Secrets.ShouldTotemSlotBeSecret ) then
		local ok, secret = pcall(C_Secrets.ShouldTotemSlotBeSecret, slot)
		if( ok and not issecretvalue(secret) ) then return secret and true or false end
		if( ok ) then return true end
	end
	return false
end

function Totems:SecureLockable()
	return MAX_TOTEMS > 1
end

function Totems:OnEnable(frame)
	if( not frame.totemBar ) then
		frame.totemBar = CreateFrame("Frame", nil, frame)
		frame.totemBar.totems = {}
		frame.totemBar.blocks = frame.totemBar.totems

		local priorities = SHAMAN_TOTEM_PRIORITIES or {1, 2, 3, 4}

		for id=1, MAX_TOTEMS do
			local totem = ShadowUF.Units:CreateBar(frame.totemBar)
			totem:SetMinMaxValues(0, 1)
			totem:SetValue(0)
			totem.id = priorities[id] or id
			totem.parent = frame

			if( id > 1 ) then
				totem:SetPoint("TOPLEFT", frame.totemBar.totems[id - 1], "TOPRIGHT", 1, 0)
			else
				totem:SetPoint("TOPLEFT", frame.totemBar, "TOPLEFT", 0, 0)
			end

			table.insert(frame.totemBar.totems, totem)
		end

		-- Fire, earth, water, air
		totemColors[1] = {r = 1, g = 0, b = 0.4}
		totemColors[2] = {r = 0, g = 1, b = 0.4}
		totemColors[3] = {r = 0, g = 0.4, b = 1}
		totemColors[4] = {r = 0.90, g = 0.90, b = 0.90}
	end

	frame:RegisterNormalEvent("PLAYER_TOTEM_UPDATE", self, "Update")
	frame:RegisterUpdateFunc(self, "UpdateVisibility")
	frame:RegisterUpdateFunc(self, "Update")
end

function Totems:OnDisable(frame)
	frame:UnregisterAll(self)
	frame:UnregisterUpdateFunc(self, "Update")

	for _, totem in pairs(frame.totemBar.totems) do
		totem:Hide()
	end
end

function Totems:OnLayoutApplied(frame)
	if( not frame.visibility.totemBar ) then return end

	local barWidth = (frame.totemBar:GetWidth() - (MAX_TOTEMS - 1)) / MAX_TOTEMS
	local config = ShadowUF.db.profile.units[frame.unitType].totemBar

	for _, totem in pairs(frame.totemBar.totems) do
		totem:SetHeight(frame.totemBar:GetHeight())
		totem:SetWidth(barWidth)
		totem:SetOrientation(config.vertical and "VERTICAL" or "HORIZONTAL")
		totem:SetReverseFill(config.reverse and true or false)
		totem:SetStatusBarTexture(ShadowUF.Layout.mediaPath.statusbar)
		totem:GetStatusBarTexture():SetHorizTile(false)

		totem.background:SetTexture(ShadowUF.Layout.mediaPath.statusbar)

		if( config.background or config.invert ) then
			totem.background:Show()
		else
			totem.background:Hide()
		end

		if( not config.icon ) then
			local color = totemColors[totem.id] or totemColors[1]
			frame:SetBlockColor(totem, "totemBar", color.r, color.g, color.b)
		end

		if( config.secure ) then
			totem.secure = totem.secure or CreateFrame("Button", frame:GetName() .. "Secure" .. totem.id, totem, "SecureUnitButtonTemplate")
			totem.secure:RegisterForClicks("RightButtonUp")
			totem.secure:SetAllPoints(totem)
			totem.secure:SetAttribute("type2", "destroytotem")
			totem.secure:SetAttribute("*totem-slot*", totem.id)
			totem.secure:Show()

		elseif( totem.secure ) then
			totem.secure:Hide()
		end
	end

	self:Update(frame)
end

local function totemMonitor(self, elapsed)
	local time = GetTime()
	self:SetValue(self.endTime - time)

	if( time >= self.endTime ) then
		self:SetValue(0)
		self:SetScript("OnUpdate", nil)
		self.endTime = nil
	end

	if( self.fontString ) then
		self.fontString:UpdateTags()
	end
end

function Totems:UpdateVisibility(frame)
	if( frame.totemBar.inVehicle ~= frame.inVehicle ) then
		frame.totemBar.inVehicle = frame.inVehicle

		if( frame.inVehicle ) then
			ShadowUF.Layout:SetBarVisibility(frame, "totemBar", false)
		else
			self:Update(frame)
		end
	end
end

-- A slot whose info is secret: the game's duration object drives the bar
local function updateSecretTotem(indicator, config)
	indicator:SetScript("OnUpdate", nil)
	indicator.endTime = nil
	indicator.have = true

	local haveTotem, _, _, _, icon = GetTotemInfo(indicator.id)
	local ok = GetTotemDuration and pcall(function()
		indicator:SetTimerDuration(GetTotemDuration(indicator.id), Enum.StatusBarInterpolation.Immediate, Enum.StatusBarTimerDirection.RemainingTime)
	end)
	if( not ok ) then
		indicator:SetMinMaxValues(0, 1)
		indicator:SetValue(0)
	end

	if( config.icon ) then
		pcall(indicator.SetStatusBarTexture, indicator, icon)
	end

	-- Faded out when the slot's empty, without testing the secret flag
	if( not pcall(indicator.SetAlphaFromBoolean, indicator, haveTotem, 1, 0) ) then
		indicator:SetAlpha(1)
	end
end

function Totems:Update(frame)
	local config = ShadowUF.db.profile.units[frame.unitType].totemBar
	local totalActive = 0
	for _, indicator in pairs(frame.totemBar.totems) do
		if( slotIsSecret(indicator.id) ) then
			updateSecretTotem(indicator, config)
			-- Can't tell, so count it as up and keep the bar shown
			totalActive = totalActive + 1
		else
			local have, _name, start, duration, icon = GetTotemInfo(indicator.id)
			if( have and start > 0 ) then
				if( config.icon ) then
					indicator:SetStatusBarTexture(icon)
				end

				indicator.have = true
				indicator.endTime = start + duration
				indicator:SetMinMaxValues(0, duration)
				indicator:SetValue(indicator.endTime - GetTime())
				indicator:SetScript("OnUpdate", totemMonitor)
				indicator:SetAlpha(1.0)

				totalActive = totalActive + 1

			elseif( indicator.have ) then
				indicator.have = nil
				indicator:SetScript("OnUpdate", nil)
				indicator:SetMinMaxValues(0, 1)
				indicator:SetValue(0)
				indicator:SetAlpha(1.0)
				indicator.endTime = nil
			end
		end

		if( indicator.fontString ) then
			indicator.fontString:UpdateTags()
		end
	end

	if( not frame.inVehicle ) then
		if( not config.showAlways ) then
			ShadowUF.Layout:SetBarVisibility(frame, "totemBar", totalActive > 0)
		end
	end
end
