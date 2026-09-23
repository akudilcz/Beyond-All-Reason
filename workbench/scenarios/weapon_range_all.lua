-- Weapon range checks for every armed ground unit of the playable factions,
-- generated from UnitDefs/WeaponDefs. Each unit gets two independent cases, each
-- in its own lane: a stationary enemy structure just inside the unit's effective
-- range must take damage, one just outside (plus the target's radius, since range
-- is measured to its edge) must not.
--
-- "Effective range" only counts weapons that can hurt that structure on their own:
-- the weapon's target categories must include the target, and paralyzer (EMP),
-- manual-fire (D-gun style), stockpile and torpedo weapons are ignored. Units with
-- no such weapon are skipped (logged, not failed).
local TARGET = "armsolar"
local MARGIN = 0.1
local WAIT_SECONDS = 12
local SPACING_FACTOR = 2.5

local function effectiveRange(def, targetCats)
	local best = 0
	for _, w in ipairs(def.weapons or {}) do
		local wd = WeaponDefs[w.weaponDef]
		if wd and not wd.paralyzer and not wd.manualFire and not wd.stockpile and wd.type ~= "TorpedoLauncher" then
			local targetable = true
			if w.onlyTargets and next(w.onlyTargets) then
				targetable = false
				for cat in pairs(w.onlyTargets) do
					if targetCats[cat] then targetable = true break end
				end
			end
			if targetable then
				best = math.max(best, wd.range or 0)
			end
		end
	end
	return best
end

local function isGroundUnit(def)
	local name = def.name
	if not (name:find("^arm") or name:find("^cor") or name:find("^leg")) then return false end
	if name:find("_scav") or def.isBuilding or def.canFly or not def.canMove then return false end
	local md = def.moveDef
	if not md or not md.name or md.name:find("boat") or md.name:find("uboat") or (def.minWaterDepth or 0) > 0 then
		return false
	end
	return true
end

local preexisting = {}

return {
	name = "weapon_range_all",
	timeout = 7200,
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
			local x = Game.mapSizeX * 0.15
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
		local tdef = UnitDefNames[TARGET]
		local maxHp, targetRadius, targetCats = tdef.health, tdef.radius or 0, tdef.modCategories or {}

		-- one entry per (unit, case); long ranges are fine because each case has its own lane
		local cases, skipped = {}, 0
		for _, def in pairs(UnitDefs) do
			if isGroundUnit(def) and def.weapons and #def.weapons > 0 then
				local range = effectiveRange(def, targetCats)
				if range <= 0 then
					skipped = skipped + 1
				elseif Game.mapSizeX * 0.15 + range * (1 + MARGIN) + targetRadius > Game.mapSizeX * 0.95 then
					ctx.log("skipped " .. def.name .. ": range " .. range .. " longer than the map allows")
					skipped = skipped + 1
				else
					cases[#cases + 1] = { def = def, range = range, name = "inside", dist = range * (1 - MARGIN), expect = true }
					cases[#cases + 1] = { def = def, range = range, name = "outside", dist = range * (1 + MARGIN) + targetRadius, expect = false }
				end
			end
		end
		table.sort(cases, function(a, b) return a.range < b.range end)
		ctx.log(#cases .. " cases; " .. skipped .. " armed ground units have no weapon that can hurt a " .. TARGET)
		ctx.call("snapshot")

		local mapZ = Game.mapSizeZ
		local i = 1
		while i <= #cases do
			-- lanes spaced by the batch's longest range; a single lane always fits (centred)
			local batch, spacing = {}, 0
			while i <= #cases do
				local s = cases[i].range * SPACING_FACTOR + targetRadius * 2
				if #batch > 0 and (#batch + 1) * math.max(spacing, s) > mapZ * 0.9 then break end
				spacing = math.max(spacing, s)
				batch[#batch + 1] = cases[i]
				i = i + 1
			end

			ctx.call("clear")
			ctx.waitSimFrames(2)
			local placed = {}
			for lane, c in ipairs(batch) do
				local z = (#batch == 1) and mapZ * 0.5 or (mapZ * 0.05 + (lane - 0.5) * spacing)
				local target, err = ctx.call("place", c.def.name, me, enemy, z, c.dist)
				if type(target) ~= "number" then
					ctx.check(c.name .. ":" .. c.def.name, false, tostring(err or target))
				else
					c.target = target
					placed[#placed + 1] = c
				end
			end

			ctx.waitSeconds(WAIT_SECONDS)
			for _, c in ipairs(placed) do
				local hp, err = ctx.call("health", c.target)
				if not hp then
					ctx.check(c.name .. ":" .. c.def.name, false, err)
				else
					local damaged = hp < maxHp
					ctx.check(c.name .. ":" .. c.def.name, damaged == c.expect,
						string.format("effective range %.0f distance %.0f expected %s, target hp %.0f/%.0f",
							c.range, c.dist, c.expect and "damage" or "no damage", hp, maxHp))
				end
			end
		end
		ctx.call("clear")
	end,
}
