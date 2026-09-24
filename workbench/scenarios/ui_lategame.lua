-- UI regression checks: the same checks with ~6,700 units and buildings on the map, at the engine's own frame rate. See workbench/lib/ui_checks.lua.
return VFS.Include("workbench/lib/ui_checks.lua")("ui_lategame", 3000, nil)
