local ShadowUF = select(2, ...)
local L = {}
--@localization(locale="enUS", format="lua_additive_table")@

-- SUF Forever: the strings are keyed by their English text, so a missing entry just shows the key.
-- This used to be debug-only; it's always on now since this fork isn't tied to the original's
-- CurseForge localization project.
ShadowUF.L = setmetatable(L, {
	__index = function(tbl, value)
		rawset(tbl, value, value)
		return value
	end,
})
