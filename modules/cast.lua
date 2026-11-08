--[[
	Cast bars. Originally by Shadowed (Shadowed Unit Frames), ported to WoW Forever.

	Forever note: UnitCastingInfo / UnitChannelInfo and the UNIT_SPELLCAST_* payloads can be
	secret for some units (C_Secrets.ShouldUnitSpellCastingBeSecret). When the start/end times
	are plain numbers the bar works exactly as it always has (timer text with pushback, finish
	detection in OnUpdate). When they are secret the bar is driven by the game instead:
	UnitCastingDuration/UnitChannelDuration duration objects through StatusBar:SetTimerDuration,
	the timer text comes from the duration object, the spell name/icon are handed straight to
	SetText/SetTexture, and the uninterruptible colour is applied with SetVertexColorFromBoolean.
	Stop/interrupt events are matched to the shown cast by castGUID only when it isn't secret
	(castBarID, which is never secret, is used to rule events out).
]]
local Cast = {}
local L = ShadowUF.L
local Secrets = ShadowUF.Secrets
local issecretvalue = Secrets.IsSecret
local FADE_TIME = 0.30
local SECRET_TEXT_THROTTLE = 0.05

ShadowUF:RegisterModule(Cast, "castBar", L["Cast bar"], true)

local UnitCastingDuration = UnitCastingDuration
local UnitChannelDuration = UnitChannelDuration

-- The unit argument is "UnitTokenPvPRestrictedForAddOns"; don't let a restricted unit throw errors at us
local function passResults(ok, ...)
	if( ok ) then return ... end
end
local function UnitCastingInfo(unit) return passResults(pcall(_G.UnitCastingInfo, unit)) end
local function UnitChannelInfo(unit) return passResults(pcall(_G.UnitChannelInfo, unit)) end
local Interpolation = Enum.StatusBarInterpolation
local TimerDirection = Enum.StatusBarTimerDirection

-- Does the value exist? Works for secrets (a secret is always "something")
local function hasValue(value)
	return issecretvalue(value) or value ~= nil
end

-- Returns isChannelled, spell, displayName, icon, startTime, endTime, isTradeSkill, notInterruptible, spellID, castID, castBarID
-- or nothing when the unit isn't casting
local function getCastInfo(unit)
	local spell, displayName, icon, startTime, endTime, isTradeSkill, castID, notInterruptible, spellID, castBarID = UnitCastingInfo(unit)
	if( hasValue(spell) ) then
		return false, spell, displayName, icon, startTime, endTime, isTradeSkill, notInterruptible, spellID, castID, castBarID
	end

	local _
	spell, displayName, icon, startTime, endTime, isTradeSkill, notInterruptible, spellID, _, _, castBarID = UnitChannelInfo(unit)
	if( hasValue(spell) ) then
		return true, spell, displayName, icon, startTime, endTime, isTradeSkill, notInterruptible, spellID, nil, castBarID
	end
end

local function isCasting(unit)
	return hasValue((UnitCastingInfo(unit))) or hasValue((UnitChannelInfo(unit)))
end

-- Is this event about the cast we are showing? true / false, or nil if it can't be told (secret castGUID).
-- castBarID is never secret, but it isn't documented whether it's unique per cast, so it's only used to rule an event out.
local function sameCast(cast, castGUID, castBarID)
	if( castBarID ~= nil and cast.castBarID ~= nil and castBarID ~= cast.castBarID ) then
		return false
	end

	if( cast.castID == nil or issecretvalue(castGUID) or castGUID == nil ) then return nil end
	return castGUID == cast.castID
end

