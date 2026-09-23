-- Synced helpers that turn the loaded map into a neutral test arena, so per-unit checks
-- measure the unit and not the map: terrain is levelled (no ridge blocking a shot),
-- features are removed (no tree absorbing it), and units that existed before the
-- scenario (start commanders) hold fire and position so they cannot interfere.
-- Global LOS is switched off, so visibility checks start from the real LOS rules.
-- Usage in a scenario's synced table:
--   local arena = VFS.Include("workbench/lib/arena.lua")
--   synced = { prepare = arena.prepare, clear = arena.clear, ... }
local ARENA_HEIGHT = 200 -- above the water line

local preexisting = {}
local M = {}

function M.prepare()
	for _, u in ipairs(Spring.GetAllUnits()) do
		preexisting[u] = true
		Spring.GiveOrderToUnit(u, CMD.FIRE_STATE, { 0 }, 0) -- hold fire
		Spring.GiveOrderToUnit(u, CMD.MOVE_STATE, { 0 }, 0) -- hold position
		Spring.GiveOrderToUnit(u, CMD.STOP, {}, 0)
	end
	for _, f in ipairs(Spring.GetAllFeatures()) do
		Spring.DestroyFeature(f)
	end
	Spring.LevelHeightMap(0, 0, Game.mapSizeX, Game.mapSizeZ, ARENA_HEIGHT)
	for _, a in ipairs(Spring.GetAllyTeamList()) do
		Spring.SetGlobalLos(a, false) -- an earlier scenario may have turned it on
	end
	return 0
end

-- removes everything created since prepare()
function M.clear()
	for _, u in ipairs(Spring.GetAllUnits()) do
		if not preexisting[u] then Spring.DestroyUnit(u, false, true) end
	end
	for _, f in ipairs(Spring.GetAllFeatures()) do
		Spring.DestroyFeature(f) -- wrecks of destroyed test units
	end
	return 0
end

function M.isPreexisting(u)
	return preexisting[u] == true
end

return M
