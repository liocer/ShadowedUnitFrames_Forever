-- A rough WoW Forever environment for loading an addon in plain Lua 5.1.
-- Simulates secret values: a secret is a userdata that errors on arithmetic,
-- ordering comparisons, indexing, calling, # and (between secrets) ==.
-- Widget methods and global APIs that don't accept secrets from addon code
-- raise an error when handed one, using the rules from the client's API docs.
-- Errors are collected (deduplicated by location) rather than stopping the run.

local H = {}
_G.HARNESS = H
H.errors, H.errorOrder, H.notes = {}, {}, {}
H.unmocked = {}

local HERE = debug.getinfo(1, "S").source:match("^@(.*/)") or "./"
local widgetRules = dofile(HERE .. "widgetapi.lua")
local apiRules = dofile(HERE .. "apirules.lua")

---------------------------------------------------------------------------
-- Secrets
---------------------------------------------------------------------------
local secretValues = setmetatable({}, {__mode = "k"})
local secretMeta
local function isSecret(v) return type(v) == "userdata" and secretValues[v] ~= nil end
local function unwrap(v) if isSecret(v) then return secretValues[v][1] end return v end

local function secretError(what)
	return function() error("attempt to " .. what .. " a secret value", 2) end
end

local function makeSecret(v)
	if v == nil then return nil end
	if isSecret(v) then return v end
	local p = newproxy(true)
	local mt = getmetatable(p)
	for k, f in pairs(secretMeta) do mt[k] = f end
	secretValues[p] = {v}
	return p
end
H.secret = makeSecret
H.unwrap = unwrap

secretMeta = {
	__add = secretError("perform arithmetic on"), __sub = secretError("perform arithmetic on"),
	__mul = secretError("perform arithmetic on"), __div = secretError("perform arithmetic on"),
	__mod = secretError("perform arithmetic on"), __pow = secretError("perform arithmetic on"),
	__unm = secretError("perform arithmetic on"), __lt = secretError("compare"), __le = secretError("compare"),
	__eq = secretError("compare"), __len = secretError("get length of"),
	__index = secretError("index"), __newindex = secretError("index"), __call = secretError("call"),
	__concat = function(a, b) return makeSecret(tostring(unwrap(a)) .. tostring(unwrap(b))) end,
	__tostring = function() return "<secret>" end,
}

function issecretvalue(v) return isSecret(v) end
function issecrettable() return false end
function canaccessvalue(v) return not isSecret(v) end
function canaccesstable() return true end
function canaccesssecrets() return false end
function hasanysecretvalues(...) for i = 1, select("#", ...) do if isSecret((select(i, ...))) then return true end end return false end
function scrubsecretvalues(...) local t = {...} for i = 1, select("#", ...) do if isSecret(t[i]) then t[i] = nil end end return unpack(t, 1, select("#", ...)) end
function secretwrap(...) local t = {...} for i = 1, select("#", ...) do t[i] = makeSecret(t[i]) end return unpack(t, 1, select("#", ...)) end
function mapvalues(fn, ...) local t = {...} for i = 1, select("#", ...) do t[i] = fn(t[i]) end return unpack(t, 1, select("#", ...)) end

local function anySecret(...)
	for i = 1, select("#", ...) do if isSecret((select(i, ...))) then return true end end
	return false
end

-- string.format / tostring accept secrets and give a secret string
local rawformat, rawtostring = string.format, tostring
string.format = function(fmt, ...)
	if anySecret(fmt, ...) then
		local args = {...}
		for i = 1, select("#", ...) do args[i] = unwrap(args[i]) end
		return makeSecret(rawformat(unwrap(fmt), unpack(args, 1, select("#", ...))))
	end
	return rawformat(fmt, ...)
end
format = string.format
tostring = function(v) if isSecret(v) then return makeSecret(rawtostring(unwrap(v))) end return rawtostring(v) end
local stringMeta = getmetatable("")
stringMeta.__index = string

---------------------------------------------------------------------------
-- Error collection
---------------------------------------------------------------------------
local function location(tb)
	for line in tb:gmatch("[^\n]+") do
		local loc = line:match("^%s*(.-ShadowedU[^:]*:%d+)")
		if loc and not loc:find("harness") then return loc end
	end
	return tb:match("[^\n]+") or "?"
end

