-- Weapon range scenario generator: checks for every armed ground unit of the playable
-- factions (or a sample of them), generated from UnitDefs/WeaponDefs, on a flat arena.
--   return VFS.Include("workbench/lib/weapon_range.lua")(name, sample, timeout)
-- sample: nil for every unit, or a list of unit names. Each unit gets two independent
-- cases, each in its own lane, against a stationary enemy structure that cannot die
-- (so every hit is observable and attributable):
--   inside:  at 90% of the "must hit" range the target must take damage
--   outside: at 110% of the "can reach" range plus the target's radius it must not
--
-- Only weapons that can hurt the target count: real damage (not BAR's zero-damage
-- `bogus` dummies such as the spies' crawl weapon), target categories that include
-- the target, not paralyzer (EMP) and not manual-fire (D-gun style, never auto-fires).
-- "Must hit" additionally ignores stockpile weapons (may have nothing in stock) and
-- water/torpedo weapons (sea lasers only aim when submerged). "Can reach" includes
-- stockpiles and adds half the weapon's area of effect (splash lands past the aim
-- point). Units with no weapon that must hit are skipped (logged, not failed).
--
-- Every failure says what happened: which weapon of which unit hit the target (from
-- the UnitDamaged callin) or, when nothing hit, which of the attacker's weapons fired.
local TARGET = "armsolar"
local MARGIN = 0.1
local WAIT_SECONDS = 12 -- plus RANGE_SECONDS per 1000 elmos, for slow long-range shells
local RANGE_SECONDS = 6
local SPACING_FACTOR = 2.5
local TARGET_HP = 1e6 -- unkillable within the test window

-- synced state: target -> { attacker, placedFrame, hits = { "unit/weapon" = damage } }
local lanes = {}

local weapons = VFS.Include("workbench/lib/weapons.lua")
local hurts = weapons.hurts

-- mustHit: range within which the unit must be able to damage the target
-- canReach: distance beyond which nothing it auto-fires may damage the target
local function ranges(def, targetCats)
	local mustHit, canReach = 0, 0
	for _, w in ipairs(def.weapons or {}) do
		local wd = WeaponDefs[w.weaponDef]
		if hurts(w, wd, targetCats) then
			canReach = math.max(canReach, (wd.range or 0) + (wd.damageAreaOfEffect or 0) * 0.5)
			if not wd.stockpile and not wd.waterWeapon then
				mustHit = math.max(mustHit, wd.range or 0)
			end
		end
	end
	return mustHit, canReach
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

local arena = VFS.Include("workbench/lib/arena.lua")

return function(scenarioName, sampleList, timeout)
local sample
if sampleList then
	sample = {}
	for _, n in ipairs(sampleList) do sample[n] = true end
