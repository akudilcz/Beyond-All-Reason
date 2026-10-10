-- Guards for engine fixes the fork carries whose effect only shows with real units, on a
-- flat arena. Each check fails on an engine without its fix:
--   stop_when_target_dies   an attacker still closing in on its target stops when the
--                           target dies, instead of walking on to its last position (#3333)
--   stop_when_move_removed  removing the active move command from the queue stops the unit (#3333)
--   self_attack_no_repeat:<unit>  with Repeat on, a permanently invalid attack (the unit
--                           itself) finishes once and leaves the queue (#3368); the
--                           stationary, mobile, aircraft and builder command AIs
--   repeat_still_repeats    Repeat on keeps re-queueing valid orders (control for #3368)
--   los_after_terrain_change  lowering terrain that blocked a unit's sight updates its
--                           LOS even when the changed rectangle's corner is out of the
--                           unit's sight radius (#3438)
--   synced_request_path     Spring.RequestPath from synced Lua returns a path (#3459;
--                           the engine crashed writing through a null search path)
-- Test units belong to a team the local player does not control, so no player widget
-- gives them orders.
local arena = VFS.Include("workbench/lib/arena.lua")

local SETTLE_SECONDS = 3 -- after the event under test: braking, LOS refresh

-- synced helpers
local function create(defName, x, z, team)
	local u = Spring.CreateUnit(defName, x, Spring.GetGroundHeight(x, z), z, 1, team)
	if u then
		Spring.GiveOrderToUnit(u, CMD.FIRE_STATE, { 0 }, 0)
	end
	return u
end

local function allyOf(team)
	return select(6, Spring.GetTeamInfo(team, false))
end

-- "speed,queueLength,x,z" of unit u (speed in elmos per second)
local function motion(u)
	if not Spring.ValidUnitID(u) then return "dead" end
	local _, _, _, w = Spring.GetUnitVelocity(u)
	local x, _, z = Spring.GetUnitPosition(u)
	return string.format("%.2f,%d,%.0f,%.0f", w * Game.gameSpeed, Spring.GetUnitCommandCount(u), x, z)
end

local function parseMotion(s)
	local speed, queue, x, z = tostring(s):match("^([%d.]+),(%d+),(-?%d+),(-?%d+)$")
	if not speed then return nil end
	return { speed = tonumber(speed), queue = tonumber(queue), x = tonumber(x), z = tonumber(z) }
end

-- the LOS geometry (see losSetup)
local WALL_WIDTH = 128
local WALL_HEIGHT = 600

return {
	name = "engine_regressions",
	timeout = 600,
	simSpeed = "max", -- every wait is in sim time
	synced = {
		prepare = arena.prepare,
		clear = function()
			for _, a in ipairs(Spring.GetAllyTeamList()) do
				Spring.SetGlobalLos(a, false)
			end
			return arena.clear()
		end,
		motion = motion,

		-- an attacker far from its (visible) target, ordered to attack it; "attacker,target"
		chaseSetup = function(team, enemyTeam)
			local x, z = Game.mapSizeX * 0.2, Game.mapSizeZ * 0.3
			local a = create("armpw", x, z, team)
			local t = create("armpw", x + 2400, z, enemyTeam)
			if not (a and t) then return "could not create armpw" end
			Spring.GiveOrderToUnit(t, CMD.MOVE_STATE, { 0 }, 0)
			Spring.SetGlobalLos(allyOf(team), true) -- an attack order needs the target in sight
			Spring.GiveOrderToUnit(a, CMD.FIRE_STATE, { 2 }, 0)
			Spring.GiveOrderToUnit(a, CMD.ATTACK, { t }, 0)
			return a .. "," .. t
		end,
		kill = function(u)
			Spring.DestroyUnit(u, false, true)
			return 0
		end,

		-- a unit walking to a far point; returns the unit
		walkSetup = function(team)
			local x, z = Game.mapSizeX * 0.2, Game.mapSizeZ * 0.5
			local u = create("armpw", x, z, team)
			if not u then return "could not create armpw" end
			Spring.GiveOrderToUnit(u, CMD.MOVE, { x + 2400, Spring.GetGroundHeight(x + 2400, z), z }, 0)
			return u
		end,
		-- removes the active command by its tag (a queue edit, as the command queue UI does)
		removeActive = function(u)
			local cmd = (Spring.GetUnitCommands(u, 1) or {})[1]
			if not cmd then return "no active command" end
			Spring.GiveOrderToUnit(u, CMD.REMOVE, { cmd.tag }, 0)
			return 0
		end,

		-- unit `defName` with Repeat on attacking itself; returns the unit
		selfAttackSetup = function(team, defName, slot)
			local x, z = Game.mapSizeX * 0.5 + slot * 200, Game.mapSizeZ * 0.7
			local u = create(defName, x, z, team)
			if not u then return "could not create " .. defName end
			Spring.GiveOrderToUnit(u, CMD.REPEAT, { 1 }, 0)
			if not Spring.GetUnitStates(u)["repeat"] then return defName .. " does not take Repeat" end
			-- the command AI is under test, not the weapon: it never reloads (an engine
			-- without the fix keeps the self-attack, which must not hit anything)
			for w = 1, #UnitDefNames[defName].weapons do
				Spring.SetUnitWeaponState(u, w, { reloadState = Spring.GetGameFrame() + 1e6 })
			end
			Spring.GiveOrderToUnit(u, CMD.ATTACK, { u }, 0)
			return u
		end,
		-- a unit with Repeat on patrolling between two move orders; returns the unit
		repeatSetup = function(team)
			local x, z = Game.mapSizeX * 0.5, Game.mapSizeZ * 0.85
			local u = create("armpw", x, z, team)
			if not u then return "could not create armpw" end
			Spring.GiveOrderToUnit(u, CMD.REPEAT, { 1 }, 0)
			Spring.GiveOrderToUnit(u, CMD.MOVE, { x + 200, Spring.GetGroundHeight(x + 200, z), z }, 0)
			Spring.GiveOrderToUnit(u, CMD.MOVE, { x, Spring.GetGroundHeight(x, z), z }, { "shift" })
			return u
		end,

		-- a radar tower with a tall wall WALL_WIDTH west of it and a probe point behind the
		-- wall, inside the tower's sight radius. Returns "probeX,probeZ,wallX1"
		losSetup = function(team)
			local def = UnitDefNames.armrad
			local r = def.losRadius
			local x, z = Game.mapSizeX * 0.75, Game.mapSizeZ * 0.3
			local wallX2 = x - 0.15 * r
			local wallX1 = wallX2 - WALL_WIDTH
			local probeX = x - 0.75 * r
			local ground = Spring.GetGroundHeight(x, z)
			Spring.LevelHeightMap(wallX1, z - 256, wallX2, z + 256, ground + WALL_HEIGHT)
			if not create("armrad", x, z, team) then return "could not create armrad" end
			return string.format("%.0f,%.0f,%.0f", probeX, z, wallX1)
		end,
		-- lowers the wall as part of a rectangle reaching far west, so the rectangle's
		-- west corner is more than the sight radius from the tower (the pre-#3438 test
		-- measured from that corner and skipped the tower)
		losLowerWall = function(wallX1, z)
			local r = UnitDefNames.armrad.losRadius
			local x1 = math.max(0, wallX1 - 2 * r - 200)
			Spring.LevelHeightMap(x1, z - 256, wallX1 + WALL_WIDTH, z + 256, Spring.GetGroundHeight(x1, z))
			return 0
		end,
		inLos = function(x, z, team)
			return Spring.IsPosInLos(x, Spring.GetGroundHeight(x, z), z, allyOf(team)) and 1 or 0
		end,

		-- number of waypoints of a synced path request across the arena (0: no path)
		requestPath = function()
			local md = UnitDefNames.armpw.moveDef
			local y = Spring.GetGroundHeight(1000, 1000)
			local path = Spring.RequestPath(md.name, 1000, y, 1000, 3000, y, 1500)
			if not path then return 0 end
			return #(path:GetPathWayPoints() or {})
		end,
	},
	run = function(ctx)
		local me = Spring.GetMyTeamID()
		local team, enemy = me, me
		for _, t in ipairs(Spring.GetTeamList()) do
			if t ~= me and t ~= Spring.GetGaiaTeamID() and not Spring.AreTeamsAllied(t, me) then team = t break end
		end
		if team == me then
			ctx.check("setup", false, "no team besides the local player's")
			return
		end
		local pwSpeed = UnitDefNames.armpw.speed
		ctx.call("prepare")
		ctx.waitSimFrames(5)

		local function waitMotion(u)
			return parseMotion(ctx.call("motion", u))
		end
		local function dist(a, b)
			return math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2)
		end
		-- a unit that was moving (`before`) is stopped with an empty queue (`after`)
		local function stopped(name, before, after, what)
			if not (before and after) then
				ctx.check(name, false, "unit died")
			elseif before.speed < 0.5 * pwSpeed then
				ctx.check(name, false, string.format("never got moving (%.1f elmos/s before %s)", before.speed, what))
			else
				ctx.check(name, after.queue == 0 and after.speed < 0.1 * pwSpeed,
					string.format("%.0f elmos/s before %s; %d s later %.1f elmos/s, %d queued, moved %.0f elmos",
						before.speed, what, SETTLE_SECONDS, after.speed, after.queue, dist(before, after)))
			end
		end

		-- #3333: target dies while the attacker closes in
		local ids, err = ctx.call("chaseSetup", team, me)
		local a, t = tostring(ids):match("^(%d+),(%d+)$")
		if not a then
			ctx.check("stop_when_target_dies", false, tostring(err or ids))
		else
			a, t = tonumber(a), tonumber(t)
			ctx.waitSimSeconds(3)
			local before = waitMotion(a)
			ctx.call("kill", t)
			ctx.waitSimSeconds(SETTLE_SECONDS)
			stopped("stop_when_target_dies", before, waitMotion(a), "the target died")
		end
		arena.sweep(ctx)

		-- #3333: the active move is removed from the queue
		local u, uerr = ctx.call("walkSetup", team)
		if type(u) ~= "number" then
			ctx.check("stop_when_move_removed", false, tostring(uerr or u))
		else
			ctx.waitSimSeconds(3)
			local before = waitMotion(u)
			local r = ctx.call("removeActive", u)
			if r ~= 0 then
				ctx.check("stop_when_move_removed", false, tostring(r))
			else
				ctx.waitSimSeconds(SETTLE_SECONDS)
				stopped("stop_when_move_removed", before, waitMotion(u), "the removal")
			end
		end
		arena.sweep(ctx)

		-- #3368: one subject per command AI kind
		local subjects = { "armjuno", "armstump", "armfig", "armcom" } -- stationary, mobile, aircraft, builder
		local selfIDs = {}
		for i, name in ipairs(subjects) do
			local id, serr = ctx.call("selfAttackSetup", team, name, i)
			if type(id) ~= "number" then
				ctx.check("self_attack_no_repeat:" .. name, false, tostring(serr or id))
			else
				selfIDs[name] = id
			end
		end
		local rep = ctx.call("repeatSetup", team)
		ctx.waitSimSeconds(10)
		for _, name in ipairs(subjects) do
			if selfIDs[name] then
				local m = waitMotion(selfIDs[name])
				ctx.check("self_attack_no_repeat:" .. name, m ~= nil and m.queue == 0,
					m and string.format("%d commands queued 10 s after a self-attack with Repeat on", m.queue) or "unit died")
			end
		end
		if type(rep) ~= "number" then
			ctx.check("repeat_still_repeats", false, tostring(rep))
		else
			local m = waitMotion(rep)
			ctx.check("repeat_still_repeats", m ~= nil and m.queue == 2,
				m and string.format("%d of 2 move orders still queued after 10 s with Repeat on", m.queue) or "unit died")
		end
		arena.sweep(ctx)

		-- #3438: terrain lowered in a wide rectangle next to a radar tower
		local geo, gerr = ctx.call("losSetup", team)
		local px, pz, wx = tostring(geo):match("^(%d+),(%d+),(%d+)$")
		if not px then
			ctx.check("los_after_terrain_change", false, tostring(gerr or geo))
		else
			px, pz, wx = tonumber(px), tonumber(pz), tonumber(wx)
			ctx.waitSimSeconds(SETTLE_SECONDS)
			local blocked = ctx.call("inLos", px, pz, team) == 0
			ctx.call("losLowerWall", wx, pz)
			ctx.waitSimSeconds(SETTLE_SECONDS)
			local seen = ctx.call("inLos", px, pz, team) == 1
			ctx.check("los_after_terrain_change", blocked and seen,
				string.format("point behind the wall: hidden while it stands %s, in sight %d s after it was lowered %s",
					tostring(blocked), SETTLE_SECONDS, tostring(seen)))
		end
		arena.sweep(ctx)

		-- #3459
		local n, perr = ctx.call("requestPath")
		ctx.check("synced_request_path", type(n) == "number" and n > 1,
			type(n) == "number" and string.format("%d waypoints", n) or tostring(perr))
		ctx.call("clear")
	end,
}
