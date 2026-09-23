-- 500 ground units of one type cross the map; measures sim/pathing cost.
local COUNT = 500
local UNIT = "armpw"

return {
	name = "mass_move_500",
	timeout = 240,
	synced = {
		spawn = function(teamID, count)
			local def = UnitDefNames[UNIT]
			local side = math.ceil(math.sqrt(count))
			local x0, z0 = Game.mapSizeX * 0.15, Game.mapSizeZ * 0.15
			for i = 0, count - 1 do
				local x = x0 + (i % side) * 48
				local z = z0 + math.floor(i / side) * 48
				Spring.CreateUnit(def.id, x, Spring.GetGroundHeight(x, z), z, 0, teamID)
			end
		end,
		moveAll = function(teamID)
			local tx, tz = Game.mapSizeX * 0.85, Game.mapSizeZ * 0.85
			for _, u in ipairs(Spring.GetTeamUnits(teamID)) do
				Spring.GiveOrderToUnit(u, CMD.MOVE, { tx, Spring.GetGroundHeight(tx, tz), tz }, 0)
			end
		end,
	},
	run = function(ctx)
		local team = Spring.GetMyTeamID()
		local before = #Spring.GetTeamUnits(team)
		ctx.synced("spawn", team, COUNT)
		local spawned = ctx.waitUntil(function() return #Spring.GetTeamUnits(team) >= before + COUNT end, 30)
		ctx.check("spawned", spawned, (#Spring.GetTeamUnits(team) - before) .. "/" .. COUNT)
		if not spawned then
			return
		end
		ctx.synced("moveAll", team)
		ctx.window("moving", function() ctx.waitSimFrames(30 * 60) end) -- 60 s of sim
		local tx, tz = Game.mapSizeX * 0.85, Game.mapSizeZ * 0.85
		local near = 0
		for _, u in ipairs(Spring.GetTeamUnits(team)) do
			local x, _, z = Spring.GetUnitPosition(u)
			if x and math.abs(x - tx) + math.abs(z - tz) < 1500 then
				near = near + 1
			end
		end
		ctx.check("progress", near > 0, near .. " units near target after 60 s")
	end,
}