end
return {
	name = scenarioName,
	timeout = timeout,
	simSpeed = "max", -- all waits are in sim time
	synced = {
		prepare = arena.prepare,
		clear = function()
			lanes = {}
			return arena.clear()
		end,
		-- one attacker + one unkillable target at `distance`; returns "attacker,target" or a message
		place = function(attackerName, attackerTeam, targetTeam, laneZ, distance)
			local x = Game.mapSizeX * 0.3 -- keep clear of the start positions
			local a = Spring.CreateUnit(attackerName, x, Spring.GetGroundHeight(x, laneZ), laneZ, 1, attackerTeam)
			local tx = x + distance
			local t = Spring.CreateUnit(TARGET, tx, Spring.GetGroundHeight(tx, laneZ), laneZ, 3, targetTeam)
			if not a or not t then
				return "could not create " .. (a and TARGET or attackerName)
			end
			arena.unlimitedResources(attackerTeam) -- some weapons cost energy per shot
			Spring.SetUnitMaxHealth(t, TARGET_HP)
			Spring.SetUnitHealth(t, TARGET_HP)
			Spring.MoveCtrl.Enable(a)
			-- decloak: BAR's cloak widget sets hold fire on cloaked units of the local player
			Spring.GiveOrderToUnit(a, CMD.CLOAK, { 0 }, 0)
			Spring.GiveOrderToUnit(a, CMD.FIRE_STATE, { 2 }, 0)
			lanes[t] = { attacker = a, placedFrame = Spring.GetGameFrame(), hits = {} }
			Spring.SetGlobalLos(Spring.GetUnitAllyTeam(a), true)
			return a .. "," .. t
		end,
		-- "damageTaken|description": who hit the target with what, or which weapons fired
		damage = function(target)
			local lane = lanes[target]
			if not lane or not Spring.ValidUnitID(target) then return "-1|target missing" end
			local taken = TARGET_HP - Spring.GetUnitHealth(target)
			local parts = {}
			for what, dmg in pairs(lane.hits) do parts[#parts + 1] = string.format("%s %.0f", what, dmg) end
			if #parts == 0 and not Spring.ValidUnitID(lane.attacker) then
				parts[1] = "attacker died"
			elseif #parts == 0 then
				local a = lane.attacker
				for i, w in ipairs(UnitDefs[Spring.GetUnitDefID(a)].weapons) do
					local reload = Spring.GetUnitWeaponState(a, i, "reloadState") or 0
					local state = reload > lane.placedFrame and " fired" or " idle"
					-- what the weapon is aiming at: its own target, another lane's, or nothing
					local ttype, _, tgt = Spring.GetUnitWeaponTarget(a, i)
					if ttype == 1 then
						state = state .. (tgt == target and " at own target" or (" at other unit " .. tostring(tgt)))
					elseif ttype == 2 then
						state = state .. " at ground"
					else
						state = state .. " no target"
					end
					-- which targeting condition fails against its own target
					if reload <= lane.placedFrame then
						local function yn(v) return v and "y" or "n" end
						state = state .. string.format(" (try %s test %s range %s lof %s canfire %s)",
							yn(Spring.GetUnitWeaponTryTarget(a, i, target)), yn(Spring.GetUnitWeaponTestTarget(a, i, target)),
							yn(Spring.GetUnitWeaponTestRange(a, i, target)), yn(Spring.GetUnitWeaponHaveFreeLineOfFire(a, i, target)),
							yn(Spring.GetUnitWeaponCanFire(a, i)))
					end
					parts[#parts + 1] = WeaponDefs[w.weaponDef].name .. state
				end
				local energy = Spring.GetTeamResources(Spring.GetUnitTeam(a), "energy")
				parts[#parts + 1] = string.format("team energy %.0f", energy or -1)
				local states = Spring.GetUnitStates(a) or {}
				parts[#parts + 1] = "firestate " .. tostring(states.firestate) .. (Spring.GetUnitIsCloaked(a) and ", cloaked" or "")
			end
			table.sort(parts)
			return string.format("%.0f|%s", taken, table.concat(parts, ", "))
		end,
	},
	syncedCallins = {
		UnitDamaged = function(unitID, _, _, damage, paralyzer, weaponDefID, _, attackerID, attackerDefID)
			local lane = lanes[unitID]
			if not lane or paralyzer then return end
			local who = (attackerID == lane.attacker and "own " or "other ")
				.. (attackerDefID and UnitDefs[attackerDefID] and UnitDefs[attackerDefID].name or "?")
			local what = who .. "/" .. (WeaponDefs[weaponDefID] and WeaponDefs[weaponDefID].name or tostring(weaponDefID))
			lane.hits[what] = (lane.hits[what] or 0) + damage
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
		local targetRadius, targetCats = tdef.radius or 0, tdef.modCategories or {}

		-- one entry per (unit, case); long ranges are fine because each case has its own lane
		local cases, skipped = {}, 0
		for _, def in pairs(UnitDefs) do
			if isGroundUnit(def) and def.weapons and #def.weapons > 0 and arena.wants(ctx, def.name)
				and (not sample or sample[def.name]) then
				local mustHit, canReach = ranges(def, targetCats)
				local outside = canReach * (1 + MARGIN) + targetRadius
				if mustHit <= 0 then
					skipped = skipped + 1
				elseif Game.mapSizeX * 0.3 + outside > Game.mapSizeX * 0.95 then
					ctx.log("skipped " .. def.name .. ": reach " .. canReach .. " longer than the map allows")
					skipped = skipped + 1
				else
					cases[#cases + 1] = { def = def, range = mustHit, name = "inside", dist = mustHit * (1 - MARGIN), expect = true }
					cases[#cases + 1] = { def = def, range = canReach, name = "outside", dist = outside, expect = false }
				end
			end
		end
		table.sort(cases, function(a, b) return a.range < b.range end)
		ctx.log(#cases .. " cases; " .. skipped .. " armed ground units have no weapon that can hurt a " .. TARGET)
		ctx.call("prepare") -- flat, featureless arena; start commanders hold fire
		ctx.waitSimFrames(5)

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

			arena.sweep(ctx)
			local placed = {}
			local names = {}
			for lane, c in ipairs(batch) do names[#names + 1] = c.name .. ":" .. c.def.name end
			local batchInfo = " [batch: " .. table.concat(names, ", ") .. "]"
			for lane, c in ipairs(batch) do
				-- the usual lane position; centred only when a single lane is wider than the map
				local z = (spacing > mapZ * 0.9) and mapZ * 0.5 or (mapZ * 0.05 + (lane - 0.5) * spacing)
				local ids, err = ctx.call("place", c.def.name, me, enemy, z, c.dist)
				local a, t = tostring(ids):match("^(%d+),(%d+)$")
				if not a then
					ctx.check(c.name .. ":" .. c.def.name, false, tostring(err or ids))
				else
					c.attacker, c.target = tonumber(a), tonumber(t)
					placed[#placed + 1] = c
				end
			end

			local longest = 0
			for _, c in ipairs(placed) do longest = math.max(longest, c.dist) end
			local waitSim = ctx.waitSimSeconds or ctx.waitSeconds
			waitSim(WAIT_SECONDS + RANGE_SECONDS * longest / 1000)
			for _, c in ipairs(placed) do
				local r, err = ctx.call("damage", c.target)
				local dmg, what = tostring(r):match("^(-?%d+)|(.*)$")
				if not dmg then
					ctx.check(c.name .. ":" .. c.def.name, false, tostring(err or r))
				else
					local damaged = tonumber(dmg) > 0
					if damaged ~= c.expect then what = what .. batchInfo end
					ctx.check(c.name .. ":" .. c.def.name, damaged == c.expect,
						string.format("%s %.0f, distance %.0f, expected %s: took %s damage (%s)",
							c.expect and "must-hit range" or "reach", c.range, c.dist, c.expect and "damage" or "no damage",
							dmg, what))
				end
			end
		end
		ctx.call("clear")
	end,
}
end
