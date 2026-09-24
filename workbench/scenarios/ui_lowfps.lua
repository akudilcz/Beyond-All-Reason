-- UI regression checks: box select and shift-drag build with the whole gesture inside one ~8 fps frame. See workbench/lib/ui_checks.lua.
return VFS.Include("workbench/lib/ui_checks.lua")("ui_lowfps", 0, 120)
