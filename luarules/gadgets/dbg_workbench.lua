local gadget = gadget ---@type Gadget

function gadget:GetInfo()
	return {
		name = "Recoil Workbench",
		desc = "Synced half of the Recoil Workbench harness (runs scenario synced functions)",
		license = "GNU GPL, v2 or later",
		layer = 0,
		enabled = true,
	}
end

if not gadgetHandler:IsSyncedCode() then
	return
end

if not (Spring.Workbench and Spring.Workbench.IsActive()) then
	return
end

local harness = VFS.Include("workbench/harness.lua")

function gadget:Initialize()
	harness.StartSynced()
end

function gadget:RecvLuaMsg(msg, playerID)
	return harness.RecvSynced(msg)
end

-- forward the synced callins scenarios may handle (engines whose harness predates them
-- have no SyncedCallin)
if harness.SyncedCallin then
	for _, name in ipairs(harness.SYNCED_CALLINS) do
		gadget[name] = function(_, ...)
			harness.SyncedCallin(name, ...)
		end
	end
end
