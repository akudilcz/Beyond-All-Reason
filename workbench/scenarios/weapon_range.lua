-- Per-unit weapon range check for a sample of ground units: a stationary enemy
-- target just inside maxWeaponRange must take damage; one just outside must not.
local SAMPLE = { "armpw", "armrock", "armham", "corak", "corthud", "corstorm" }
local TARGET = "armsolar"
local MARGIN = 0.1 -- fraction of range
local WAIT_SECONDS = 12

-- synced state: units that existed before the scenario (start commanders etc.)
-- are never touched, so clearing cannot end the game
local preexisting = {}

return {
	name = "weapon_range",
	timeout = 60 + #SAMPLE * 2 * (WAIT_SECONDS + 5),
	synced = {
		snapshot = function()
			for _, u in ipairs(Spring.GetAllUnits()) do
				preexisting[u] = true
			end
			return #Spring.GetAllUnits()
		end,
		clear = function()
			local n = 0
			for _, u in ipairs(Spring.GetAllUnits()) do
				if not preexisting[u] then
					Spring.DestroyUnit(u, false, true)
					n = n + 1
				end
			end
			return n
		end,
		-- returns the target unit id, or a message string when placement failed
		place = function(attackerName, attackerTeam, targetTeam, distance)
			local x, z = Game.mapSizeX * 0.5, Game.mapSizeZ * 0.5
			local a = Spring.CreateUnit(attackerName, x, Spring.GetGroundHeight(x, z), z, 0, attackerTeam)
			local tx = x + distance
			local t = Spring.CreateUnit(TARGET, tx, Spring.GetGroundHeight(tx, z), z, 0, targetTeam)
			if not a or not t then
				return "could not create " .. (a and TARGET or attackerName)
			end
			-- freeze the attacker so it cannot walk into range (an ATTACK order would
			-- close the distance and make every "outside" case fire), let it pick the
			-- target itself, and give its allyteam full LOS so units whose sight is
			-- shorter than their weapon range are still tested on range alone
			Spring.MoveCtrl.Enable(a)
			Spring.GiveOrderToUnit(a, CMD.FIRE_STATE, { 2 }, 0)
			Spring.SetGlobalLos(Spring.GetUnitAllyTeam(a), true)
			return t
		end,
		-- remaining health of a unit, 0 if it is dead
		health = function(unitID)
			return Spring.ValidUnitID(unitID) and (Spring.GetUnitHealth(unitID)) or 0
		end,
	},
	run = function(ctx)
		local me = Spring.GetMyTeamID()
		local enemy
		for _, t in ipairs(Spring.GetTeamList()) do
			if not Spring.AreTeamsAllied(t, me) and t ~= Spring.GetGaiaTeamID() then
				enemy = t
				break
			end
		end
		if not enemy then
			ctx.check("enemy_team", false, "start script needs a non-allied team")
			return
		end
		local maxHp = UnitDefNames[TARGET].health
		ctx.call("snapshot")

		for _, name in ipairs(SAMPLE) do
			local def = UnitDefNames[name]
			local range = def and def.maxWeaponRange or 0
			if range <= 0 then
				ctx.check("range:" .. name, false, "unit missing or unarmed")
			else
				for _, case in ipairs({ { "inside", range * (1 - MARGIN), true }, { "outside", range * (1 + MARGIN), false } }) do
					ctx.call("clear")
					local target, placeErr = ctx.call("place", name, me, enemy, case[2])
					if type(target) ~= "number" then
						ctx.check(case[1] .. ":" .. name, false, tostring(placeErr or target))
					else
						ctx.waitSeconds(WAIT_SECONDS)
						local hp, hpErr = ctx.call("health", target)
						if not hp then
							ctx.check(case[1] .. ":" .. name, false, hpErr)
							hp = maxHp
						end
						local damaged = hp < maxHp
						ctx.check(
							case[1] .. ":" .. name,
							damaged == case[3],
							string.format(
								"range %.0f distance %.0f expected %s, target hp %.0f/%.0f",
								range, case[2], case[3] and "damage" or "no damage", hp, maxHp
							)
						)
					end
				end
			end
		end
		ctx.call("clear")
	end,
}
