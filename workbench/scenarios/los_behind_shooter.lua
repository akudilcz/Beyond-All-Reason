-- Does a unit directly *behind* a shooter block its line of fire?
-- For several common ground units: a shooter faces an unkillable enemy structure at half
-- its range; in the "clear" lane it stands alone, in the "blocked" lane an allied unit of
-- the same type is parked right behind it (touching, opposite the target). If only the
-- clear lane does damage, units behind a weapon's firing point block it, which is a bug:
-- nothing lies between the weapon and its target.
local arena = VFS.Include("workbench/lib/arena.lua")

local SHOOTERS = { "armpw", "corak", "armham", "corthud", "armstump", "corraid", "armflash", "corgator" }
local TARGET = "armsolar"
local TARGET_HP = 1e6
local WAIT_SECONDS = 12

local lanes = {} -- synced: target -> { shooter, damage } (only the lane's own shooter counts)

return {
	name = "los_behind_shooter",
	timeout = 300,
	simSpeed = "max",
	synced = {
		prepare = arena.prepare,
		clear = function()
			lanes = {}
			return arena.clear()
		end,
		-- blocked: 1 to park an ally directly behind the shooter; returns the target id
		place = function(team, enemy, shooterName, laneZ, blocked)
			local def = UnitDefNames[shooterName]
			local range = 0
			for _, w in ipairs(def.weapons) do range = math.max(range, WeaponDefs[w.weaponDef].range) end
			local x = Game.mapSizeX * 0.3
			local s = Spring.CreateUnit(shooterName, x, Spring.GetGroundHeight(x, laneZ), laneZ, 1, team) -- facing +x
			local tx = x + range * 0.5
			local t = Spring.CreateUnit(TARGET, tx, Spring.GetGroundHeight(tx, laneZ), laneZ, 3, enemy)
			if not (s and t) then return "could not create units" end
			Spring.SetUnitMaxHealth(t, TARGET_HP)
			Spring.SetUnitHealth(t, TARGET_HP)
			arena.unlimitedResources(team)
			Spring.MoveCtrl.Enable(s)
			Spring.GiveOrderToUnit(s, CMD.FIRE_STATE, { 2 }, 0)
			if blocked == 1 then
				local bx = x - (def.radius or 16) * 2 -- touching, directly behind (-x)
				local b = Spring.CreateUnit(shooterName, bx, Spring.GetGroundHeight(bx, laneZ), laneZ, 1, team)
				if b then
					Spring.MoveCtrl.Enable(b)
					Spring.GiveOrderToUnit(b, CMD.FIRE_STATE, { 0 }, 0) -- the blocker never shoots
				end
			end
			Spring.SetGlobalLos(Spring.GetUnitAllyTeam(s), true)
			lanes[t] = { shooter = s, damage = 0 }
			return t
		end,
		damage = function(target)
			return lanes[target] and lanes[target].damage or -1
		end,
	},
	syncedCallins = {
		UnitDamaged = function(unitID, _, _, damage, paralyzer, _, _, attackerID)
			local lane = lanes[unitID]
			if lane and not paralyzer and attackerID == lane.shooter then lane.damage = lane.damage + damage end
		end,
	},
	run = function(ctx)
		local me = Spring.GetMyTeamID()
		local enemy
		for _, t in ipairs(Spring.GetTeamList()) do
			if not Spring.AreTeamsAllied(t, me) and t ~= Spring.GetGaiaTeamID() then enemy = t break end
		end
		ctx.call("prepare")
		ctx.waitSimFrames(5)
		arena.sweep(ctx)

		local results = {}
		for i, name in ipairs(SHOOTERS) do
			for blocked = 0, 1 do
				local z = Game.mapSizeZ * 0.05 + ((i - 1) * 2 + blocked + 0.5) * (Game.mapSizeZ * 0.9 / (#SHOOTERS * 2))
				local t, err = ctx.call("place", me, enemy, name, z, blocked)
				results[#results + 1] = { name = name, blocked = blocked, target = type(t) == "number" and t or nil, err = err or t }
			end
		end
		ctx.waitSimFrames(WAIT_SECONDS * Game.gameSpeed)

		local byName = {}
		for _, r in ipairs(results) do
			local dmg = r.target and tonumber(ctx.call("damage", r.target)) or -1
			byName[r.name] = byName[r.name] or {}
			byName[r.name][r.blocked] = dmg
		end
		for _, name in ipairs(SHOOTERS) do
			local clear, blocked = byName[name][0] or -1, byName[name][1] or -1
			ctx.check("not_blocked_by_ally_behind:" .. name, clear <= 0 or blocked > 0,
				string.format("damage alone %.0f, with an ally directly behind %.0f", clear, blocked))
		end
		arena.sweep(ctx)
	end,
}
