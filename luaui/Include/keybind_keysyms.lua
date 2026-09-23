-- Serves the engine key constants to the keybind editor includes.
--
-- barwidgets.lua loads KEYSYMS into the widget-handler environment, which an Include from
-- inside a widget does not inherit, so the global may or may not be visible here.

local KEYSYMS = KEYSYMS

if not KEYSYMS then
	-- the header may be served by the engine (raw VFS mode wins over the game archive), whose
	-- version builds KEYSYMS with setmetatable; give it read access to globals
	local env = setmetatable({}, { __index = _G })
	VFS.Include("luaui/Headers/keysym.h.lua", env)
	KEYSYMS = env.KEYSYMS
end

return KEYSYMS