function H.report(err, tb, context)
	tb = tb or debug.traceback("", 2)
	local addonLine = rawtostring(err):match("(ShadowedU[^:]*:%d+)") or location(tb)
	local key = addonLine .. " " .. rawtostring(err):gsub("^.-:%d+: ", "")
	if not H.errors[key] then
		H.errors[key] = {err = rawtostring(err), tb = tb, count = 0, context = context}
		table.insert(H.errorOrder, key)
	end
	H.errors[key].count = H.errors[key].count + 1
end

function H.pcall(context, fn, ...)
	local args, n = {...}, select("#", ...)
	return xpcall(function() return fn(unpack(args, 1, n)) end, function(e)
		H.report(e, debug.traceback(rawtostring(e), 2), context)
		return e
	end)
end

function geterrorhandler() return function(e) H.report(e, debug.traceback(rawtostring(e), 2), "errorhandler") end end
function seterrorhandler() end
function securecall(fn, ...) if type(fn) == "string" then fn = _G[fn] end local ok, a, b, c, d = H.pcall("securecall", fn, ...) if ok then return a, b, c, d end end
securecallfunction = securecall
function securecallmethod(obj, m, ...) return securecall(obj[m], obj, ...) end

---------------------------------------------------------------------------
-- Lua extensions
---------------------------------------------------------------------------
function strsplit(sep, str, limit)
	local out, pattern = {}, "([^" .. sep:gsub("%%", "%%%%") .. "]*)"
	str = unwrap(str)
	local pos = 1
	while true do
		if limit and #out == limit - 1 then table.insert(out, str:sub(pos)) break end
		local s, e = str:find("[" .. sep:gsub("%p", "%%%0") .. "]", pos)
		if not s then table.insert(out, str:sub(pos)) break end
		table.insert(out, str:sub(pos, s - 1))
		pos = e + 1
	end
	return unpack(out)
end
string.split = function(str, sep, limit) return strsplit(sep, str, limit) end
function strtrim(s, chars) chars = chars or " \t\r\n" local p = "[" .. chars:gsub("%p", "%%%0") .. "]" return (s:gsub("^" .. p .. "+", ""):gsub(p .. "+$", "")) end
string.trim = strtrim
function strjoin(sep, ...) return table.concat({...}, sep) end
string.join = strjoin
function strconcat(...) return table.concat({...}) end
function tostringall(...) local t = {...} for i = 1, select("#", ...) do t[i] = tostring(t[i]) end return unpack(t, 1, select("#", ...)) end
strlen, strsub, strfind, strmatch, gsub, strlower, strupper, strrep, strbyte, strchar, strrev =
	string.len, string.sub, string.find, string.match, string.gsub, string.lower, string.upper, string.rep, string.byte, string.char, string.reverse
gmatch = string.gmatch
strlenutf8 = function(s) return #s end
string.utf8sub = function(s, i, j) return s:sub(i, j) end
tinsert, tremove, sort, wipe = table.insert, table.remove, table.sort, function(t) for k in pairs(t) do t[k] = nil end return t end
table.wipe = wipe
function tContains(t, v) for _, x in pairs(t) do if x == v then return true end end return false end
function tInvert(t) local o = {} for k, v in pairs(t) do o[v] = k end return o end
function CopyTable(t) local o = {} for k, v in pairs(t) do o[k] = type(v) == "table" and CopyTable(v) or v end return o end
floor, ceil, abs, max, min, sqrt, mod, random = math.floor, math.ceil, math.abs, math.max, math.min, math.sqrt, math.fmod, math.random
fmod = math.fmod
PI = math.pi
function Clamp(v, a, b) return math.min(math.max(v, a), b) end
function Lerp(a, b, t) return a + (b - a) * t end
function Round(v) return math.floor(v + 0.5) end
bit = bit or {band = function(a, b) return 0 end, bor = function(a, b) return a end, lshift = function(a, b) return a * 2 ^ b end, rshift = function(a, b) return math.floor(a / 2 ^ b) end, bnot = function(a) return -a - 1 end}
function debugstack() return debug.traceback() end
function debugprofilestop() return os.clock() * 1000 end
function issecure() return false end
function issecurevariable() return false end
function forceinsecure() end
function hooksecurefunc(tbl, name, fn)
	if type(tbl) == "string" then tbl, name, fn = _G, tbl, name end
	local orig = tbl[name]
	if type(orig) ~= "function" then H.report("hooksecurefunc on non-function " .. rawtostring(name)) return end
	tbl[name] = function(...) local a, b, c, d, e = orig(...) fn(...) return a, b, c, d, e end
