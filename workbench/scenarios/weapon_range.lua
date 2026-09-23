-- Weapon range checks for a sample of ground units (the smoke suite): the same checks
-- as weapon_range_all, a few minutes long. See lib/weapon_range.lua.
local SAMPLE = { "armpw", "armrock", "armham", "corak", "corthud", "corstorm" }
return VFS.Include("workbench/lib/weapon_range.lua")("weapon_range", SAMPLE, 600)
