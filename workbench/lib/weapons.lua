-- Weapon helpers shared by the per-unit weapon scenarios.
local M = {}

-- whether weapon mount `w` (an entry of UnitDef.weapons) with WeaponDef `wd` can hurt a
-- target with category set `targetCats` on its own, when auto-firing: real damage (not
-- BAR's zero-damage `bogus` dummies), target categories that include the target, not a
-- paralyzer (EMP), not manual-fire (D-gun style, never auto-fires), not a torpedo.
function M.hurts(w, wd, targetCats)
	if not wd or wd.paralyzer or wd.manualFire or wd.type == "TorpedoLauncher" then return false end
	if wd.customParams and wd.customParams.bogus then return false end
	local dmg = 0
	for _, d in pairs(wd.damages or {}) do dmg = math.max(dmg, d) end
	if dmg <= 0 then return false end
	if w.onlyTargets and next(w.onlyTargets) then
		for cat in pairs(w.onlyTargets) do
			if targetCats[cat] then return true end
		end
		return false
	end
	return true
end

-- whether any of the unit's weapons can hurt the target
function M.canHurt(def, targetCats)
	for _, w in ipairs(def.weapons or {}) do
		if M.hurts(w, WeaponDefs[w.weaponDef], targetCats) then return true end
	end
	return false
end

function M.playable(def)
	local name = def.name
	return (name:find("^arm") or name:find("^cor") or name:find("^leg")) and not name:find("_scav") and true or false
end

return M