end
function getglobal(n) return _G[n] end
function setglobal(n, v) _G[n] = v end
function GetTime() return H.time end
function time() return os.time() end
function date(...) return os.date(...) end
H.time = 1000

---------------------------------------------------------------------------
-- Widgets
---------------------------------------------------------------------------
local ruleChain = {
	Frame = {"SimpleFrameAPI", "SimpleScriptRegionResizingAPI", "SimpleScriptRegionAPI", "SimpleRegionAPI", "SimpleObjectAPI", "SimpleFrameScriptObjectAPI"},
	Texture = {"SimpleTextureAPI", "SimpleTextureBaseAPI", "SimpleRegionAPI", "SimpleScriptRegionResizingAPI", "SimpleScriptRegionAPI", "SimpleObjectAPI", "SimpleFrameScriptObjectAPI"},
	FontString = {"SimpleFontStringAPI", "SimpleRegionAPI", "SimpleScriptRegionResizingAPI", "SimpleScriptRegionAPI", "SimpleObjectAPI", "SimpleFrameScriptObjectAPI"},
}
ruleChain.MaskTexture = ruleChain.Texture
ruleChain.Line = ruleChain.Texture
local function chainFor(t)
	if ruleChain[t] then return ruleChain[t] end
	local own = ({StatusBar = "SimpleStatusBarAPI", Button = "SimpleButtonAPI", CheckButton = "SimpleCheckboxAPI", Cooldown = "FrameAPICooldown",
		EditBox = "SimpleEditBoxAPI", Slider = "SimpleSliderAPI", ScrollFrame = "SimpleScrollFrameAPI", Model = "SimpleModelAPI", PlayerModel = "FrameAPICharacterModelBase",
		GameTooltip = "FrameAPITooltip", MessageFrame = "SimpleMessageFrameAPI", ColorSelect = "SimpleColorSelectAPI", AnimationGroup = "SimpleAnimGroupAPI",
		Animation = "SimpleAnimAPI", Alpha = "SimpleAnimAlphaAPI"})[t]
	local chain = {}
	if own then table.insert(chain, own) end
	if t == "PlayerModel" then table.insert(chain, "SimpleModelAPI") end
	for _, v in ipairs(ruleChain.Frame) do table.insert(chain, v) end
	ruleChain[t] = chain
	return chain
end

local function secretRule(objType, method)
	for _, api in ipairs(chainFor(objType)) do
		local r = widgetRules[api] and widgetRules[api][method]
		if r then return r end
	end
	return nil
end

local Widget = {}
local widgetMeta = {}
local allFrames, namedFrames = {}, {}
H.allFrames = allFrames

local function noop() end

local function newWidget(objType, name, parent, template)
	local w = {__type = objType, __name = name, __parent = parent, __shown = true, __points = {}, __scripts = {}, __attrs = {},
		__children = {}, __regions = {}, __w = 0, __h = 0, __level = parent and parent.GetFrameLevel and (parent:GetFrameLevel() + 1) or 1,
		__alpha = 1, __scale = 1, __events = {}, __unitEvents = {}, __min = 0, __max = 1, __value = 0, __text = nil, __template = template}
	setmetatable(w, widgetMeta)
	if parent and parent.__children and objType ~= "Texture" and objType ~= "FontString" then table.insert(parent.__children, w) end
	if name and name ~= "" then
		if name:find("$parent") and parent then name = name:gsub("%$parent", parent:GetName() or "") end
		w.__name = name
		_G[name] = w
		namedFrames[name] = w
	end
	table.insert(allFrames, w)
	return w
end
H.newWidget = newWidget

widgetMeta.__index = function(self, key)
	local m = Widget[key]
	if m then
		local rule = secretRule(self.__type, key)
		if rule and rule ~= "AllowedWhenTainted" then
			return function(...)
				if anySecret(select(2, ...)) then error(rawformat("%s:%s doesn't accept secret values from addons (%s)", self.__type, key, rule), 2) end
				return m(...)
			end
		end
		return m
	end
	local rule = type(key) == "string" and secretRule(self.__type, key)
	if rule then
		H.unmocked[key] = (H.unmocked[key] or 0) + 1
		return function(_, ...)
			if rule and rule ~= "AllowedWhenTainted" and anySecret(...) then error(rawformat("%s:%s doesn't accept secret values from addons (%s)", self.__type, key, rule), 2) end
		end
	end
	return nil