-- I'm not really thrilled with this method of detecting fake unit casts, mostly because it's inefficient and ugly
local function monitorFakeCast(self)
	local frame = self.parent
	local isChannelled, spell, displayName, icon, startTime, endTime, isTradeSkill, notInterruptible, spellID, castID, castBarID = getCastInfo(frame.unit)
	local casting = isChannelled ~= nil

	-- A different cast replaced the one we were watching without a gap
	if( self.active and casting ) then
		if( ( castBarID ~= nil and self.castBarID ~= nil and castBarID ~= self.castBarID ) or
			( not issecretvalue(castID) and castID ~= nil and self.castID ~= nil and castID ~= self.castID ) or
			( isChannelled ~= self.isChannelled ) ) then
			self.active = nil
		end
	end

	-- Cast started
	if( not self.active and casting ) then
		self.active = true
		self.isChannelled = isChannelled
		self.endTime = Secrets.Plain(endTime)
		self.notInterruptible = Secrets.Bool(notInterruptible)
		self.castBarID = castBarID
		self.castID = Secrets.Plain(castID)
		Cast:UpdateCast(frame, frame.unit, isChannelled, spell, displayName, icon, startTime, endTime, isTradeSkill, notInterruptible, spellID, castID, castBarID)
		return

	-- Cast stopped
	elseif( self.active and not casting ) then
		-- Stopped before it should have finished, so it was interrupted
		if( self.endTime and GetTime() <= (self.endTime / 1000) ) then
			Cast:EventInterruptCast(frame, nil, frame.unit)
		-- Secret times, we can't tell how it ended so just fade it out
		elseif( not self.endTime ) then
			Cast:StopCast(frame)
		end

		self.active = nil
		self.notInterruptible = nil
		self.endTime = nil
		self.castBarID = nil
		self.castID = nil
		return
	end

	if( not self.active ) then return end

	-- Cast delayed
	if( self.endTime and not issecretvalue(endTime) and endTime ~= self.endTime ) then
		self.endTime = endTime
		Cast:UpdateDelay(frame, spell, displayName, icon, startTime, endTime)
	end

	-- Cast interruptible status changed
	local plainNotInterruptible = Secrets.Bool(notInterruptible)
	if( plainNotInterruptible ~= nil and self.notInterruptible ~= plainNotInterruptible ) then
		self.notInterruptible = plainNotInterruptible
		if( plainNotInterruptible ) then
			Cast:EventUninterruptible(frame)
		else
			Cast:EventInterruptible(frame)
		end
	end
end

local function createFakeCastMonitor(frame)
	if( not frame.castBar.monitor ) then
		frame.castBar.monitor = C_Timer.NewTicker(0.10, monitorFakeCast)
		frame.castBar.monitor.parent = frame
	end
end

local function cancelFakeCastMonitor(frame)
	if( frame.castBar and frame.castBar.monitor ) then
		frame.castBar.monitor:Cancel()
		frame.castBar.monitor = nil
	end
end

function Cast:OnEnable(frame)
	if( not frame.castBar ) then
		frame.castBar = CreateFrame("Frame", nil, frame)
		frame.castBar.bar = ShadowUF.Units:CreateBar(frame)
		frame.castBar.background = frame.castBar.bar.background
		frame.castBar.bar.parent = frame
		frame.castBar.bar.background = frame.castBar.background

		frame.castBar.icon = frame.castBar.bar:CreateTexture(nil, "ARTWORK")
		frame.castBar.bar.name = frame.castBar.bar:CreateFontString(nil, "ARTWORK")
		frame.castBar.bar.time = frame.castBar.bar:CreateFontString(nil, "ARTWORK")
	end

	if( ShadowUF.fakeUnits[frame.unitType] ) then
		createFakeCastMonitor(frame)
		frame:RegisterUpdateFunc(self, "UpdateFakeCast")
		return
	end

	frame:RegisterUnitEvent("UNIT_SPELLCAST_START", self, "EventUpdateCast")
	frame:RegisterUnitEvent("UNIT_SPELLCAST_STOP", self, "EventStopCast")
	frame:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", self, "EventStopCast")
	frame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", self, "EventInterruptCast")
	frame:RegisterUnitEvent("UNIT_SPELLCAST_DELAYED", self, "EventDelayCast")
	frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", self, "EventCastSucceeded")

	frame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_START", self, "EventUpdateChannel")
	frame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", self, "EventStopChannel")
	frame:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_UPDATE", self, "EventDelayChannel")

	frame:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTIBLE", self, "EventInterruptible")
	frame:RegisterUnitEvent("UNIT_SPELLCAST_NOT_INTERRUPTIBLE", self, "EventUninterruptible")

	frame:RegisterUpdateFunc(self, "UpdateCurrentCast")
end

