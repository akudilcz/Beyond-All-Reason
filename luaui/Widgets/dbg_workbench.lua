local widget = widget ---@type Widget

function widget:GetInfo()
	return {
		name = "Recoil Workbench",
		desc = "Runs Recoil Workbench scenarios when the engine is started with --workbench",
		license = "GNU GPL, v2 or later",
		layer = -math.huge,
		enabled = true,
	}
end

local harness

function widget:Initialize()
	if not (Spring.Workbench and Spring.Workbench.IsActive()) then
		widgetHandler:RemoveWidget(self)
		return
	end
	harness = VFS.Include("workbench/harness.lua")
end

function widget:GameStart()
	harness.Start()
end

function widget:GameFrame()
	if harness then
		harness.GameFrame()
	end
end

function widget:Update()
	if harness and Spring.GetGameFrame() > 0 then
		harness.Update()
	end
end