end

local function fire(self, script, ...)
	local fn = self.__scripts[script]
	if fn then return H.pcall(script, fn, self, ...) end
end
H.fire = fire

function Widget:GetName() return self.__name end
function Widget:GetDebugName() return self.__name or "anon" end
function Widget:GetParent() return self.__parent end
function Widget:SetParent(p) self.__parent = p end
function Widget:GetObjectType() return self.__type end
function Widget:IsObjectType(t) return self.__type == t or t == "Frame" or t == "Region" or t == "Object" end
function Widget:IsForbidden() return false end
function Widget:IsProtected() return false end
function Widget:CanChangeProtectedState() return true end
function Widget:Show() if not self.__shown then self.__shown = true fire(self, "OnShow") end end
function Widget:Hide() if self.__shown then self.__shown = false fire(self, "OnHide") end end
function Widget:SetShown(s) if s then self:Show() else self:Hide() end end
function Widget:IsShown() return self.__shown end
function Widget:IsVisible() local p = self while p do if not p.__shown then return false end p = p.__parent end return true end
function Widget:SetAlpha(a) self.__alpha = a end
function Widget:GetAlpha() return self.__alpha end
function Widget:GetEffectiveAlpha() return self.__alpha end
function Widget:SetAlphaFromBoolean(b, t, f) self.__alpha = makeSecret(1) end
function Widget:SetVertexColorFromBoolean() end
function Widget:SetScale(s) self.__scale = s end
function Widget:GetScale() return self.__scale end
function Widget:GetEffectiveScale() return self.__scale end
function Widget:SetWidth(v) self.__w = v end
function Widget:SetHeight(v) self.__h = v end
function Widget:SetSize(w, h) self.__w, self.__h = w, h end
function Widget:GetWidth() return self.__w end
function Widget:GetHeight() return self.__h end
function Widget:GetSize() return self.__w, self.__h end
function Widget:GetRect() return 0, 0, self.__w, self.__h end
function Widget:GetLeft() return 100 end
function Widget:GetRight() return 100 + self.__w end
function Widget:GetTop() return 500 end
function Widget:GetBottom() return 500 - self.__h end
function Widget:GetCenter() return 100 + self.__w / 2, 500 - self.__h / 2 end
function Widget:SetPoint(p, rel, rp, x, y)
	if type(rel) == "number" then x, y, rel, rp = rel, rp, nil, nil end
	table.insert(self.__points, {p, rel, rp or p, x or 0, y or 0})
end
function Widget:SetAllPoints() self.__points = {{"TOPLEFT"}, {"BOTTOMRIGHT"}} end
function Widget:ClearAllPoints() self.__points = {} end
function Widget:GetNumPoints() return #self.__points end
function Widget:GetPoint(i) local p = self.__points[i or 1] if p then return p[1], p[2], p[3], p[4], p[5] end end
function Widget:GetPointByName(n) for _, p in ipairs(self.__points) do if p[1] == n then return unpack(p) end end end
function Widget:SetFrameLevel(l) self.__level = l end
function Widget:GetFrameLevel() return self.__level end
function Widget:SetFrameStrata(s) self.__strata = s end
function Widget:GetFrameStrata() return self.__strata or "MEDIUM" end
function Widget:SetScript(s, fn) self.__scripts[s] = fn end
function Widget:GetScript(s) return self.__scripts[s] end
function Widget:HookScript(s, fn)
	local old = self.__scripts[s]
	self.__scripts[s] = old and function(...) old(...) fn(...) end or fn
end
function Widget:HasScript(s) return true end
function Widget:SetAttribute(k, v)
	self.__attrs[k] = v
	fire(self, "OnAttributeChanged", k, v)
