-- Does an ally *behind* a shooter take away its line of fire? Asks the engine directly
-- (Spring.GetUnitWeaponHaveFreeLineOfFire) for every armed ground unit type: shooter and
-- enemy target at half range, queried alone and then with an allied armpw (a Y-axis
-- cylinder collision volume) parked directly behind the shooter. Nothing lies between the
-- weapon and its target, so the answer must not change. Precise weapons (no spread) check
-- friendlies with TraceRay, whose cylinder test used to accept hits behind the ray start.
local arena = VFS.Include("workbench/lib/arena.lua")

local BLOCKER = "armpw"
-- part 2: rays that start just outside an ally's collision volume and point away from it
-- (only units whose hits use the unit volume: with per-piece volumes, e.g. corraid, a piece
-- can reach past the unit volume, so a "just outside" start is inside a piece: a real hit)
local SURFACE_BLOCKERS = { "armpw", "corak", "armwar", "armham", "corthud", "armstump", "armflash",
	"armck", "armllt", "corllt", "armsolar", "armmex", "armrad" }
local SURFACE_ANGLES = { 30, 45, 60 } -- degrees from +x in the xz plane
local SURFACE_GAPS = { 1, 4 }         -- elmos between the volume and the ray start
local TARGET = "armsolar"

-- ground units and structures with a weapon that can target ground units
local function candidates()
	local list = {}
	for id, def in pairs(UnitDefs) do
		if not def.canFly and #def.weapons > 0 and not def.name:find("scav") and not def.name:find("_") then
			local wd = WeaponDefs[def.weapons[1].weaponDef]
			if wd and wd.range > 100 and wd.range < 1500 and not wd.type:find("Shield") and wd.damages[0] > 1 then
				list[#list + 1] = def.name
			end
		end
	end
	table.sort(list)
	return list
end

local lanes = {} -- synced: shooter -> { target, blocker }

return {
	name = "los_probe_behind",
	timeout = 900,
	simSpeed = "max",
	synced = {
		prepare = arena.prepare,
		clear = function()
			lanes = {}
			return arena.clear()
		end,
		-- one lane: shooter facing +x, target at half range; returns the shooter id
		place = function(team, enemy, shooterName, laneZ)
			local def = UnitDefNames[shooterName]
			local range = WeaponDefs[def.weapons[1].weaponDef].range
			local x = Game.mapSizeX * 0.3
			local s = Spring.CreateUnit(shooterName, x, Spring.GetGroundHeight(x, laneZ), laneZ, 1, team)
			local tx = x + range * 0.5
			local t = Spring.CreateUnit(TARGET, tx, Spring.GetGroundHeight(tx, laneZ), laneZ, 3, enemy)
			if not (s and t) then
				if s then Spring.DestroyUnit(s, false, true) end
				if t then Spring.DestroyUnit(t, false, true) end
				return "could not create units"
			end
			Spring.MoveCtrl.Enable(s)
			Spring.GiveOrderToUnit(s, CMD.FIRE_STATE, { 0 }, 0)
			Spring.SetGlobalLos(Spring.GetUnitAllyTeam(s), true)
			lanes[s] = { target = t, x = x, z = laneZ, radius = def.radius or 16 }
			return s
		end,
		-- park an allied blocker directly behind the shooter (touching, opposite the target)
		block = function(team, s)
			local l = lanes[s]
			if not l then return -1 end
			local bx = l.x - l.radius - UnitDefNames[BLOCKER].radius
			local b = Spring.CreateUnit(BLOCKER, bx, Spring.GetGroundHeight(bx, l.z), l.z, 1, team)
			if not b then return -1 end
			Spring.MoveCtrl.Enable(b)
			Spring.GiveOrderToUnit(b, CMD.FIRE_STATE, { 0 }, 0)
			l.blocker = b
			return b
		end,
		-- a precise (no spread) weapon that avoids friendlies: its line-of-fire check is a TraceRay
		preciseShooter = function(team, x, z)
			for _, name in ipairs(candidates()) do
				local wd = WeaponDefs[UnitDefNames[name].weapons[1].weaponDef]
				if (wd.accuracy or 0) == 0 and (wd.sprayAngle or 0) == 0 and wd.avoidFriendly ~= false then
					local s = Spring.CreateUnit(name, x, Spring.GetGroundHeight(x, z), z, 0, team)
					if s then
						Spring.MoveCtrl.Enable(s)
						Spring.GiveOrderToUnit(s, CMD.FIRE_STATE, { 0 }, 0)
						lanes[s] = { name = name }
						return s
					end
				end
			end
			return "no precise shooter"
		end,
		-- for each start angle and gap: 1 if the ray from just outside <blockerName>'s volume,
		-- pointing away from it, has a free line of fire; returns the answers as a string, and
		-- the same rays with the blocker moved away (control) after a '|'
		surface = function(team, s, blockerName, x, z)
			local b = Spring.CreateUnit(blockerName, x, Spring.GetGroundHeight(x, z), z, 0, team)
			if not b then return "-" end
			Spring.MoveCtrl.Enable(b)
			Spring.GiveOrderToUnit(b, CMD.FIRE_STATE, { 0 }, 0)
			local _, _, _, mx, my, mz = Spring.GetUnitPosition(b, true)
			local sx, sy, sz, ox, oy, oz, vtype = Spring.GetUnitCollisionVolumeData(b)
			local cx, cy, cz = mx + ox, my + oy, mz + oz
			local rays = {}
			for _, a in ipairs(SURFACE_ANGLES) do
				local dx, dz = math.cos(math.rad(a)), math.sin(math.rad(a))
				-- distance from the centre to the volume's edge along (dx, dz), for an
				-- ellipse with the volume's x/z half sizes (boxes: the box edge)
				local rx, rz = sx * 0.5, sz * 0.5
				local edge = (vtype == 2) and math.min(rx / math.max(dx, 1e-6), rz / math.max(dz, 1e-6))
					or 1 / math.sqrt((dx / rx) ^ 2 + (dz / rz) ^ 2)
				for _, g in ipairs(SURFACE_GAPS) do
					local px, pz = cx + dx * (edge + g), cz + dz * (edge + g)
					rays[#rays + 1] = { px, cy, pz, px + dx * 300, cy, pz + dz * 300 }
				end
			end
			local out = {}
			for _, r in ipairs(rays) do
				out[#out + 1] = Spring.GetUnitWeaponHaveFreeLineOfFire(s, 1, r[1], r[2], r[3], r[4], r[5], r[6]) and "1" or "0"
			end
			Spring.MoveCtrl.SetPosition(b, x, Spring.GetGroundHeight(x, z) - 2000, z) -- out of the way
			out[#out + 1] = "|"
			for _, r in ipairs(rays) do
				out[#out + 1] = Spring.GetUnitWeaponHaveFreeLineOfFire(s, 1, r[1], r[2], r[3], r[4], r[5], r[6]) and "1" or "0"
			end
			Spring.DestroyUnit(b, false, true)
			return table.concat(out) .. " " .. tostring(vtype)
		end,
		-- 1 if weapon 1 has a free line of fire to the lane's target, 0 if not, -1 unknown
		free = function(s)
			local l = lanes[s]
			if not l then return -1 end
			local r = Spring.GetUnitWeaponHaveFreeLineOfFire(s, 1, l.target)
			if r == nil then return -1 end
			return r and 1 or 0
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

		local names = {}
		for _, n in ipairs(candidates()) do if ctx.wants(n) then names[#names + 1] = n end end
		local BATCH = 24
		local probed, blocked, list = 0, 0, {}
		for b0 = 1, #names, BATCH do
			local lanesOf = {}
			for i = b0, math.min(b0 + BATCH - 1, #names) do
				local z = Game.mapSizeZ * 0.05 + ((i - b0) + 0.5) * (Game.mapSizeZ * 0.9 / BATCH)
				local s = ctx.call("place", me, enemy, names[i], z)
				if type(s) == "number" then lanesOf[#lanesOf + 1] = { name = names[i], s = s } end
			end
			ctx.waitSimFrames(10)
			for _, l in ipairs(lanesOf) do l.alone = tonumber(ctx.call("free", l.s)) end
			for _, l in ipairs(lanesOf) do ctx.call("block", me, l.s) end
			ctx.waitSimFrames(5)
			for _, l in ipairs(lanesOf) do
				l.behind = tonumber(ctx.call("free", l.s))
				if l.alone == 1 and l.behind ~= nil and l.behind >= 0 then
					probed = probed + 1
					if l.behind == 0 then
						blocked = blocked + 1
						list[#list + 1] = l.name
					end
				end
			end
			arena.sweep(ctx)
		end
		ctx.log(string.format("probed %d unit types with a free line of fire alone", probed))

		-- part 2
		local s = ctx.call("preciseShooter", me, Game.mapSizeX * 0.5, Game.mapSizeZ * 0.9)
		if type(s) ~= "number" then
			ctx.check("ray_leaving_ally_is_free", false, tostring(s))
		else
			local rays, wrong, which = 0, 0, {}
			for i, name in ipairs(SURFACE_BLOCKERS) do
				local x, z = Game.mapSizeX * (0.2 + 0.04 * i), Game.mapSizeZ * 0.5
				local r = tostring(ctx.call("surface", me, s, name, x, z))
				local with, without, vtype = r:match("^(%d+)|(%d+) (%S+)")
				if with then
					for k = 1, #with do
						if without:sub(k, k) == "1" then
							rays = rays + 1
							if with:sub(k, k) == "0" then
								wrong = wrong + 1
								which[name .. " (volume type " .. vtype .. ")"] = true
							end
						end
					end
				end
			end
			local names = {}
			for n in pairs(which) do names[#names + 1] = n end
			table.sort(names)
			ctx.check("ray_leaving_ally_is_free", rays > 0 and wrong == 0, string.format(
				"%d/%d rays starting just outside an ally and pointing away from it are blocked by that ally%s",
				wrong, rays, #names > 0 and (": " .. table.concat(names, ", ")) or ""))
		end
		ctx.check("ally_behind_keeps_line_of_fire", probed > 0 and blocked == 0,
			string.format("%d/%d types lose their line of fire to an ally directly behind%s",
				blocked, probed, #list > 0 and (": " .. table.concat(list, ", ")) or ""))
	end,
}
