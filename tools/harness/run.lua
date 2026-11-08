-- Usage: lua5.1 run.lua <repo> [scenario]
-- Loads SUF Forever in the mock client, logs in, plays a few update cycles out of
-- combat and in combat (secret values), opens the options, and prints every
-- distinct error with where it came from.
local HERE = debug.getinfo(1, "S").source:match("^@(.*/)") or "./"
local REPO = assert(arg[1], "repo path")
local H = dofile(HERE .. "wow.lua")
H.knownEvents = dofile(HERE .. "events.lua")
dofile(HERE .. "api.lua")
do
	local class = os.getenv("CLASS")
	local spec = {ROGUE = {4, 3}, WARRIOR = {1, 1}, SHAMAN = {7, 0}, HUNTER = {3, 0}, PRIEST = {5, 0}, MAGE = {8, 0}, WARLOCK = {9, 0}, PALADIN = {2, 0}, DRUID = {11, 0}}
	if class and spec[class] then
		local p = H.units.player
		p.class, p.classID, p.powerType = class, spec[class][1], spec[class][2]
	end
end

-- Globals the client has but we didn't mock: callable no-op stubs (and counted).
-- ALL_CAPS names we don't know are treated as GlobalStrings.
local known = {}
for _, n in ipairs(dofile(REPO .. "/tools/forever_globals.lua")) do known[n] = true end
H.stubCalls = {}
setmetatable(_G, {__index = function(t, k)
	if type(k) ~= "string" then return nil end
	if known[k] then
		if k:match("^[A-Z][A-Z0-9_]+$") then return k end
		if k:match("Frame$") or k:match("Bar$") or k:match("Container$") or k:match("Frame%d*$") then
			local f = H.newWidget("Frame", nil, UIParent) rawset(t, k, f) f.__name = k return f
		end
		local stub = setmetatable({}, {__call = function() H.stubCalls[k] = (H.stubCalls[k] or 0) + 1 end,
			__index = function(_, kk) return function() H.stubCalls[k .. "." .. tostring(kk)] = (H.stubCalls[k .. "." .. tostring(kk)] or 0) + 1 end end})
		return stub
	end
	if k:match("^[A-Z][A-Z0-9_]+$") and #k > 3 and not k:find("CALLBACK") and not k:find("CUSTOM_") then return k end
	return nil
end})

local addonDirs = {
	ShadowedUnitFrames_Forever = REPO,
	ShadowedUF_Forever_Options = REPO .. "/options",
}

local function readFile(p) local f = io.open(p, "rb") if not f then return nil end local s = f:read("*a") f:close() return s end

local loadFile
local function loadXML(path, addonName, ns)
	local src = readFile(path)
	if not src then H.report("missing file " .. path) return end
	local dir = path:match("^(.*)/[^/]*$")
	src = src:gsub("<!%-%-.-%-%->", "")
	-- templates with attributes
	for name, body in src:gmatch('<%w+%s+name="([%w_]+)"[^>]-virtual="true"[^>]*>(.-)</%w+>') do
		H.templates[name] = function(w)
			for k, v in body:gmatch('<Attribute%s+name="([^"]+)"%s+type="%w+"%s+value="([^"]*)"') do w.__attrs[k] = v end
		end
	end
	for tag, file in src:gmatch('<(%w+)%s+file="([^"]+)"') do
		if tag == "Script" or tag == "Include" then
			loadFile(dir .. "/" .. file:gsub("\\", "/"), addonName, ns)
		end
	end
end

function loadFile(path, addonName, ns)
	if path:lower():match("%.xml$") then return loadXML(path, addonName, ns) end
	local chunk, err = loadfile(path)
	if not chunk then H.report("syntax: " .. err) return end
	H.pcall("load " .. path:match("[^/]+$"), chunk, addonName, ns)
end

function H.loadAddon(name)
	if H.loadedAddons[name] then return true end
	local dir = addonDirs[name]
	if not dir then return false, "MISSING" end
	local toc
	for _, f in ipairs({name .. ".toc", name .. "_Mainline.toc"}) do toc = toc or readFile(dir .. "/" .. f) end
	if not toc then H.report("no toc for " .. name) return false, "MISSING" end
	local ns = {}
	for line in toc:gmatch("[^\r\n]+") do
		line = line:gsub("^%s+", ""):gsub("%s+$", "")
		local deps = line:match("^## Dependencies:%s*(.+)") or line:match("^## RequiredDeps:%s*(.+)")
		if deps then for d in deps:gmatch("[^,%s]+") do H.loadAddon(d) end end
		if line ~= "" and not line:match("^#") then
			loadFile(dir .. "/" .. line:gsub("\\", "/"), name, ns)
		end
	end
	H.loadedAddons[name] = true
	H.fireEvent("ADDON_LOADED", name)
	return true
end