end
function Widget:SetAttributeNoHandler(k, v) self.__attrs[k] = v end
function Widget:GetAttribute(k) return self.__attrs[k] end
function Widget:RegisterEvent(e) H.registerEvent(self, e) end
function Widget:RegisterUnitEvent(e, ...) H.registerEvent(self, e, ...) end
function Widget:UnregisterEvent(e) H.unregisterEvent(self, e) end
function Widget:UnregisterAllEvents() for e in pairs(self.__events) do H.unregisterEvent(self, e) end end
function Widget:IsEventRegistered(e) return self.__events[e] ~= nil end
function Widget:RegisterAllEvents() end
function Widget:GetChildren() return unpack(self.__children) end
function Widget:GetNumChildren() return #self.__children end
function Widget:GetRegions() return unpack(self.__regions) end
function Widget:CreateTexture(name, layer) local t = newWidget("Texture", name, self) t.__layer = layer table.insert(self.__regions, t) return t end
function Widget:CreateMaskTexture(name) return newWidget("MaskTexture", name, self) end
function Widget:CreateLine(name) return newWidget("Line", name, self) end
function Widget:CreateFontString(name, layer, inherits) local f = newWidget("FontString", name, self) f.__font = {"Fonts\\FRIZQT__.TTF", 12, ""} table.insert(self.__regions, f) return f end
function Widget:CreateAnimationGroup(name) return newWidget("AnimationGroup", name, self) end
function Widget:CreateAnimation(t, name) return newWidget(t or "Animation", name, self) end
function Widget:IsPlaying() return false end
function Widget:GetID() return self.__id or 0 end
function Widget:SetID(i) self.__id = i end
function Widget:IsMouseOver() return false end
function Widget:IsMouseEnabled() return self.__mouse or false end
function Widget:EnableMouse(b) self.__mouse = b end
function Widget:GetHitRectInsets() return 0, 0, 0, 0 end
function Widget:GetFrameRef(n) return self.__refs and self.__refs[n] end
function Widget:SetFrameRef(n, f) self.__refs = self.__refs or {} self.__refs[n] = f end
function Widget:CallMethod(m, ...) if self[m] then return self[m](self, ...) end end
function Widget:Execute() end
function Widget:WrapScript() end
function Widget:UnwrapScript() end
function Widget:RunAttribute() end
function Widget:IsAnchoringRestricted() return false end
function Widget:IsDragging() return false end
-- status bars
function Widget:SetMinMaxValues(a, b) self.__min, self.__max = a, b if anySecret(a, b) then self.__secretValue = true end end
function Widget:GetMinMaxValues() if self.__secretValue then return makeSecret(unwrap(self.__min)), makeSecret(unwrap(self.__max)) end return self.__min, self.__max end
function Widget:SetValue(v) self.__value = v if isSecret(v) then self.__secretValue = true end end
function Widget:GetValue() if self.__secretValue then return makeSecret(unwrap(self.__value)) end return self.__value end
function Widget:GetStatusBarTexture() if not self.__sbtex then self.__sbtex = newWidget("Texture", nil, self) end return self.__sbtex end
function Widget:SetStatusBarTexture(t) self:GetStatusBarTexture().__tex = t end
function Widget:GetOrientation() return self.__orient or "HORIZONTAL" end
function Widget:SetOrientation(o) self.__orient = o end
function Widget:GetReverseFill() return self.__reverse or false end
function Widget:SetReverseFill(r) self.__reverse = r end
function Widget:GetStatusBarColor() return 1, 1, 1, 1 end
function Widget:SetTimerDuration(d) self.__duration = d end
-- textures
function Widget:GetTexture() return self.__tex end
function Widget:SetTexture(t) self.__tex = t return true end
function Widget:SetAtlas(a) self.__tex = a return true end
function Widget:GetTexCoord() return 0, 0, 0, 1, 1, 0, 1, 1 end
function Widget:GetVertexColor() return 1, 1, 1, 1 end
function Widget:GetDrawLayer() return self.__layer or "ARTWORK", 0 end
function Widget:GetNormalTexture() return self.__normal or self:CreateTexture() end
function Widget:GetHighlightTexture() return self.__highlight or self:CreateTexture() end
function Widget:GetPushedTexture() return self:CreateTexture() end
function Widget:GetDisabledTexture() return self:CreateTexture() end
function Widget:GetCheckedTexture() return self:CreateTexture() end
function Widget:GetFontString() self.__fs = self.__fs or self:CreateFontString() return self.__fs end
-- font strings
function Widget:SetFont(path, size, flags) self.__font = {path, size, flags} return true end
function Widget:GetFont() local f = self.__font or {"Fonts\\FRIZQT__.TTF", 12, ""} return f[1], f[2], f[3] end
function Widget:SetFontObject(o) self.__fontObject = o end
function Widget:GetFontObject() return self.__fontObject end
function Widget:SetText(t) self.__text = t end
function Widget:SetFormattedText(fmt, ...) self.__text = string.format(fmt, ...) end
function Widget:GetText() return self.__text end
function Widget:GetStringWidth() return 10 end
function Widget:GetStringHeight() return 10 end
function Widget:GetUnboundedStringWidth() return 10 end
function Widget:GetNumLines() return 1 end
function Widget:GetLineHeight() return 12 end
function Widget:GetJustifyH() return "CENTER" end
function Widget:GetJustifyV() return "MIDDLE" end
function Widget:GetShadowOffset() return 0, 0 end
function Widget:GetShadowColor() return 0, 0, 0, 1 end
function Widget:GetTextColor() return 1, 1, 1, 1 end
function Widget:CanWordWrap() return true end
function Widget:IsTruncated() return false end
-- cooldowns
function Widget:GetCooldownTimes() return 0, 0 end
function Widget:GetCooldownDuration() return 0 end
-- edit boxes / sliders / buttons
function Widget:GetNumber() return 0 end
function Widget:HasFocus() return false end
function Widget:GetCursorPosition() return 0 end
function Widget:GetMaxLetters() return 0 end
function Widget:GetChecked() return self.__checked end
function Widget:SetChecked(c) self.__checked = c end
function Widget:IsEnabled() return self.__enabled ~= false end
function Widget:Enable() self.__enabled = true end
function Widget:Disable() self.__enabled = false end
function Widget:SetEnabled(e) self.__enabled = e end
function Widget:GetButtonState() return "NORMAL" end
function Widget:GetVerticalScroll() return 0 end
function Widget:GetHorizontalScroll() return 0 end
function Widget:GetVerticalScrollRange() return 0 end
function Widget:GetScrollChild() return self.__scrollchild end
function Widget:SetScrollChild(c) self.__scrollchild = c end
function Widget:GetValueStep() return 1 end
function Widget:GetThumbTexture() return self:CreateTexture() end
function Widget:GetBackdrop() return self.__backdrop end
function Widget:SetBackdrop(b) self.__backdrop = b end
function Widget:GetBackdropColor() return 0, 0, 0, 1 end
function Widget:GetBackdropBorderColor() return 0, 0, 0, 1 end
-- tooltips
function Widget:NumLines() return 0 end
function Widget:GetOwner() return self.__owner end
function Widget:SetOwner(o) self.__owner = o end
function Widget:IsOwned(o) return self.__owner == o end
function Widget:GetUnit() return nil end
-- models
function Widget:GetModelFileID() return nil end
function Widget:GetCameraDistance() return 1 end
-- scroll / misc
function Widget:GetEffectiveScale() return 1 end
function Widget:GetPropagateKeyboardInput() return false end

