-- Serves the engine key constants to the keybind editor includes.
--
-- barwidgets.lua loads KEYSYMS into the widget-handler environment, which an Include from
-- inside a widget does not inherit, so the global may or may not be visible here.

local KEYSYMS = KEYSYMS

if not KEYSYMS then
	local env = {}
	-- VFS.ZIP: load the game's own header like barwidgets.lua does; in the default raw-first
	-- mode the engine's LuaUI/Headers/keysym.h.lua shadows it, and that one needs setmetatable
	VFS.Include("luaui/Headers/keysym.h.lua", env, VFS.ZIP)
	KEYSYMS = env.KEYSYMS
end

return KEYSYMS
