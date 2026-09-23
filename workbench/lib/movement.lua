-- Movement scenario generator: every unit type accepted by `candidate` crosses a flat
-- arena in parallel lanes. Each type must arrive within a generous budget and never
-- exceed its maxSpeed by more than 10%. Used by unit_movement (land) and
-- ship_movement (flooded arena).
--   return VFS.Include("workbench/lib/movement.lua")(name, candidate, arenaHeight)
local LANES = 24
local LANE_SPACING = 140
local DISTANCE = 1000
local SPEED_TOLERANCE = 1.10
local BUDGET_FACTOR = 3.0 -- allowed time = distance / speed * factor + 8 s (acceleration, turning)

local arena = VFS.Include("workbench/lib/arena.lua")

-- synced state
local tracked = {}

local function encode(t)
	local parts = {}
	for _, v in ipairs(t) do parts[#parts + 1] = v end
	return table.concat(parts, ";")
end

return function(scenarioName, isCandidate, arenaHeight)
return {
	name = scenarioName,
	timeout = 3600,
	synced = {
		prepare = arena.prepare,
		clear = function()
			tracked = {}
			return arena.clear()
		end,
		-- spawn one unit per lane; returns the number spawned
		spawn = function(team, lane, defName)
			local x0 = Game.mapSizeX * 0.5 - DISTANCE * 0.5
			local z = Game.mapSizeZ * 0.5 + (lane - LANES * 0.5) * LANE_SPACING
			local u = Spring.CreateUnit(defName, x0, Spring.GetGroundHeight(x0, z), z, 1, team)
			if u then tracked[u] = { lane = lane, name = defName, maxSpeed = 0 } end
			return u or -1
		end,
		go = function()
			local tx = Game.mapSizeX * 0.5 + DISTANCE * 0.5
			for u, t in pairs(tracked) do
				local _, _, z = Spring.GetUnitPosition(u)
				Spring.GiveOrderToUnit(u, CMD.MOVE, { tx, Spring.GetGroundHeight(tx, z), z }, 0)
			end
			return 0
		end,
		sample = function()
			for u, t in pairs(tracked) do
				if Spring.ValidUnitID(u) then
					local _, _, _, speed = Spring.GetUnitVelocity(u)
					if speed and speed > t.maxSpeed then t.maxSpeed = speed end
				end
			end
			return 0
		end,
		-- "name,distanceLeft,maxObservedSpeed" per tracked unit, ';'-separated
		report = function()
			local tx = Game.mapSizeX * 0.5 + DISTANCE * 0.5
			local out = {}
			for u, t in pairs(tracked) do
				local x = Spring.ValidUnitID(u) and select(1, Spring.GetUnitPosition(u)) or -1
				local left = x >= 0 and math.max(0, tx - x) or -1
				out[#out + 1] = string.format("%s,%.1f,%.3f", t.name, left, t.maxSpeed)
			end
			return encode(out)
		end,
	},
	run = function(ctx)
		local team = Spring.GetMyTeamID()
		local defs = {}
		for _, def in pairs(UnitDefs) do
			if isCandidate(def) then defs[#defs + 1] = def end
		end
		table.sort(defs, function(a, b) return a.name < b.name end)
		ctx.log(#defs .. " unit types")
		ctx.call("prepare", arenaHeight) -- flat arena: slopes change speeds and block paths

		for first = 1, #defs, LANES do
			ctx.call("clear")
			local batch = {}
			for lane = 1, math.min(LANES, #defs - first + 1) do
				local def = defs[first + lane - 1]
				local id = ctx.call("spawn", team, lane, def.name)
				if not id or id < 0 then
					ctx.check("spawn:" .. def.name, false, "CreateUnit failed")
				else
					batch[def.name] = def
				end
			end

			-- budget from the slowest unit in the batch; framerate-independent (sim frames)
			local slowest = math.huge
			for _, def in pairs(batch) do slowest = math.min(slowest, def.speed) end
			local budgetFrames = math.ceil((DISTANCE / slowest * BUDGET_FACTOR + 8) * Game.gameSpeed)
			ctx.waitSimFrames(10)
			ctx.call("go")
			local endFrame = Spring.GetGameFrame() + budgetFrames
			while Spring.GetGameFrame() < endFrame do
				ctx.waitSimFrames(5)
				ctx.call("sample")
			end

			local rep = ctx.call("report") or ""
			for entry in rep:gmatch("[^;]+") do
				local name, left, maxSpeed = entry:match("([^,]+),([^,]+),([^,]+)")
				local def = batch[name]
				if def then
					left, maxSpeed = tonumber(left), tonumber(maxSpeed)
					-- GetUnitVelocity speed is elmos/frame; UnitDef speed is elmos/second
					local maxSpeedPerSec = maxSpeed * Game.gameSpeed
					ctx.check("arrive:" .. name, left >= 0 and left < 60,
						string.format("%.0f elmos short after %.0f s (speed %.1f)", left, budgetFrames / Game.gameSpeed, def.speed))
					ctx.check("speed:" .. name, maxSpeedPerSec <= def.speed * SPEED_TOLERANCE,
						string.format("max observed %.1f vs maxSpeed %.1f", maxSpeedPerSec, def.speed))
				end
			end
		end
		ctx.call("clear")
	end,
}
end