function Cast:OnLayoutApplied(frame, config)
	if( not frame.visibility.castBar ) then return end

	-- Set textures
	frame.castBar.bar:SetStatusBarTexture(ShadowUF.Layout.mediaPath.statusbar)
	frame.castBar.bar:SetStatusBarColor(0, 0, 0, 0)
	frame.castBar.bar:GetStatusBarTexture():SetHorizTile(false)
	frame.castBar.background:SetVertexColor(0, 0, 0, 0)
	frame.castBar.background:SetHorizTile(false)

	-- Setup fill
	frame.castBar.bar:SetOrientation(config.castBar.vertical and "VERTICAL" or "HORIZONTAL")
	frame.castBar.bar:SetReverseFill(config.castBar.reverse and true or false)

	-- Setup the main bar + icon
	frame.castBar.bar:ClearAllPoints()
	frame.castBar.bar:SetHeight(frame.castBar:GetHeight())
	frame.castBar.bar:SetMinMaxValues(0, 1)
	frame.castBar.bar:SetValue(0)

	-- Use the entire bars width and show the icon
	if( config.castBar.icon == "HIDE" ) then
		frame.castBar.bar:SetWidth(frame.castBar:GetWidth())
		frame.castBar.bar:SetAllPoints(frame.castBar)
		frame.castBar.icon:Hide()
	-- Shift the bar to the side and show an icon
	else
		frame.castBar.bar:SetWidth(frame.castBar:GetWidth() - frame.castBar:GetHeight())
		frame.castBar.icon:ClearAllPoints()
		frame.castBar.icon:SetWidth(frame.castBar:GetHeight())
		frame.castBar.icon:SetHeight(frame.castBar:GetHeight())
		frame.castBar.icon:Show()

		if( config.castBar.icon == "LEFT" ) then
			frame.castBar.bar:SetPoint("TOPLEFT", frame.castBar, "TOPLEFT", frame.castBar:GetHeight() + 1, 0)
			frame.castBar.icon:SetPoint("TOPRIGHT", frame.castBar.bar, "TOPLEFT", -1, 0)
		else
			frame.castBar.bar:SetPoint("TOPLEFT", frame.castBar, "TOPLEFT", 1, 0)
			frame.castBar.icon:SetPoint("TOPLEFT", frame.castBar.bar, "TOPRIGHT", 0, 0)
		end
	end

	-- Set the font at the very least, so it doesn't error when we set text on it even if it isn't being shown
	ShadowUF.Layout:ToggleVisibility(frame.castBar.bar.name, config.castBar.name.enabled)
	if( config.castBar.name.enabled ) then
		frame.castBar.bar.name:SetParent(frame.highFrame)
		frame.castBar.bar.name:SetWidth(frame.castBar.bar:GetWidth() * 0.75)
		frame.castBar.bar.name:SetHeight(ShadowUF.db.profile.font.size + 1)
		frame.castBar.bar.name:SetJustifyH(ShadowUF.Layout:GetJustify(config.castBar.name))

		ShadowUF.Layout:AnchorFrame(frame.castBar.bar, frame.castBar.bar.name, config.castBar.name)
		ShadowUF.Layout:SetupFontString(frame.castBar.bar.name, config.castBar.name.size)
	end

	ShadowUF.Layout:ToggleVisibility(frame.castBar.bar.time, config.castBar.time.enabled)
	if( config.castBar.time.enabled ) then
		frame.castBar.bar.time:SetParent(frame.highFrame)
		frame.castBar.bar.time:SetWidth(frame.castBar.bar:GetWidth() * 0.25)
		frame.castBar.bar.time:SetHeight(ShadowUF.db.profile.font.size + 1)
		frame.castBar.bar.time:SetJustifyH(ShadowUF.Layout:GetJustify(config.castBar.time))

		ShadowUF.Layout:AnchorFrame(frame.castBar.bar, frame.castBar.bar.time, config.castBar.time)
		ShadowUF.Layout:SetupFontString(frame.castBar.bar.time, config.castBar.time.size)
	end

	-- So we don't have to check the entire thing in an OnUpdate
	frame.castBar.bar.time.enabled = config.castBar.time.enabled

	if( config.castBar.autoHide and not isCasting(frame.unit) ) then
		ShadowUF.Layout:SetBarVisibility(frame, "castBar", false)
	end
end

function Cast:OnDisable(frame, unit)
	frame:UnregisterAll(self)

	if( frame.castBar ) then
		cancelFakeCastMonitor(frame)

		frame.castBar.bar:SetScript("OnUpdate", nil)
		frame.castBar.bar.active = nil
		frame.castBar.bar.duration = nil
		frame.castBar.bar.name:Hide()
		frame.castBar.bar.time:Hide()
		frame.castBar.bar:Hide()
	end