local function section(t) io.write("\n== " .. t .. " ==\n") end
local function phase(name, fn)
	local before = #H.errorOrder
	H.pcall(name, fn)
	io.write(("  %-42s %d new error(s)\n"):format(name, #H.errorOrder - before))
end

-- Mock unit update events for every unit we know
local units = {"player", "target", "pet", "party1", "party2", "focus", "targettarget"}
local unitEvents = {"UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_UPDATE", "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER", "UNIT_AURA",
	"UNIT_HEAL_PREDICTION", "UNIT_ABSORB_AMOUNT_CHANGED", "UNIT_HEAL_ABSORB_AMOUNT_CHANGED", "UNIT_NAME_UPDATE", "UNIT_LEVEL", "UNIT_FACTION",
	"UNIT_THREAT_SITUATION_UPDATE", "UNIT_PORTRAIT_UPDATE", "UNIT_MODEL_CHANGED", "UNIT_CONNECTION", "UNIT_FLAGS", "UNIT_TARGET", "UNIT_PET",
	"UNIT_CLASSIFICATION_CHANGED", "UNIT_PHASE", "UNIT_THREAT_LIST_UPDATE"}
local function pumpUnits()
	for _, u in ipairs(units) do
		for _, e in ipairs(unitEvents) do
			if e == "UNIT_POWER_UPDATE" or e == "UNIT_POWER_FREQUENT" then H.fireEvent(e, u, "MANA") H.fireEvent(e, u, "COMBO_POINTS")
			elseif e == "UNIT_AURA" then H.fireEvent(e, u, {isFullUpdate = true}) H.fireEvent(e, u, {addedAuras = {}, updatedAuraInstanceIDs = {1}, removedAuraInstanceIDs = {99}})
			else H.fireEvent(e, u) end
		end
	end
	H.fireEvent("PLAYER_TARGET_CHANGED")
	H.fireEvent("PLAYER_FOCUS_CHANGED")
	H.fireEvent("GROUP_ROSTER_UPDATE")
	H.fireEvent("RAID_TARGET_UPDATE")
	H.fireEvent("PARTY_LEADER_CHANGED")
	H.fireEvent("UPDATE_SHAPESHIFT_FORM")
	H.fireEvent("PLAYER_TOTEM_UPDATE", 1)
	H.fireEvent("COMBO_TARGET_CHANGED")
	H.fireEvent("PLAYER_XP_UPDATE", "player")
	H.fireEvent("UPDATE_EXHAUSTION")
	H.tick(0.1, 12)
end

local function castCycle()
	local cast = {"Healing Touch", "Healing Touch", 136243, H.time * 1000, H.time * 1000 + 2500, false, "Cast-1", false, 5185, 1, 0}
	_G.UnitCastingInfo = H.guard("UnitCastingInfo", function(u)
		if u ~= "player" and u ~= "target" then return nil end
		if H.secretMode then local c = {} for i = 1, 11 do c[i] = H.secret(cast[i]) end return unpack(c, 1, 11) end
		return unpack(cast, 1, 11)
	end)
	local guid, spell = "Cast-1", 5185
	if H.secretMode then guid, spell = H.secret(guid), H.secret(spell) end
	for _, u in ipairs({"player", "target"}) do
		H.fireEvent("UNIT_SPELLCAST_START", u, guid, spell)
		H.tick(0.1, 5)
		H.fireEvent("UNIT_SPELLCAST_DELAYED", u, guid, spell)
		H.fireEvent("UNIT_SPELLCAST_FAILED", u, "Cast-2", spell)
		H.tick(0.1, 5)
		_G.UnitCastingInfo = H.guard("UnitCastingInfo", function() return nil end)
		H.fireEvent("UNIT_SPELLCAST_SUCCEEDED", u, guid, spell)
		H.fireEvent("UNIT_SPELLCAST_STOP", u, guid, spell)
		H.fireEvent("UNIT_SPELLCAST_CHANNEL_START", u, guid, spell)
		H.fireEvent("UNIT_SPELLCAST_CHANNEL_STOP", u, guid, spell)
		H.fireEvent("UNIT_SPELLCAST_INTERRUPTED", u, guid, spell)
		H.tick(0.1, 10)
	end
end

section("Loading")
phase("load ShadowedUnitFrames_Forever", function() H.loadAddon("ShadowedUnitFrames_Forever") end)
phase("PLAYER_LOGIN", function() H.fireEvent("PLAYER_LOGIN") end)
phase("PLAYER_ENTERING_WORLD", function() H.fireEvent("PLAYER_ENTERING_WORLD", true, false) H.tick(0.1, 5) end)
phase("SPELLS_CHANGED", function() H.fireEvent("SPELLS_CHANGED") end)

-- Spawn group header children like the secure header would
local function spawnHeaders()
	for _, f in ipairs(H.allFrames) do
		local tmpl = f.__template
		if tmpl and tmpl:find("SecureGroup") and f.__attrs.template and not f.__spawned and f.__shown then
			f.__spawned = true
			local unitType = f.unitType or ""
			local count = unitType == "party" and 2 or unitType == "raid" and 3 or unitType:find("pet") and 1 or (unitType == "maintank" or unitType == "mainassist") and 1 or 0
			for i = 1, count do
				local childName = (f:GetName() or "SUFHeader") .. "UnitButton" .. i
				local child = CreateFrame("Button", childName, f, f.__attrs.template)
				f.__attrs["child" .. i] = child
				if f.initialConfigFunction then H.pcall("initialConfigFunction", f.initialConfigFunction, f, childName) end
				local unit = unitType == "party" and ("party" .. i) or unitType == "raid" and ("raid" .. i) or unitType == "partypet" and "partypet1" or ("raid" .. i)
				child:SetAttribute("unit", unit)
				child:Show()
			end
		end
	end
end

section("Out of combat")
phase("spawn group headers", spawnHeaders)
phase("unit events (plain values)", pumpUnits)
phase("casts (plain values)", castCycle)

section("In combat, secret values")
phase("enter combat", function() H.inCombat = true H.secretMode = true H.fireEvent("PLAYER_REGEN_DISABLED") end)
phase("unit events (secret values)", pumpUnits)
phase("casts (secret values)", castCycle)
phase("leave combat", function() H.inCombat = false H.secretMode = false H.fireEvent("PLAYER_REGEN_ENABLED") H.tick(0.1, 5) end)

section("Options")
phase("load options addon", function() H.loadAddon("ShadowedUF_Forever_Options") end)
phase("/suf", function()
	local dlg = LibStub("AceConfigDialog-3.0", true)
	if dlg then dlg.Open = function() end dlg.AddToBlizOptions = function() return CreateFrame("Frame") end end
	for k, fn in pairs(SlashCmdList) do
		if k:find("SHADOW") or k:find("SUF") then fn("") break end
	end
end)
phase("build every options page", function()
	local reg = LibStub("AceConfigRegistry-3.0", true)
	if not reg then error("AceConfigRegistry not loaded") end
	for appName in pairs(reg.tables) do
		local okGet, opts = pcall(reg.GetOptionsTable, reg, appName, "dialog", "SUF-test-1.0")
		if not okGet then error(opts) end
		-- walk the whole tree, calling every function-valued field the dialog would
		local seen = {}
		local function walk(o, path, handler)
			if type(o) ~= "table" or seen[o] then return end
			seen[o] = true
			handler = o.handler or handler
			local function mkinfo()
				local inf = {options = opts, option = o, type = o.type, handler = handler, arg = o.arg, uiType = "dialog", uiName = "SUF-test-1.0"}
				for i, p in ipairs(path) do inf[i] = p end
				return inf
			end
			if type(o.hidden) == "function" then
				local ok, h = pcall(o.hidden, mkinfo())
				if ok and h then return end
			elseif o.hidden == true then return end
			for _, field in ipairs({"name", "desc", "hidden", "disabled", "values", "get", "min", "max"}) do
				local v = o[field]
				if type(v) == "function" then
					local inf = mkinfo()
					if field == "get" and o.type == "group" then -- groups only pass get down
					else
						local ok, val = H.pcall("options " .. table.concat(path, "."), v, inf)
						if field == "get" and ok and (o.type == "toggle" or o.type == "range") and type(o.set) == "function" then
							H.pcall("options set " .. table.concat(path, "."), o.set, mkinfo(), val)
						end
					end
				end
			end
			if type(o.args) == "table" then
				for k, child in pairs(o.args) do
					local p = {unpack(path)}
					table.insert(p, k)
					walk(child, p, handler)
				end
			end
			if type(o.plugins) == "table" then
				for _, plug in pairs(o.plugins) do
					for k, child in pairs(plug) do local p = {unpack(path)} table.insert(p, k) walk(child, p, handler) end
				end
			end
		end
		walk(opts, {})
	end
end)

section("Sanity")
local count, sample = 0, {}
for _, f in ipairs(H.allFrames) do
	if f.unitType and f.healthBar then
		count = count + 1
		if #sample < 6 then
			local t = {}
			for _, r in ipairs(f.__regions) do end
			table.insert(sample, (f.unitType or "?") .. " unit=" .. tostring(f.unit) .. " hp=" .. tostring(H.unwrap(f.healthBar.__value)) .. "/" .. tostring(H.unwrap(f.healthBar.__max)))
		end
	end
end
io.write(count, " unit frames with health bars\n")
for _, l in ipairs(sample) do io.write("  ", l, "\n") end
section("Results")
io.write(("%d distinct error(s)\n"):format(#H.errorOrder))
for i, key in ipairs(H.errorOrder) do
	local e = H.errors[key]
	io.write(("\n[%d] x%d (%s)\n%s\n"):format(i, e.count, e.context or "?", e.err))
	if os.getenv("TB") then io.write(e.tb, "\n") else
		local n = 0
		for line in e.tb:gmatch("[^\n]+") do
			if line:find("ShadowedU") and not line:find("harness") then
				io.write("    ", line:gsub("^%s+", ""), "\n")
				n = n + 1
				if n >= 4 then break end
			end
		end
	end
end
if os.getenv("STUBS") then
	io.write("\nUnmocked API calls:\n")
	for k, v in pairs(H.stubCalls) do io.write("  ", k, " x", v, "\n") end
end
for _, n in ipairs(H.notes) do if os.getenv("NOTES") then io.write(n, "\n") end end
