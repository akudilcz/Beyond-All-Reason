-- Builds a mass-movement scenario: `count` ground units of one type cross the map.
-- Measures sim/pathing cost at scale. Used by workbench/scenarios/mass_move_*.lua.
return function(count, unitName)
	unitName = unitName or "armpw"
	local simSeconds = 60
	local preexisting = {} -- synced side: units that existed before the scenario

	return {
		name = "mass_move_" .. count,
		timeout = 240 + count / 20,
		synced = {
			snapshot = function()
				for _, u in ipairs(Spring.GetAllUnits()) do preexisting[u] = true end
				return 0
			end,
			-- remove everything the scenario created so later scenarios start clean
			clear = function()
				for _, u in ipairs(Spring.GetAllUnits()) do
					if not preexisting[u] then Spring.DestroyUnit(u, false, true) end
				end
				return 0
			end,
			spawn = function(teamID, n)
				local def = UnitDefNames[unitName]
				local side = math.ceil(math.sqrt(n))
				local spacing = 48
				local x0, z0 = Game.mapSizeX * 0.1, Game.mapSizeZ * 0.1
				for i = 0, n - 1 do
					local x = x0 + (i % side) * spacing
					local z = z0 + math.floor(i / side) * spacing
					Spring.CreateUnit(def.id, x, Spring.GetGroundHeight(x, z), z, 0, teamID)
				end
				return n
			end,
			moveAll = function(teamID)
				local tx, tz = Game.mapSizeX * 0.85, Game.mapSizeZ * 0.85
				for _, u in ipairs(Spring.GetTeamUnits(teamID)) do
					Spring.GiveOrderToUnit(u, CMD.MOVE, { tx, Spring.GetGroundHeight(tx, tz), tz }, 0)
				end
				return 0
			end,
		},
		run = function(ctx)
			local team = Spring.GetMyTeamID()
			local before = #Spring.GetTeamUnits(team)
			ctx.call("snapshot")
			ctx.call("spawn", team, count)
			local spawned = ctx.waitUntil(function() return #Spring.GetTeamUnits(team) >= before + count end, 60)
			ctx.check("spawned", spawned, (#Spring.GetTeamUnits(team) - before) .. "/" .. count)
			if not spawned then
				ctx.call("clear")
				return
			end
			ctx.waitSimFrames(30) -- settle before measuring
			ctx.call("moveAll", team)
			ctx.window("moving", function() ctx.waitSimFrames(Game.gameSpeed * simSeconds) end)
			local tx, tz = Game.mapSizeX * 0.85, Game.mapSizeZ * 0.85
			local progressed = 0
			for _, u in ipairs(Spring.GetTeamUnits(team)) do
				local x, _, z = Spring.GetUnitPosition(u)
				if x and x > Game.mapSizeX * 0.3 then
					progressed = progressed + 1
				end
			end
			ctx.check("progress", progressed > 0, progressed .. " units past 30% of the map after " .. simSeconds .. " s")
			ctx.call("clear")
		end,
	}
end
