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

-- height: ground level for the whole map (default above water; negative floods it)
function M.prepare(height)
	for _, u in ipairs(Spring.GetAllUnits()) do
		preexisting[u] = true
		Spring.GiveOrderToUnit(u, CMD.FIRE_STATE, { 0 }, 0) -- hold fire
		Spring.GiveOrderToUnit(u, CMD.MOVE_STATE, { 0 }, 0) -- hold position
		Spring.GiveOrderToUnit(u, CMD.STOP, {}, 0)
	end
	for _, f in ipairs(Spring.GetAllFeatures()) do
		Spring.DestroyFeature(f)
	end
	Spring.LevelHeightMap(0, 0, Game.mapSizeX, Game.mapSizeZ, tonumber(height) or ARENA_HEIGHT)
	for _, a in ipairs(Spring.GetAllyTeamList()) do
		Spring.SetGlobalLos(a, false) -- an earlier scenario may have turned it on
	end
	return 0
end

-- removes everything created since prepare(), including projectiles still in flight
-- (a slow shell from the last batch must not land on the next batch's target)
function M.clear()
	for _, p in ipairs(Spring.GetProjectilesInRectangle(0, 0, Game.mapSizeX, Game.mapSizeZ) or {}) do
		Spring.DeleteProjectile(p)
	end
	for _, u in ipairs(Spring.GetAllUnits()) do
		if not preexisting[u] then Spring.DestroyUnit(u, false, true) end
	end
	for _, f in ipairs(Spring.GetAllFeatures()) do
		Spring.DestroyFeature(f) -- wrecks of destroyed test units
	end
	return 0
end

-- fills a team's storage so energy- or metal-hungry weapons and builds never stall
function M.unlimitedResources(team)
	for _, r in ipairs({ "m", "e" }) do
		Spring.SetTeamResource(team, r .. "s", 1e7)
		Spring.SetTeamResource(team, r, 1e7)
	end
end

-- honours run.py --filter in generated scenarios (engines before ctx.wants run everything)
function M.wants(ctx, caseName)
	return not ctx.wants or ctx.wants(caseName)
end

function M.isPreexisting(u)
	return preexisting[u] == true
end

return M