end

-- Easy coloring
local function setBarColor(self, color)
	self.parent:SetBlockColor(self, "castBar", color.r, color.g, color.b)
end

-- Same as setBarColor, but picks the colour from a (possibly secret) boolean without looking at it
local colorCache = {}
local function makeColor(index, r, g, b, a)
	local color = colorCache[index]
	if( not color ) then
		color = CreateColor(r, g, b, a)
		colorCache[index] = color
	else
		color:SetRGBA(r, g, b, a)
	end
	return color
end

local function setBarColorFromBoolean(self, value, trueColor, falseColor)
	if( not issecretvalue(value) ) then
		setBarColor(self, value and trueColor or falseColor)
		return
	end

	local frame = self.parent
	local bars = ShadowUF.db.profile.bars
	local background = self.background
	local bgColor = background.overrideColor or background.backgroundColor
	local texture = self:GetStatusBarTexture()
	local ok
	if( not ShadowUF.db.profile.units[frame.unitType].castBar.invert ) then
		ok = pcall(texture.SetVertexColorFromBoolean, texture, value, makeColor(1, trueColor.r, trueColor.g, trueColor.b, bars.alpha), makeColor(2, falseColor.r, falseColor.g, falseColor.b, bars.alpha))
		if( not bgColor ) then
			pcall(background.SetVertexColorFromBoolean, background, value, makeColor(3, trueColor.r, trueColor.g, trueColor.b, bars.backgroundAlpha), makeColor(4, falseColor.r, falseColor.g, falseColor.b, bars.backgroundAlpha))
		else
			background:SetVertexColor(bgColor.r, bgColor.g, bgColor.b, bars.backgroundAlpha)
		end
	else
		ok = pcall(background.SetVertexColorFromBoolean, background, value, makeColor(3, trueColor.r, trueColor.g, trueColor.b, bars.alpha), makeColor(4, falseColor.r, falseColor.g, falseColor.b, bars.alpha))
		if( not bgColor ) then
			self:SetStatusBarColor(0, 0, 0, 1 - bars.backgroundAlpha)
		else
			self:SetStatusBarColor(bgColor.r, bgColor.g, bgColor.b, 1 - bars.backgroundAlpha)
		end
	end

	-- Couldn't apply it from the boolean, use the normal colour
	if( not ok ) then setBarColor(self, falseColor) end
end

local function setNormalColor(cast)
	setBarColor(cast, cast.isChannelled and ShadowUF.db.profile.castColors.channel or ShadowUF.db.profile.castColors.cast)
end

-- Stop the game driving the bar from a duration object and show it full
local function fillBar(cast)
	cast.duration = nil
	cast:SetMinMaxValues(0, 1)
	cast:SetValue(1)
end

-- Cast OnUpdates
local function fadeOnUpdate(self, elapsed)
	self.fadeElapsed = self.fadeElapsed - elapsed

	if( self.fadeElapsed <= 0 ) then
		self.fadeElapsed = nil
		self:SetScript("OnUpdate", nil)
		self.name:Hide()
		self.time:Hide()
		self:Hide()

		local frame = self:GetParent()
		if( ShadowUF.db.profile.units[frame.unitType].castBar.autoHide ) then
			ShadowUF.Layout:SetBarVisibility(frame, "castBar", false)
		end
	else
		local alpha = self.fadeElapsed / self.fadeStart
		self:SetAlpha(alpha)
		self.time:SetAlpha(alpha)
		self.name:SetAlpha(alpha)
	end
end

local function startFade(cast, fadeTime)
	cast.fadeElapsed = fadeTime
	cast.fadeStart = fadeTime
	cast:SetScript("OnUpdate", fadeOnUpdate)
end

