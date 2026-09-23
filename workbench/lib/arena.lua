-- Synced helpers that turn the loaded map into a neutral test arena, so per-unit checks
-- measure the unit and not the map: terrain is levelled (no ridge blocking a shot),
-- features are removed (no tree absorbing it), and units that existed before the
-- scenario (start commanders) hold fire and position, parked in a corner west of every
-- test lane so they never stand in a line of fire (weapons refuse to shoot through a
-- friendly unit).
-- Global LOS is switched off, so visibility checks start from the real LOS rules.
-- Usage in a scenario's synced table:
--   local arena = VFS.Include("workbench/lib/arena.lua")
--   synced = { prepare = arena.prepare, clear = arena.clear, ... }
local ARENA_HEIGHT = 200 -- above the water line

local preexisting = {}
local arenaHeight = ARENA_HEIGHT
local M = {}

-- height: ground level for the whole map (default above water; negative floods it)
function M.prepare(height)
	local parked = 0
	for _, u in ipairs(Spring.GetAllUnits()) do
		preexisting[u] = true
		Spring.GiveOrderToUnit(u, CMD.FIRE_STATE, { 0 }, 0) -- hold fire
		Spring.GiveOrderToUnit(u, CMD.MOVE_STATE, { 0 }, 0) -- hold position
		Spring.GiveOrderToUnit(u, CMD.STOP, {}, 0)
		parked = parked + 1
		Spring.SetUnitPosition(u, Game.mapSizeX * 0.03 + (parked % 4) * 60, Game.mapSizeZ * 0.03 + math.floor(parked / 4) * 60)
	end
	for _, f in ipairs(Spring.GetAllFeatures()) do
		Spring.DestroyFeature(f)
	end
	arenaHeight = tonumber(height) or ARENA_HEIGHT
	Spring.LevelHeightMap(0, 0, Game.mapSizeX, Game.mapSizeZ, arenaHeight)
	for _, a in ipairs(Spring.GetAllyTeamList()) do
		Spring.SetGlobalLos(a, false) -- an earlier scenario may have turned it on
	end
	return 0
end

-- removes everything created since prepare(), including projectiles still in flight
-- (a slow shell from the last batch must not land on the next batch's target)
-- Returns "units,features,projectiles" removed. Death handlers can spawn things a few
-- frames later (e.g. commander wrecks), so scenarios sweep again after a pause: see
-- M.sweepAgain.
function M.clear()
	local p, u, f = 0, 0, 0
	for _, id in ipairs(Spring.GetProjectilesInRectangle(0, 0, Game.mapSizeX, Game.mapSizeZ) or {}) do
		Spring.DeleteProjectile(id)
		p = p + 1
	end
	for _, id in ipairs(Spring.GetAllUnits()) do
		if not preexisting[id] then
			Spring.DestroyUnit(id, false, true)
			u = u + 1
		end
	end
	for _, id in ipairs(Spring.GetAllFeatures()) do
		Spring.DestroyFeature(id) -- wrecks of destroyed test units
		f = f + 1
	end
	-- explosions crater the ground; over many batches in the same lanes the craters and
	-- mounds block flat-trajectory weapons, so every batch starts on level ground again
	Spring.LevelHeightMap(0, 0, Game.mapSizeX, Game.mapSizeZ, arenaHeight)
	return string.format("%d,%d,%d", u, f, p)
end

-- unsynced helper: clear, let delayed death effects happen, clear again; logs anything
-- the second sweep had to remove (it would otherwise stand in the next batch's lanes)
function M.sweep(ctx)
	ctx.call("clear")
	ctx.waitSimFrames(45)
	local late = ctx.call("clear")
	if late and late ~= "0,0,0" then
		ctx.log("second sweep removed units,features,projectiles " .. tostring(late))
	end
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
