-- UI regression checks: the same checks with ~6,700 units and buildings on the map and ~8 fps. See workbench/lib/ui_checks.lua.
return VFS.Include("workbench/lib/ui_checks.lua")("ui_lategame_lowfps", 3000, 120)