local function castOnUpdate(self, elapsed)
	local time = GetTime()
	self.elapsed = self.elapsed + (time - self.lastUpdate)
	self.lastUpdate = time
	self:SetValue(self.elapsed)

	if( self.elapsed <= 0 ) then
		self.elapsed = 0
	end

	if( self.time.enabled ) then
		local timeLeft = self.endSeconds - self.elapsed
		if( timeLeft <= 0 ) then
			self.time:SetText("0.0")
		elseif( self.pushback == 0 ) then
			self.time:SetFormattedText("%.1f", timeLeft)
		else
			self.time:SetFormattedText("|cffff0000%.1f|r %.1f", self.pushback, timeLeft)
		end
	end

	-- Cast finished, do a quick fade
	if( self.elapsed >= self.endSeconds ) then
		setBarColor(self, ShadowUF.db.profile.castColors.finished)

		self.spellName = nil
		startFade(self, FADE_TIME)
	end
end

local function channelOnUpdate(self, elapsed)
	local time = GetTime()
	self.elapsed = self.elapsed - (time - self.lastUpdate)
	self.lastUpdate = time
	self:SetValue(self.elapsed)

	if( self.elapsed <= 0 ) then
		self.elapsed = 0
	end

	if( self.time.enabled ) then
		if( self.elapsed <= 0 ) then
			self.time:SetText("0.0")
		elseif( self.pushback == 0 ) then
			self.time:SetFormattedText("%.1f", self.elapsed)
		else
			self.time:SetFormattedText("|cffff0000%.1f|r %.1f", self.pushback, self.elapsed)
		end
	end

	-- Channel finished, do a quick fade
	if( self.elapsed <= 0 ) then
		setBarColor(self, ShadowUF.db.profile.castColors.finished)

		self.spellName = nil
		startFade(self, FADE_TIME)
	end
end

-- Secret casts: the bar moves by itself (SetTimerDuration), we only refresh the text.
-- The end of the cast comes from the STOP/CHANNEL_STOP events since we can't compare the time.
local function setRemainingText(fontString, duration)
	fontString:SetFormattedText("%.1f", duration:GetRemainingDuration())
end

local function timerOnUpdate(self, elapsed)
	if( not self.time.enabled or not self.duration ) then return end

	self.textElapsed = (self.textElapsed or 0) + elapsed
	if( self.textElapsed < SECRET_TEXT_THROTTLE ) then return end
	self.textElapsed = 0

	if( not pcall(setRemainingText, self.time, self.duration) ) then
		self.time:SetText("")
	end
end

-- Hand the bar to a duration object from the game, true if that worked
local function applyTimerDuration(cast, unit, channelled)
	local getDuration = channelled and UnitChannelDuration or UnitCastingDuration
	if( not getDuration or not cast.SetTimerDuration or not Interpolation or not TimerDirection ) then return false end

	local ok, duration = pcall(getDuration, unit)
	if( not ok or duration == nil ) then return false end

	ok = pcall(cast.SetTimerDuration, cast, duration, Interpolation.Immediate, channelled and TimerDirection.RemainingTime or TimerDirection.ElapsedTime)
	if( not ok ) then return false end

	cast.duration = duration
	return true
end

function Cast:UpdateCurrentCast(frame)
	local isChannelled, spell, displayName, icon, startTime, endTime, isTradeSkill, notInterruptible, spellID, castID, castBarID = getCastInfo(frame.unit)
	if( isChannelled ~= nil ) then
		self:UpdateCast(frame, frame.unit, isChannelled, spell, displayName, icon, startTime, endTime, isTradeSkill, notInterruptible, spellID, castID, castBarID)
	else
		if( ShadowUF.db.profile.units[frame.unitType].castBar.autoHide ) then
			ShadowUF.Layout:SetBarVisibility(frame, "castBar", false)
		end

		local cast = frame.castBar.bar
		frame:SetBlockColor(cast, "castBar", 0, 0, 0)

		cast.spellName = nil
		cast.active = nil
		cast.duration = nil
		cast:SetScript("OnUpdate", nil)
		cast.name:Hide()
		cast.time:Hide()
		cast:Hide()
	end
end

-- Cast updated/changed
function Cast:EventUpdateCast(frame)
	local spell, displayName, icon, startTime, endTime, isTradeSkill, castID, notInterruptible, spellID, castBarID = UnitCastingInfo(frame.unit)
	self:UpdateCast(frame, frame.unit, false, spell, displayName, icon, startTime, endTime, isTradeSkill, notInterruptible, spellID, castID, castBarID)
end

function Cast:EventDelayCast(frame)
	local spell, displayName, icon, startTime, endTime = UnitCastingInfo(frame.unit)
	self:UpdateDelay(frame, spell, displayName, icon, startTime, endTime)
