-- Behaviour checks beyond moving and shooting, on a flat arena with unlimited resources:
--   produce:<factory>  every land factory produces its cheapest mobile unit
--   build:<builder>    every mobile ground builder finishes its cheapest land structure
--   transport          an air transport picks up a bot and unloads it elsewhere
--   cloak              a cloakable unit cloaks when ordered and stays cloaked while idle
--   radar              a radar reveals an enemy unit outside line of sight
-- Budgets come from the build times in the defs (x2 plus slack), so a check fails when
-- a unit cannot do its job at all or is far slower than its stats say, not on jitter.
local arena = VFS.Include("workbench/lib/arena.lua")

local SPACING = 320
local SLACK_SECONDS = 15

local function playable(def)
	local name = def.name
	return (name:find("^arm") or name:find("^cor") or name:find("^leg")) and not name:find("_scav")
end

local function landOK(def)
	local md = def.moveDef
	if def.canFly then return true end
	return (def.minWaterDepth or 0) <= 0 and not (md and md.name and (md.name:find("boat") or md.name:find("uboat")))
end

-- cheapest build option satisfying pred, or nil
local function cheapestOption(def, pred)
	local best
	for _, id in ipairs(def.buildOptions or {}) do
		local o = UnitDefs[id]
		if o and pred(o) and (not best or o.buildTime < best.buildTime) then best = o end
	end
	return best
end

local function isPlainStructure(o)
	return o.isBuilding and landOK(o) and not o.needGeo and (o.extractsMetal or 0) == 0
end

local function isMobile(o)
	return o.canMove and landOK(o)
end

local function gridPos(i)
	local cols = math.floor(Game.mapSizeX * 0.8 / SPACING)
	local x = Game.mapSizeX * 0.1 + ((i - 1) % cols) * SPACING
	local z = Game.mapSizeZ * 0.1 + math.floor((i - 1) / cols) * SPACING
	return x, z
end

-- synced helpers
local function unlimitedResources(team)
	for _, r in ipairs({ "m", "e" }) do
		Spring.SetTeamResource(team, r .. "s", 1e7)
		Spring.SetTeamResource(team, r, 1e7)
	end
end

local function create(defName, x, z, facing, team)
	return Spring.CreateUnit(defName, x, Spring.GetGroundHeight(x, z), z, facing or 0, team)
end

-- a finished unit of defName near (x, z)
local function finishedNear(defName, x, z, radius, team)
	local id = UnitDefNames[defName].id
	for _, u in ipairs(Spring.GetUnitsInCylinder(x, z, radius, team)) do
		if Spring.GetUnitDefID(u) == id and not Spring.GetUnitIsBeingBuilt(u) then return u end
	end
end

local jobs = {} -- synced: index -> { kind, maker, product, x, z }

