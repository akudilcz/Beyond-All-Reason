-- Low-frame-rate UI regression tests: the whole mouse gesture (move, press, drag,
-- release) happens inside one frame at ~8 fps, which is what broke box selection
-- (SmartSelect overriding the engine with a stale selection) and drag-building
-- (modifier state read from the end of the event batch) with many units.
-- Uses the engine's input emulation, so it drives the real input pipeline.
--
-- Verified by mutation: with the SmartSelect fix reverted, box_select_low_fps selects
-- 0/12 units; with it, 12/12. drag_build_one_frame guards low-fps drag-building but
-- cannot catch a regression of the KeyInput modifier fix: emulated keys set modifier
-- state directly instead of going through the SDL event batch where that bug lived.
-- That fix is guarded by the engine unit test test_KeyInput instead.
-- Generator: ui_checks(name, clutter, stallMs). clutter = number of extra units (both
-- teams, moving) plus buildings spread over the map to reproduce a late game; stallMs =
-- artificial frame stall (nil: the engine's own frame rate under that load).
local GROUP = 12
local CLEAR_RADIUS = 900 -- clutter stays out of the middle, where the checks happen
local CLUTTER_UNITS = { "armpw", "corak", "armflash", "corgator", "armham", "corthud", "armstump", "corraid" }
local CLUTTER_BUILDINGS = { "armsolar", "corsolar", "armwin", "corwin" }

return function(scenarioName, clutter, stallMs)

local preexisting = {}
local grouped = {}

local function screenBox(units, margin)
	local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
	for _, u in ipairs(units) do
		local x, y, z = Spring.GetUnitPosition(u)
		local sx, sy = Spring.WorldToScreenCoords(x, y, z)
		x0, y0 = math.min(x0, sx), math.min(y0, sy)
		x1, y1 = math.max(x1, sx), math.max(y1, sy)
	end
	return x0 - margin, y0 - margin, x1 + margin, y1 + margin
end

-- the low-fps box select: the drag starts and SmartSelect's Update runs while the box
-- is still small (and covers no units); then the rest of the drag and the release
-- arrive together in the next frame, before Update runs again
local function dragAcrossOneFrameBoundary(ctx, x0, y0, x1, y1, button)
	debug.emulateMouseMove(math.floor(x0), math.floor(y0))
	debug.emulateMousePress(button)
	debug.emulateMouseMove(math.floor(x0) + 30, math.floor(y0) + 30)
	ctx.waitFrames(1)
	-- physical input is handled before the GUI update in a frame; emulate that ordering
	ctx.atNextGameFrame(function()
		debug.emulateMouseMove(math.floor(x1), math.floor(y1))
		debug.emulateMouseRelease(button)
	end)
end

-- a complete drag gesture inside the current frame
local function dragInOneFrame(x0, y0, x1, y1, button)
	debug.emulateMouseMove(math.floor(x0), math.floor(y0))
	debug.emulateMousePress(button)
	debug.emulateMouseMove(math.floor((x0 + x1) / 2), math.floor((y0 + y1) / 2))
	debug.emulateMouseMove(math.floor(x1), math.floor(y1))
	debug.emulateMouseRelease(button)
end

return {
	name = scenarioName,
	timeout = 180 + (clutter or 0) / 20,
	synced = {
		-- n units for each of the two teams roaming the map, plus n/8 buildings each, all
		-- outside CLEAR_RADIUS of the centre; returns how many were created
		spawnClutter = function(team, enemy, n)
			local cx, cz = Game.mapSizeX * 0.5, Game.mapSizeZ * 0.5
			local made, i = 0, 0
			local function spot()
				-- deterministic spread over the map, skipping the clear middle
				while true do
					i = i + 1
					local x = (i * 7919) % math.floor(Game.mapSizeX * 0.9) + Game.mapSizeX * 0.05
					local z = (i * 104729) % math.floor(Game.mapSizeZ * 0.9) + Game.mapSizeZ * 0.05
					if (x - cx) ^ 2 + (z - cz) ^ 2 > CLEAR_RADIUS ^ 2 then return x, z end
				end
			end
			for _, t in ipairs({ team, enemy }) do
				for k = 1, n do
					local x, z = spot()
					local u = Spring.CreateUnit(CLUTTER_UNITS[k % #CLUTTER_UNITS + 1], x, Spring.GetGroundHeight(x, z), z, 0, t)
					if u then
						made = made + 1
						local tx, tz = spot()
						Spring.GiveOrderToUnit(u, CMD.MOVE, { tx, Spring.GetGroundHeight(tx, tz), tz }, 0)
					end
				end
				for k = 1, math.floor(n / 8) do
					local x, z = spot()
					if Spring.CreateUnit(CLUTTER_BUILDINGS[k % #CLUTTER_BUILDINGS + 1], x, Spring.GetGroundHeight(x, z), z, 0, t) then
						made = made + 1
					end
				end
			end
			return made
		end,
		snapshot = function()
			for _, u in ipairs(Spring.GetAllUnits()) do preexisting[u] = true end
			return 0
		end,
		-- all = 1: everything the test made, including clutter; else only spawnGroup's units
		clear = function(all)
			for _, u in ipairs(Spring.GetAllUnits()) do
				if not preexisting[u] and (all == 1 or grouped[u]) then Spring.DestroyUnit(u, false, true) end
			end
			grouped = {}
			return 0
		end,
		-- a compact group of units around (cx, cz); returns their ids, comma separated
		spawnGroup = function(team, defName, n, cx, cz)
			local ids = {}
			for i = 0, n - 1 do
				local x, z = cx + (i % 4) * 40 - 60, cz + math.floor(i / 4) * 40 - 40
				local u = Spring.CreateUnit(defName, x, Spring.GetGroundHeight(x, z), z, 0, team)
				if u then ids[#ids + 1] = u; grouped[u] = true end
			end
			return table.concat(ids, ",")
		end,
	},
	run = function(ctx)
		if not debug or not debug.emulateMousePress then
			ctx.check("input_emulation_available", false, "debug.emulate* missing in this engine")
			return
		end
		if Spring.GetSpectatingState() then
			ctx.check("player_not_spectator", false, "UI tests need a playing player (run without --spectate)")
			return
		end
		local team = Spring.GetMyTeamID()
		local cx, cz = Game.mapSizeX * 0.5, Game.mapSizeZ * 0.5
		ctx.call("snapshot")
		if clutter and clutter > 0 then
			local enemy
			for _, t in ipairs(Spring.GetTeamList()) do
				if not Spring.AreTeamsAllied(t, team) and t ~= Spring.GetGaiaTeamID() then enemy = t break end
			end
			local made = ctx.call("spawnClutter", team, enemy or team, clutter)
			ctx.log("late-game clutter: " .. tostring(made) .. " units and buildings")
			ctx.waitSimFrames(60)
			-- the frame rate a player gets with this on the map (camera on the clear middle)
			ctx.window("lategame_frames", function() ctx.waitFrames(120) end)
		end
		Spring.SetCameraTarget(cx, Spring.GetGroundHeight(cx, cz), cz, 0)
		Spring.SetCameraState({ mode = 1, height = 1400 }, 0) -- overhead
		ctx.waitFrames(10)

		-- 1. box select a group with the whole drag inside one frame
		local csv = ctx.call("spawnGroup", team, "armpw", GROUP, cx, cz) or ""
		local group = {}
		for id in tostring(csv):gmatch("%d+") do group[#group + 1] = tonumber(id) end
		ctx.waitSimFrames(10)
		Spring.SelectUnitArray({})
		if stallMs then Spring.Workbench.SetFrameStall(stallMs) end
		ctx.waitFrames(5)
		-- start the drag well outside the group so the first-frame box selects nothing
		local x0, y0, x1, y1 = screenBox(group, 60)
		dragAcrossOneFrameBoundary(ctx, x0 - 120, y0 - 120, x1, y1, 1)
		ctx.waitFrames(6)
		local selected = {}
		for _, u in ipairs(Spring.GetSelectedUnits()) do selected[u] = true end
		local hit = 0
		for _, u in ipairs(group) do if selected[u] then hit = hit + 1 end end
		ctx.check("box_select_low_fps", hit == #group, hit .. "/" .. #group .. " units selected when the drag's end and release share a frame at ~8 fps")

		-- 2. shift drag-build a line of structures with the whole gesture inside one frame
		Spring.Workbench.SetFrameStall(0)
		ctx.call("clear")
		local bcsv = ctx.call("spawnGroup", team, "armck", 1, cx, cz) or ""
		local builder = tonumber(tostring(bcsv):match("%d+"))
		ctx.waitSimFrames(10)
		if not builder then
			ctx.check("drag_build_one_frame", false, "could not spawn a builder")
		else
			Spring.SelectUnitArray({ builder })
			ctx.waitFrames(3)
			Spring.SetActiveCommand("buildunit_armsolar")
			if stallMs then Spring.Workbench.SetFrameStall(stallMs) end
			ctx.waitFrames(5)
			local ax, ay = Spring.WorldToScreenCoords(cx - 300, Spring.GetGroundHeight(cx - 300, cz + 300), cz + 300)
			local bx, by = Spring.WorldToScreenCoords(cx + 300, Spring.GetGroundHeight(cx + 300, cz + 300), cz + 300)
			debug.emulateKeyPress(0x130) -- left shift (SDL1 keysym, as the engine expects)
			dragInOneFrame(ax, ay, bx, by, 1)
			debug.emulateKeyRelease(0x130)
			ctx.waitFrames(6)
			local queued = Spring.GetUnitCommandCount(builder) or 0
			ctx.check("drag_build_one_frame", queued >= 2, queued .. " build orders queued from a one-frame shift-drag at ~8 fps")
		end

		Spring.Workbench.SetFrameStall(0)
		debug.clearEmulatedInput()
		ctx.call("clear", 1)
	end,
}
end