end

-- Channel updated/changed
function Cast:EventUpdateChannel(frame)
	local spell, displayName, icon, startTime, endTime, isTradeSkill, notInterruptible, spellID, _, _, castBarID = UnitChannelInfo(frame.unit)
	self:UpdateCast(frame, frame.unit, true, spell, displayName, icon, startTime, endTime, isTradeSkill, notInterruptible, spellID, nil, castBarID)
end

function Cast:EventDelayChannel(frame)
	local spell, displayName, icon, startTime, endTime = UnitChannelInfo(frame.unit)
	self:UpdateDelay(frame, spell, displayName, icon, startTime, endTime)
end

-- Fade out the current cast
function Cast:StopCast(frame)
	local cast = frame.castBar.bar
	if( cast.time.enabled ) then
		cast.time:SetText("0.0")
	end

	if( ShadowUF.db.profile.units[frame.unitType].castBar.autoHide ) then
		ShadowUF.Layout:SetBarVisibility(frame, "castBar", true)
	end

	cast.spellName = nil
	cast.spellID = nil
	cast.castID = nil
	cast.castBarID = nil
	cast.active = nil
	fillBar(cast)
	startFade(cast, FADE_TIME)
	cast:Show()
end

-- Cast finished (STOP) or failed (FAILED)
function Cast:EventStopCast(frame, event, unit, castGUID, spellID, castBarID)
	local cast = frame.castBar.bar
	if( not cast.active or cast.isChannelled ) then return end

	local same = sameCast(cast, castGUID, castBarID)
	if( same == false ) then return end
	-- Can't tell which cast failed; "Another action is in progress" fails other spells while this one keeps casting
	if( same == nil and event == "UNIT_SPELLCAST_FAILED" and isCasting(frame.unit) ) then return end

	self:StopCast(frame)
end

-- Channel finished, or was interrupted (interruptedBy is set)
function Cast:EventStopChannel(frame, event, unit, castGUID, spellID, interruptedBy, castBarID)
	local cast = frame.castBar.bar
	if( not cast.active or not cast.isChannelled ) then return end
	if( castBarID ~= nil and cast.castBarID ~= nil and castBarID ~= cast.castBarID ) then return end

	if( issecretvalue(interruptedBy) or interruptedBy ~= nil ) then
		self:EventInterruptCast(frame, nil, unit)
		return
	end

	self:StopCast(frame)
end

-- Cast interrupted. Called without an event by the fake unit monitor and channel stops
function Cast:EventInterruptCast(frame, event, unit, castGUID, spellID, interruptedBy, castBarID)
	local cast = frame.castBar.bar
	if( event and ( not cast.active or sameCast(cast, castGUID, castBarID) == false ) ) then return end

	setBarColor(cast, ShadowUF.db.profile.castColors.interrupted)
	if( ShadowUF.db.profile.units[frame.unitType].castBar.autoHide ) then
		ShadowUF.Layout:SetBarVisibility(frame, "castBar", true)
	end

	if( ShadowUF.db.profile.units[frame.unitType].castBar.name.enabled ) then
		cast.name:SetText(L["Interrupted"])
	end

	cast.spellID = nil
	cast.active = nil
	fillBar(cast)
	startFade(cast, FADE_TIME + 0.20)
	cast:Show()
end

-- Cast succeeded
function Cast:EventCastSucceeded(frame, event, unit, castGUID, spellID, castBarID)
	local cast = frame.castBar.bar
	if( cast.active and not cast.isChannelled and sameCast(cast, castGUID, castBarID) ) then
		setBarColor(cast, ShadowUF.db.profile.castColors.finished)
	end
end

-- Interruptible status changed
function Cast:EventInterruptible(frame)
	if( not frame.castBar.bar.active ) then return end
	setNormalColor(frame.castBar.bar)
end

function Cast:EventUninterruptible(frame)
	if( not frame.castBar.bar.active ) then return end
	setBarColor(frame.castBar.bar, ShadowUF.db.profile.castColors.uninterruptible)
end

