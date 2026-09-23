-- Per-unit-type movement checks for every mobile ground unit of the playable factions
-- (bots, vehicles, hovercraft, amphibious) on a flat land arena. See lib/movement.lua.
local function isCandidate(def)
	local name = def.name
	if not (name:find("^arm") or name:find("^cor") or name:find("^leg")) then
		return false
	end
	if name:find("_scav") or name:find("_dead") or name:find("_heap") then
		return false
	end
	if not def.canMove or def.canFly or def.isBuilding or (def.speed or 0) <= 0 then
		return false
	end
	local md = def.moveDef
	if not md or not md.name or md.name:find("boat") or md.name:find("uboat") or (def.minWaterDepth or 0) > 0 then
		return false -- ships need water: ship_movement
	end
	return true
end

return VFS.Include("workbench/lib/movement.lua")("unit_movement", isCandidate)
