-- A late-game load: n units per team roaming the map plus n/8 buildings each, all kept out
-- of a clear circle in the middle (where UI checks happen). Synced side only.
local M = {}

M.UNITS = { "armpw", "corak", "armflash", "corgator", "armham", "corthud", "armstump", "corraid" }
M.BUILDINGS = { "armsolar", "corsolar", "armwin", "corwin" }

local spotIndex = 0
M.toughUnits = {} -- units spawned with tough = true

-- call from a GameFrame handler: keeps tough units at full health whatever hits them
function M.heal()
	for u in pairs(M.toughUnits) do
		if Spring.ValidUnitID(u) then Spring.SetUnitHealth(u, 1e6) else M.toughUnits[u] = nil end
	end
end

-- deterministic spread over the map, skipping the clear middle
function M.spot(clearRadius)
	local cx, cz = Game.mapSizeX * 0.5, Game.mapSizeZ * 0.5
	while true do
		spotIndex = spotIndex + 1
		local x = (spotIndex * 7919) % math.floor(Game.mapSizeX * 0.9) + Game.mapSizeX * 0.05
		local z = (spotIndex * 104729) % math.floor(Game.mapSizeZ * 0.9) + Game.mapSizeZ * 0.05
		if (x - cx) ^ 2 + (z - cz) ^ 2 > clearRadius ^ 2 then return x, z end
	end
end

-- returns how many units and buildings were created; holdFire: units do not shoot, so the
-- map keeps its full unit count (movement load) instead of the armies wiping each other out
-- tough: 1e6 health, so a fighting map keeps its unit count too (steady combat load)
function M.spawn(team, enemy, n, clearRadius, holdFire, tough)
	spotIndex = 0
	local made = 0
	for _, t in ipairs({ team, enemy }) do
		for k = 1, n do
			local x, z = M.spot(clearRadius)
			local u = Spring.CreateUnit(M.UNITS[k % #M.UNITS + 1], x, Spring.GetGroundHeight(x, z), z, 0, t)
			if u then
				made = made + 1
				if holdFire then Spring.GiveOrderToUnit(u, CMD.FIRE_STATE, { 0 }, 0) end
				if tough then
					Spring.SetUnitMaxHealth(u, 1e6)
					Spring.SetUnitHealth(u, 1e6)
					M.toughUnits[u] = true
				end
				local tx, tz = M.spot(clearRadius)
				Spring.GiveOrderToUnit(u, CMD.MOVE, { tx, Spring.GetGroundHeight(tx, tz), tz }, 0)
			end
		end
		for k = 1, math.floor(n / 8) do
			local x, z = M.spot(clearRadius)
			if Spring.CreateUnit(M.BUILDINGS[k % #M.BUILDINGS + 1], x, Spring.GetGroundHeight(x, z), z, 0, t) then
				made = made + 1
			end
		end
	end
	return made
end

-- sends every idle mobile unit of both teams somewhere else, so the map keeps moving
function M.roam(team, enemy, clearRadius)
	local sent = 0
	for _, t in ipairs({ team, enemy }) do
		for _, u in ipairs(Spring.GetTeamUnits(t)) do
			local def = UnitDefs[Spring.GetUnitDefID(u)]
			if def and def.speed > 0 and (Spring.GetUnitCommandCount(u) or 0) == 0 then
				local tx, tz = M.spot(clearRadius)
				Spring.GiveOrderToUnit(u, CMD.MOVE, { tx, Spring.GetGroundHeight(tx, tz), tz }, 0)
				sent = sent + 1
			end
		end
	end
	return sent
end

return M
