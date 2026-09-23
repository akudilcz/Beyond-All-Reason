-- Air strike checks, generated from UnitDefs: every armed aircraft of the playable
-- factions that can hurt a ground structure is ordered to attack an unkillable enemy
-- structure 1500 elmos away, in its own lane on a flat arena. It must damage that
-- target itself (attributed through the UnitDamaged callin) within a budget from its
-- speed. Fighters (air-only weapons) are skipped. Catches aircraft that never reach,
-- never release, or miss every pass.
local arena = VFS.Include("workbench/lib/arena.lua")
local weapons = VFS.Include("workbench/lib/weapons.lua")

local TARGET = "armsolar"
local DISTANCE = 1500
local LANE_SPACING = 450
local SLACK_SECONDS = 30
local TARGET_HP = 1e6

-- synced state: target -> { attacker, firstHitFrame, damage }
local lanes = {}

return {
	name = "air_attack",
	timeout = 3600,
	synced = {
		prepare = arena.prepare,
		clear = function()
			lanes = {}
			return arena.clear()
		end,
		place = function(attackerName, attackerTeam, targetTeam, laneZ)
			local x = Game.mapSizeX * 0.2
			local a = Spring.CreateUnit(attackerName, x, Spring.GetGroundHeight(x, laneZ), laneZ, 1, attackerTeam)
			local tx = x + DISTANCE
			local t = Spring.CreateUnit(TARGET, tx, Spring.GetGroundHeight(tx, laneZ), laneZ, 3, targetTeam)
			if not a or not t then
				return "could not create " .. (a and TARGET or attackerName)
			end
			Spring.SetUnitMaxHealth(t, TARGET_HP)
			Spring.SetUnitHealth(t, TARGET_HP)
			Spring.SetGlobalLos(Spring.GetUnitAllyTeam(a), true)
			Spring.GiveOrderToUnit(a, CMD.FIRE_STATE, { 2 }, 0)
			Spring.GiveOrderToUnit(a, CMD.ATTACK, { t }, 0)
			lanes[t] = { attacker = a, placedFrame = Spring.GetGameFrame(), damage = 0 }
			return t
		end,
		-- "ownDamage,secondsToFirstHit" (-1 when not hit yet)
		result = function(target)
			local lane = lanes[target]
			if not lane then return "0,-1" end
			local t = lane.firstHitFrame and (lane.firstHitFrame - lane.placedFrame) / Game.gameSpeed or -1
			return string.format("%.0f,%.1f", lane.damage, t)
		end,
	},
	syncedCallins = {
		UnitDamaged = function(unitID, _, _, damage, paralyzer, _, _, attackerID)
			local lane = lanes[unitID]
			if lane and not paralyzer and attackerID == lane.attacker and damage > 0 then
				lane.damage = lane.damage + damage
				lane.firstHitFrame = lane.firstHitFrame or Spring.GetGameFrame()
			end
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
		local targetCats = UnitDefNames[TARGET].modCategories or {}
		local defs, skipped = {}, 0
		for _, def in pairs(UnitDefs) do
			if weapons.playable(def) and def.canFly and def.weapons and #def.weapons > 0 then
				if weapons.canHurt(def, targetCats) and (def.speed or 0) > 0 then
					defs[#defs + 1] = def
				else
					skipped = skipped + 1
				end
			end
		end
		table.sort(defs, function(a, b) return a.name < b.name end)
		ctx.log(#defs .. " armed aircraft; " .. skipped .. " skipped (air-only weapons)")
		ctx.call("prepare")
		ctx.waitSimFrames(5)

		local perBatch = math.max(1, math.floor(Game.mapSizeZ * 0.8 / LANE_SPACING))
		for first = 1, #defs, perBatch do
			ctx.call("clear")
			ctx.waitSimFrames(2)
			local batch, slowest = {}, math.huge
			for lane = 1, math.min(perBatch, #defs - first + 1) do
				local def = defs[first + lane - 1]
				local z = Game.mapSizeZ * 0.1 + (lane - 0.5) * LANE_SPACING
				local target, err = ctx.call("place", def.name, me, enemy, z)
				if type(target) ~= "number" then
					ctx.check("strike:" .. def.name, false, tostring(err or target))
				else
					batch[#batch + 1] = { def = def, target = target }
					slowest = math.min(slowest, def.speed)
				end
			end
			local budget = DISTANCE / slowest * 2 + SLACK_SECONDS
			local deadline = Spring.GetGameFrame() + math.ceil(budget * Game.gameSpeed)
			-- poll once a sim second until every aircraft has hit or the budget is spent
			local results, lastPoll = {}, Spring.GetGameFrame()
			ctx.waitUntil(function()
				local frame = Spring.GetGameFrame()
				if frame >= deadline then return true end
				if frame < lastPoll + 30 then return false end
				lastPoll = frame
				local all = true
				for _, b in ipairs(batch) do
					if not results[b] then
						local r = ctx.call("result", b.target)
						if r and r:sub(1, 2) ~= "0," then results[b] = r else all = false end
					end
				end
				return all
			end, budget * 4 + 60)
			for _, b in ipairs(batch) do
				local r = results[b] or ctx.call("result", b.target) or "0,-1"
				local dmg, t = r:match("^(%d+),(-?[%d.]+)$")
				dmg = tonumber(dmg) or 0
				ctx.check("strike:" .. b.def.name, dmg > 0,
					dmg > 0 and string.format("first hit after %s s, %d damage (speed %.0f)", t, dmg, b.def.speed)
					or string.format("no hit on a target %d elmos away within %.0f s (speed %.0f)", DISTANCE, budget, b.def.speed))
			end
		end
		ctx.call("clear")
	end,
}