local function applyTemplates(w, template)
	if not template then return end
	for t in tostring(template):gmatch("[^,%s]+") do
		local tmpl = H.templates[t]
		if tmpl then tmpl(w) end
		if t:find("Backdrop") then
			for _, m in ipairs({"ApplyBackdrop", "ClearBackdrop", "SetBackdropColor", "SetBackdropBorderColor", "SetupBackdrop", "OnBackdropSizeChanged"}) do w[m] = function() end end
			w.SetBackdrop = function(self, b) self.__backdrop = b end
			w.GetBackdrop = function(self) return self.__backdrop end
			w.GetBackdropColor = function() return 0, 0, 0, 1 end
			w.GetBackdropBorderColor = function() return 0, 0, 0, 1 end
		end
	end
end

H.templates = {}
function CreateFrame(objType, name, parent, template, id)
	if parent == nil and objType ~= "GameTooltip" then parent = nil end
	local t = objType
	if t == "CheckButton" or t == "Button" or t == "StatusBar" or t == "Cooldown" or t == "Frame" or t == "EditBox" or t == "Slider"
		or t == "ScrollFrame" or t == "GameTooltip" or t == "PlayerModel" or t == "Model" or t == "ColorSelect" or t == "MessageFrame"
		or t == "SimpleHTML" or t == "DressUpModel" or t == "ModelScene" or t == "ScrollingMessageFrame" or t == "Minimap" then
	else
		H.report("CreateFrame: unknown frame type " .. rawtostring(objType))
	end
	local w = newWidget(objType, name, parent, template)
	if id then w.__id = id end
	applyTemplates(w, template)
	fire(w, "OnLoad")
	return w
end