return {
	name = "unit_behaviours",
	timeout = 3600,
	synced = {
		prepare = arena.prepare,
		clear = function()
			jobs = {}
			return arena.clear()
		end,
		-- places a factory or builder at grid slot i and orders it to make `product`
		startJob = function(team, i, kind, makerName, productName)
			unlimitedResources(team)
			local x, z = gridPos(i)
			local maker = create(makerName, x, z, 0, team)
			if not maker then return "could not create " .. makerName end
			local pid = UnitDefNames[productName].id
			if kind == "produce" then
				Spring.GiveOrderToUnit(maker, -pid, {}, 0)
			else
				local bx = x + SPACING * 0.4
				Spring.GiveOrderToUnit(maker, -pid, { bx, Spring.GetGroundHeight(bx, z), z, 0 }, 0)
			end
			jobs[i] = { maker = maker, product = productName, x = x, z = z }
			return 0
		end,
		-- comma-separated indices of the jobs whose product is finished
		jobsDone = function(team)
			unlimitedResources(team)
			local done = {}
			for i, j in pairs(jobs) do
				if finishedNear(j.product, j.x, j.z, SPACING * 0.9, team) then done[#done + 1] = i end
			end
			return table.concat(done, ",")
		end,

		-- transport: returns "transportID,cargoID"
		transportSetup = function(team, transportName, cargoName)
			local x, z = Game.mapSizeX * 0.3, Game.mapSizeZ * 0.5
			local t = create(transportName, x, z, 0, team)
			local c = create(cargoName, x + 150, z, 0, team)
			if not (t and c) then return "could not create " .. transportName .. "/" .. cargoName end
			Spring.GiveOrderToUnit(t, CMD.LOAD_UNITS, { c }, 0)
			local ux = x + 900
			Spring.GiveOrderToUnit(t, CMD.UNLOAD_UNIT, { ux, Spring.GetGroundHeight(ux, z), z }, { "shift" })
			return t .. "," .. c
		end,
		-- "carried,distanceFromDrop" of the cargo
		transportState = function(transport, cargo)
			if not Spring.ValidUnitID(cargo) then return "dead" end
			local ux, z = Game.mapSizeX * 0.3 + 900, Game.mapSizeZ * 0.5
			local x, _, cz = Spring.GetUnitPosition(cargo)
			local carrier = Spring.GetUnitTransporter(cargo)
			return string.format("%d,%.0f", carrier and 1 or 0, math.sqrt((x - ux) ^ 2 + (cz - z) ^ 2))
		end,

		-- cloak: returns the unit id
		cloakSetup = function(team, defName)
			unlimitedResources(team)
			local x, z = Game.mapSizeX * 0.5, Game.mapSizeZ * 0.3
			local u = create(defName, x, z, 0, team)
			if not u then return "could not create " .. defName end
			Spring.GiveOrderToUnit(u, CMD.CLOAK, { 1 }, 0)
			return u
		end,
		isCloaked = function(team, u)
			unlimitedResources(team)
			return Spring.GetUnitIsCloaked(u) and 1 or 0
		end,

		-- radar: a radar tower for `team` and an enemy bot outside its LOS but in radar range
		radarSetup = function(team, enemyTeam, radarName, targetName)
			unlimitedResources(team)
			local x, z = Game.mapSizeX * 0.7, Game.mapSizeZ * 0.7
			local r = create(radarName, x, z, 0, team)
			local rdef = UnitDefNames[radarName]
			local dist = (rdef.losRadius + rdef.radarRadius) * 0.5
			local t = create(targetName, x + dist, z, 0, enemyTeam)
			if not (r and t) then return "could not create " .. radarName .. "/" .. targetName end
			Spring.GiveOrderToUnit(t, CMD.FIRE_STATE, { 0 }, 0)
			return t
		end,
		-- "inRadar,inLos" of unit u for allyTeam
		losState = function(allyTeam, u)
			if not Spring.ValidUnitID(u) then return "dead" end
			local s = Spring.GetUnitLosState(u, allyTeam, true)
			local los, radar = s % 2, math.floor(s / 2) % 2 -- bits: 1 in los, 2 in radar
			return radar .. "," .. los
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

		-- 1+2: production and construction, all jobs of a kind in parallel
		local function runJobs(kind, list)
			ctx.call("clear")
			ctx.waitSimFrames(2)
			local budget = 0
			for i, j in ipairs(list) do
				local r, err = ctx.call("startJob", me, i, kind, j.maker.name, j.product.name)
				if r ~= 0 then
					ctx.check(kind .. ":" .. j.maker.name, false, tostring(err or r))
					j.failed = true
				end
				local seconds = j.product.buildTime / math.max(1, j.maker.buildSpeed)
				budget = math.max(budget, seconds * 2 + SLACK_SECONDS)
			end
			ctx.log(string.format("%d %s jobs, budget %.0f s", #list, kind, budget))
			local deadline = Spring.GetGameFrame() + math.ceil(budget * Game.gameSpeed)
			local pending = #list
			while pending > 0 and Spring.GetGameFrame() < deadline do
				ctx.waitSimFrames(30)
				for i in tostring(ctx.call("jobsDone", me) or ""):gmatch("%d+") do
					list[tonumber(i)].done = true
				end
				pending = 0
				for _, j in ipairs(list) do
					if not j.failed and not j.done then pending = pending + 1 end
				end
			end
			for _, j in ipairs(list) do
				if not j.failed then
					ctx.check(kind .. ":" .. j.maker.name, j.done,
						string.format("%s %s within %.0f s", j.done and "made" or "did not make", j.product.name, budget))
				end
			end
		end

		local factories, builders = {}, {}
		for _, def in pairs(UnitDefs) do
			if playable(def) and def.buildOptions and #def.buildOptions > 0 and landOK(def) then
				if def.isFactory then
					local p = cheapestOption(def, isMobile)
					if p then factories[#factories + 1] = { maker = def, product = p } end
				elseif def.canMove and not def.canFly and def.isBuilder then
					local p = cheapestOption(def, isPlainStructure)
					if p then builders[#builders + 1] = { maker = def, product = p } end
				end
			end
		end
		local byName = function(a, b) return a.maker.name < b.maker.name end
		table.sort(factories, byName)
		table.sort(builders, byName)
		runJobs("produce", factories)
		runJobs("build", builders)
		ctx.call("clear")

		-- 3: transport
		local ids, err = ctx.call("transportSetup", me, "armatlas", "armpw")
		local tr, cargo = tostring(ids):match("(%d+),(%d+)")
		if not tr then
			ctx.check("transport", false, tostring(err or ids))
		else
			local loaded, dist = false, math.huge
			ctx.waitUntil(function()
				local s = ctx.call("transportState", tonumber(tr), tonumber(cargo)) or "dead"
				local l, d = s:match("(%d),(%d+)")
				if not l then return true end
				loaded = loaded or l == "1"
				dist = tonumber(d)
				return loaded and l == "0" and dist < 200
			end, 90)
			ctx.check("transport", loaded and dist < 200,
				string.format("loaded %s, cargo ends %.0f elmos from the drop point", tostring(loaded), dist))
		end
		ctx.call("clear")

		-- 4: cloak
		local spy, cerr = ctx.call("cloakSetup", me, "armspy")
		if type(spy) ~= "number" then
			ctx.check("cloak", false, tostring(cerr or spy))
		else
			local cloaked = ctx.waitUntil(function() return ctx.call("isCloaked", me, spy) == 1 end, 15)
			ctx.waitSeconds(5)
			local stays = ctx.call("isCloaked", me, spy) == 1
			ctx.check("cloak", cloaked and stays, string.format("cloaked %s, still cloaked after 5 s %s", tostring(cloaked), tostring(stays)))
		end
		ctx.call("clear")

		-- 5: radar
		if enemy then
			local target, rerr = ctx.call("radarSetup", me, enemy, "armrad", "corak")
			if type(target) ~= "number" then
				ctx.check("radar", false, tostring(rerr or target))
			else
				local state = "0,0"
				ctx.waitUntil(function()
					state = ctx.call("losState", Spring.GetMyAllyTeamID(), target) or "dead"
					return state:sub(1, 1) == "1"
				end, 15)
				local radar, los = state:match("(%d),(%d)")
				ctx.check("radar", radar == "1" and los == "0",
					"enemy between LOS and radar range: radar " .. tostring(radar) .. ", los " .. tostring(los))
			end
			ctx.call("clear")
		end
	end,
}
