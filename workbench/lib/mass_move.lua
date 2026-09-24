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
				-- a few grid spots are blocked (cliffs, water, features) and CreateUnit refuses
				-- them: move on to the next spot so the count is still n (same spots each run)
				local made, i = 0, 0
				while made < n and i < n * 2 do
					local x = x0 + (i % side) * spacing
					local z = z0 + math.floor(i / side) * spacing
					if Spring.CreateUnit(def.id, x, Spring.GetGroundHeight(x, z), z, 0, teamID) then
						made = made + 1
					end
					i = i + 1
				end
				return made
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
			local old = {} -- the team's units from before, not counted as progress
			for _, u in ipairs(Spring.GetTeamUnits(team)) do old[u] = true end
			ctx.call("snapshot")
			-- the spawn's own count: the team's total also moves with units left over from
			-- earlier scenarios (dying or being cleared meanwhile)
			local have = tonumber(ctx.call("spawn", team, count)) or 0
			local spawned = have >= count
			-- a short spawn is reported but still measured (with what spawned): skipping the
			-- window would silently drop the run from every timing comparison
			ctx.check("spawned", spawned, have .. "/" .. count)
			if have <= 0 then
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
				if x and x > Game.mapSizeX * 0.3 and not old[u] then
					progressed = progressed + 1
				end
			end
			ctx.check("progress", progressed > 0, progressed .. " units past 30% of the map after " .. simSeconds .. " s")
			ctx.call("clear")
		end,
	}
end