UIParent = newWidget("Frame", "UIParent")
UIParent.__w, UIParent.__h = 1920, 1080
WorldFrame = newWidget("Frame", "WorldFrame")
GameTooltip = newWidget("GameTooltip", "GameTooltip", UIParent)
GameFontNormal = newWidget("Font", "GameFontNormal")
for _, n in ipairs({"GameFontHighlight", "GameFontHighlightSmall", "GameFontNormalSmall", "GameFontNormalLarge", "GameFontDisable", "GameFontHighlightLarge",
	"ChatFontNormal", "GameFontNormalHuge", "NumberFontNormal", "SystemFont_Shadow_Med1", "GameFontDisableSmall", "GameFontRed", "GameFontGreen",
	"GameFontHighlightMedium", "GameFontNormalMed3", "TextStatusBarText", "GameFontWhite", "SubZoneTextFont", "ZoneTextFont", "GameFontBlack",
	"GameFontHighlightSmallOutline", "NumberFontNormalSmall", "GameTooltipText", "GameTooltipTextSmall", "GameTooltipHeaderText"}) do
	_G[n] = newWidget("Font", n)
end
function CreateFont(name) local f = newWidget("Font", name) return f end
DEFAULT_CHAT_FRAME = newWidget("MessageFrame", "ChatFrame1", UIParent)
ChatFrame1 = DEFAULT_CHAT_FRAME
function DEFAULT_CHAT_FRAME:AddMessage(msg) table.insert(H.notes, "chat: " .. rawtostring(unwrap(msg))) end
function print(...) local t = {} for i = 1, select("#", ...) do t[i] = rawtostring(unwrap((select(i, ...)))) end table.insert(H.notes, "print: " .. table.concat(t, " ")) end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local eventFrames = {}
function H.registerEvent(frame, event, ...)
	if type(event) ~= "string" or not event:match("^[A-Z_0-9]+$") then error("RegisterEvent: bad event " .. rawtostring(event), 3) end
	if H.knownEvents and not H.knownEvents[event] then
		H.report("RegisterEvent: event doesn't exist on this client: " .. event, debug.traceback("", 3))
		return false
	end
	eventFrames[event] = eventFrames[event] or {}
	eventFrames[event][frame] = true
	frame.__events[event] = true
	local units = {...}
	frame.__unitEvents[event] = #units > 0 and units or nil
	return true
end
function H.unregisterEvent(frame, event)
	if eventFrames[event] then eventFrames[event][frame] = nil end
	frame.__events[event] = nil
end
function H.fireEvent(event, ...)
	local list = {}
	for f in pairs(eventFrames[event] or {}) do table.insert(list, f) end
	for _, f in ipairs(list) do
		local units = f.__unitEvents[event]
		local ok = true
		if units then
			ok = false
			for _, u in ipairs(units) do if u == (...) then ok = true end end
		end
		if ok and f.__events[event] then fire(f, "OnEvent", event, ...) end
	end
end
function H.tick(elapsed, count)
	for _ = 1, count or 1 do
		H.time = H.time + elapsed
		H.runTimers()
		for _, f in ipairs(allFrames) do
			if f.__scripts.OnUpdate and f:IsVisible() then fire(f, "OnUpdate", elapsed) end
		end
	end
end

---------------------------------------------------------------------------
-- Timers
---------------------------------------------------------------------------
local timers = {}
function H.runTimers()
	local due = {}
	for t in pairs(timers) do if t.at <= H.time and not t.cancelled then table.insert(due, t) end end
	for _, t in ipairs(due) do
		H.pcall("timer", t.fn, t)
		if t.every and not t.cancelled and (not t.iterations or t.iterations > 1) then
			t.at = H.time + t.every
			if t.iterations then t.iterations = t.iterations - 1 end
		else
			timers[t] = nil
		end
	end
end
local Ticker = {}
Ticker.__index = Ticker
function Ticker:Cancel() self.cancelled = true timers[self] = nil end
function Ticker:IsCancelled() return self.cancelled end
C_Timer = {
	After = function(d, fn) timers[setmetatable({at = H.time + d, fn = fn}, Ticker)] = true end,
	NewTimer = function(d, fn) local t = setmetatable({at = H.time + d, fn = fn}, Ticker) timers[t] = true return t end,
	NewTicker = function(d, fn, n) local t = setmetatable({at = H.time + d, fn = fn, every = d, iterations = n}, Ticker) timers[t] = true return t end,
}

return H
