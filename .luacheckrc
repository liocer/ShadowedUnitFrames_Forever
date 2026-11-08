-- luacheck config for WoW Forever. tools/forever_globals.lua lists every global the
-- Forever client's own UI defines or documents (generated from Gethe/wow-ui-source,
-- branch "forever"), so an "undefined variable" usually means the API doesn't exist here.
-- Note: the API docs aren't complete; a few old C functions (e.g. GetReadyCheckStatus)
-- exist without being listed. Check Blizzard's code before removing a call.
std = "lua51"
max_line_length = false
exclude_files = { "libs/", "options/libs/", "locale-import.lua", ".luacheckrc", "tools/" }
ignore = { "11./BINDING_.*", "11./SLASH_.*", "211", "212", "213", "231/_.*", "431", "432", "311", "512", "542", "122" }
globals = { "ShadowUF", "ClickCastFrames", "CONFIGMODE_CALLBACKS", "SlashCmdList", "ShadowedUFDB" }
read_globals = dofile("tools/forever_globals.lua")
for _, n in ipairs({ "Enum", "LibStub", "ClickCastHeader", "BigWigsAPI", "Clique", "unpack", "select" }) do
	table.insert(read_globals, n)
end
