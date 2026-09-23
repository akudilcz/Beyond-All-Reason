-- Weapon range checks for every armed ground unit of the playable factions,
-- generated from UnitDefs. Each unit is tested in two lanes at once: a stationary
-- enemy structure just inside maxWeaponRange must take damage, one just outside
-- (plus the target's radius, since range is measured to its edge) must not.
-- Units are batched by similar range and lanes are spaced 2.5x the batch's longest
-- range apart, so no attacker can reach another lane's target.
local TARGET = "armsolar"
local MARGIN = 0.1
local WAIT_SECONDS = 12
local SPACING_FACTOR = 2.5

local function isCandidate(def)
	local name = def.name
	if not (name:find("^arm") or name:find("^cor") or name:find("^leg")) then
		return false
	end
	if name:find("_scav") or def.isBuilding or def.canFly or not def.canMove then
		return false
	end
	if (def.maxWeaponRange or 0) <= 0 or not def.weapons or #def.weapons == 0 then
		return false
	end
	local md = def.moveDef
	if not md or not md.name or md.name:find("boat") or md.name:find("uboat") or (def.minWaterDepth or 0) > 0 then
		return false
	end
	return true
end

local preexisting = {}

return {
	name = "weapon_range_all",
	timeout = 5400,
	synced = {
		snapshot = function()
			for _, u in ipairs(Spring.GetAllUnits()) do preexisting[u] = true end
			return 0
		end,
		clear = function()
			for _, u in ipairs(Spring.GetAllUnits()) do
				if not preexisting[u] then Spring.DestroyUnit(u, false, true) end
			end
			return 0
		end,
		-- one attacker + one target at `distance`; returns the target id or a message
		place = function(attackerName, attackerTeam, targetTeam, laneZ, distance)
			local x = Game.mapSizeX * 0.25
			local a = Spring.CreateUnit(attackerName, x, Spring.GetGroundHeight(x, laneZ), laneZ, 1, attackerTeam)
			local tx = x + distance
			local t = Spring.CreateUnit(TARGET, tx, Spring.GetGroundHeight(tx, laneZ), laneZ, 3, targetTeam)
			if not a or not t then
				return "could not create " .. (a and TARGET or attackerName)
			end
			Spring.MoveCtrl.Enable(a)
			Spring.GiveOrderToUnit(a, CMD.FIRE_STATE, { 2 }, 0)
			Spring.SetGlobalLos(Spring.GetUnitAllyTeam(a), true)
			return t
		end,
		health = function(unitID)
			return Spring.ValidUnitID(unitID) and (Spring.GetUnitHealth(unitID)) or 0
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
		local maxHp = UnitDefNames[TARGET].health
		local targetRadius = UnitDefNames[TARGET].radius or 0

		local defs = {}
		for _, def in pairs(UnitDefs) do
			if isCandidate(def) then defs[#defs + 1] = def end
		end
		table.sort(defs, function(a, b) return a.maxWeaponRange < b.maxWeaponRange end)
		ctx.log(#defs .. " armed ground unit types")
		ctx.call("snapshot")

		local mapZ = Game.mapSizeZ
		local i = 1
		while i <= #defs do
			-- fill a batch while lanes (two per unit) still fit on the map at this batch's spacing
			local batch, spacing = {}, 0
			while i <= #defs do
				local s = defs[i].maxWeaponRange * SPACING_FACTOR + targetRadius * 2
				local lanes = (#batch + 1) * 2
				if #batch > 0 and lanes * math.max(spacing, s) > mapZ * 0.9 then break end
				spacing = math.max(spacing, s)
				batch[#batch + 1] = defs[i]
				i = i + 1
			end

			-- a single unit whose two lanes don't fit: the lanes would be closer than its range
			-- and the inside/outside cases would contaminate each other, so skip it
			if #batch == 1 and 2 * spacing > mapZ * 0.9 then
				ctx.log("skipped " .. batch[1].name .. ": range " .. batch[1].maxWeaponRange .. " too long for this map's lanes")
				batch = {}
			end

			ctx.call("clear")
			ctx.waitSimFrames(2)
			local cases = {}
			for k, def in ipairs(batch) do
				local range = def.maxWeaponRange
				for c, case in ipairs({ { "inside", range * (1 - MARGIN), true }, { "outside", range * (1 + MARGIN) + targetRadius, false } }) do
					local lane = (k - 1) * 2 + c
					local z = mapZ * 0.05 + (lane - 0.5) * spacing
					local target, err = ctx.call("place", def.name, me, enemy, z, case[2])
					if type(target) ~= "number" then
						ctx.check(case[1] .. ":" .. def.name, false, tostring(err or target))
					else
						cases[#cases + 1] = { def = def, case = case, target = target }
					end
				end
			end

			ctx.waitSeconds(WAIT_SECONDS)
			for _, c in ipairs(cases) do
				local hp, err = ctx.call("health", c.target)
				if not hp then
					ctx.check(c.case[1] .. ":" .. c.def.name, false, err)
				else
					local damaged = hp < maxHp
					ctx.check(c.case[1] .. ":" .. c.def.name, damaged == c.case[3],
						string.format("range %.0f distance %.0f expected %s, target hp %.0f/%.0f",
							c.def.maxWeaponRange, c.case[2], c.case[3] and "damage" or "no damage", hp, maxHp))
				end
			end
		end
		ctx.call("clear")
	end,
}
