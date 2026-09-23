-- The units a player can actually get: everything reachable through build options and
-- evolution (customParams.evolution_target) from the start commanders. Generated behaviour checks use it to skip scavenger/boss-only
-- defs (e.g. corvac) whose mechanics are not part of normal play.
local ROOTS = { "armcom", "corcom", "legcom" }

local M = {}
local cache

-- set of unit names reachable from the start commanders
function M.reachable()
	if cache then return cache end
	cache = {}
	local queue = {}
	for _, name in ipairs(ROOTS) do
		if UnitDefNames[name] then queue[#queue + 1] = UnitDefNames[name] end
	end
	while #queue > 0 do
		local def = table.remove(queue)
		if not cache[def.name] then
			cache[def.name] = true
			for _, id in ipairs(def.buildOptions or {}) do
				local o = UnitDefs[id]
				if o and not cache[o.name] then queue[#queue + 1] = o end
			end
			local evolved = def.customParams and UnitDefNames[def.customParams.evolution_target or ""]
			if evolved and not cache[evolved.name] then queue[#queue + 1] = evolved end
		end
	end
	return cache
end

return M
