-- Two mixed armies meet head-on in the middle of the map: stresses weapons,
-- projectiles, particles, explosions, decals and target acquisition together.
local PER_TEAM = 600
local ARMY = {
	[0] = { "armpw", "armrock", "armham", "armstump", "armsam", "armart" },
	[1] = { "corak", "corstorm", "corthud", "corraid", "cormist", "corwolv" },
}
local FIGHT_SECONDS = 45

local preexisting = {}

return {
	name = "big_battle",
	timeout = 600,
	synced = {
		snapshot = function()
			for _, u in ipairs(Spring.GetAllUnits()) do preexisting[u] = true end
			return 0
		end,
		-- spawns one army block facing the centre; side 0 west, side 1 east
		spawnArmy = function(teamID, side, count)
			local names = ARMY[side]
			local cols = 30
			local spacing = 44
			local cx, cz = Game.mapSizeX * 0.5, Game.mapSizeZ * 0.5
			local x0 = side == 0 and (cx - 900 - cols * spacing) or (cx + 900)
			local z0 = cz - (count / cols) * spacing * 0.5
			for i = 0, count - 1 do
				local x = x0 + (i % cols) * spacing
				local z = z0 + math.floor(i / cols) * spacing
				Spring.CreateUnit(names[(i % #names) + 1], x, Spring.GetGroundHeight(x, z), z, side == 0 and 1 or 3, teamID)
			end
			return count
		end,
		charge = function()
			local cx, cz = Game.mapSizeX * 0.5, Game.mapSizeZ * 0.5
			for _, u in ipairs(Spring.GetAllUnits()) do
				if not preexisting[u] then
					Spring.GiveOrderToUnit(u, CMD.FIGHT, { cx, Spring.GetGroundHeight(cx, cz), cz }, 0)
				end
			end
			return 0
		end,
		-- units created by the scenario still alive
		alive = function()
			local n = 0
			for _, u in ipairs(Spring.GetAllUnits()) do
				if not preexisting[u] then n = n + 1 end
			end
			return n
		end,
		clear = function()
			for _, u in ipairs(Spring.GetAllUnits()) do
				if not preexisting[u] then Spring.DestroyUnit(u, false, true) end
			end
			return 0
		end,
	},
	run = function(ctx)
		local me = Spring.GetMyTeamID()
		local enemy
		for _, t in ipairs(Spring.GetTeamList()) do
			if not Spring.AreTeamsAllied(t, me) and t ~= Spring.GetGaiaTeamID() then enemy = t break end
		end
		if not enemy then
			ctx.check("enemy_team", false, "start script needs a non-allied team")
			return
		end
		ctx.call("snapshot")
		ctx.call("spawnArmy", me, 0, PER_TEAM)
		ctx.call("spawnArmy", enemy, 1, PER_TEAM)
		local spawned = ctx.call("alive") or 0
		ctx.check("spawned", spawned == PER_TEAM * 2, spawned .. "/" .. PER_TEAM * 2)

		ctx.waitSimFrames(30)
		ctx.call("charge")
		ctx.window("battle", function() ctx.waitSimFrames(Game.gameSpeed * FIGHT_SECONDS) end)

		local survivors = ctx.call("alive") or spawned
		ctx.check("armies_engaged", survivors < spawned, string.format("%d of %d units survived %d s of fighting", survivors, spawned, FIGHT_SECONDS))
		ctx.call("clear")
	end,
}
