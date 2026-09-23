-- Per-unit-type movement checks for every ship and submarine of the playable factions,
-- on a flooded arena (the whole map levelled to 200 elmos below the water line).
-- See lib/movement.lua.
local WATER_DEPTH = 200
local LANE_SPACING = 240 -- hulls are wide: neighbouring ships must not bump each other

local function isCandidate(def)
	local name = def.name
	if not (name:find("^arm") or name:find("^cor") or name:find("^leg")) or name:find("_scav") then
		return false
	end
	if not def.canMove or def.canFly or def.isBuilding or (def.speed or 0) <= 0 then
		return false
	end
	local md = def.moveDef
	return md and md.name and (md.name:find("boat") or md.name:find("uboat") or (def.minWaterDepth or 0) > 0) and true or false
end

return VFS.Include("workbench/lib/movement.lua")("ship_movement", isCandidate, -WATER_DEPTH, LANE_SPACING)