function Cast:UpdateDelay(frame, spell, displayName, icon, startTime, endTime)
	local cast = frame.castBar.bar
	if( not hasValue(spell) or not cast.active ) then return end

	-- Secret cast: just hand the game the updated duration
	if( not cast.startTime or Secrets.Any(startTime, endTime) ) then
		if( cast.duration and not applyTimerDuration(cast, frame.unit, cast.isChannelled) ) then
			cast.duration = nil
		end
		return
	end

	startTime = startTime / 1000
	endTime = endTime / 1000

	-- For a channel, delay is a negative value so using plus is fine here
	local delay = startTime - cast.startTime
	if( not cast.isChannelled ) then
		cast.endSeconds = cast.endSeconds + delay
		cast:SetMinMaxValues(0, cast.endSeconds)
	else
		cast.elapsed = cast.elapsed + delay
	end

	cast.pushback = cast.pushback + delay
	cast.lastUpdate = GetTime()
	cast.startTime = startTime
	cast.endTime = endTime
end

-- Update the actual bar
function Cast:UpdateCast(frame, unit, channelled, spell, displayName, icon, startTime, endTime, isTradeSkill, notInterruptible, spellID, castID, castBarID)
	if( not hasValue(spell) ) then return end
	local cast = frame.castBar.bar
	local config = ShadowUF.db.profile.units[frame.unitType].castBar
	if( config.autoHide ) then
		ShadowUF.Layout:SetBarVisibility(frame, "castBar", true)
	end

	-- BigWigs Spell Name Override
	if( BigWigsAPI and BigWigsAPI.GetSpellRename and ShadowUF.db.profile.bossmodSpellRename and not issecretvalue(spellID) and spellID ) then
		spell = BigWigsAPI.GetSpellRename(spellID) or spell
	end

	-- Set casted spell (may be a secret string, SetText takes those)
	if( config.name.enabled ) then
		cast.name:SetText(spell)
		cast.name:SetAlpha(ShadowUF.db.profile.bars.alpha)
		cast.name:Show()
	end

	-- Show cast time
	if( cast.time.enabled ) then
		cast.time:SetAlpha(1)
		cast.time:Show()
	end

	-- Set spell icon (may be secret, SetTexture takes those)
	if( config.icon ~= "HIDE" ) then
		frame.castBar.icon:SetTexture(icon)
		frame.castBar.icon:Show()
	end

	-- Setup cast info
	cast.active = true
	cast.isChannelled = channelled
	cast.spellName = spell
	cast.spellID = Secrets.Plain(spellID)
	cast.castID = Secrets.Plain(castID)
	cast.castBarID = castBarID
	cast.pushback = 0
	cast.fadeElapsed = nil
	cast.duration = nil

	if( not Secrets.Any(startTime, endTime) ) then
		local now = GetTime()
		cast.startTime = startTime / 1000
		cast.endTime = endTime / 1000
		cast.endSeconds = cast.endTime - cast.startTime
		cast.elapsed = cast.isChannelled and (cast.endTime - now) or (now - cast.startTime)
		cast.lastUpdate = now
		cast:SetMinMaxValues(0, cast.endSeconds)
		cast:SetValue(cast.elapsed)
		cast:SetScript("OnUpdate", cast.isChannelled and channelOnUpdate or castOnUpdate)
	else
		cast.startTime = nil
		cast.endTime = nil
		cast.endSeconds = nil
		cast.textElapsed = SECRET_TEXT_THROTTLE
		if( not applyTimerDuration(cast, unit, channelled) ) then
			-- Nothing to time it with, at least show that something is being cast
			cast:SetMinMaxValues(0, 1)
			cast:SetValue(1)
			if( cast.time.enabled ) then cast.time:SetText("") end
		end
		cast:SetScript("OnUpdate", timerOnUpdate)
	end

	cast:SetAlpha(ShadowUF.db.profile.bars.alpha)
	cast:Show()

	setBarColorFromBoolean(cast, notInterruptible, ShadowUF.db.profile.castColors.uninterruptible, channelled and ShadowUF.db.profile.castColors.channel or ShadowUF.db.profile.castColors.cast)
end

-- Trigger checks on fake cast
function Cast:UpdateFakeCast(f)
	local monitor = f.castBar.monitor
	monitor.active = nil
	monitor.isChannelled = nil
	monitor.endTime = nil
	monitor.notInterruptible = nil
	monitor.castBarID = nil
	monitor.castID = nil
	monitorFakeCast(monitor)

	-- Nothing being cast by the new unit
	if( not monitor.active ) then
		self:UpdateCurrentCast(f)
	end
end
