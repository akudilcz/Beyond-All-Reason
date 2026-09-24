-- Late-game simulation load, headless-friendly: the same ~6,750 units and buildings as
-- ui_lategame, both teams roaming the map, measured for 90 sim seconds with idle units
-- sent on again every 20 s. By default they hold fire (movement load); with
-- --filter fight they fight with 1e6 health (steady combat load). Profile with
-- tools/workbench/profile.sh.
local lategame = VFS.Include("workbench/lib/lategame.lua")

local N = 3000
local CLEAR_RADIUS = 900
local SIM_SECONDS = 90

local preexisting = {}

return {
	name = "lategame_load",
	timeout = 600,
	synced = {
		snapshot = function()
			for _, u in ipairs(Spring.GetAllUnits()) do preexisting[u] = true end
			return 0
		end,
		-- fight = 1: units shoot (with 1e6 health, so the map stays full): steady combat load
		spawn = function(team, enemy, fight)
			local f = tonumber(fight) == 1
			return lategame.spawn(team, enemy, N, CLEAR_RADIUS, not f, f)
		end,
		roam = function(team, enemy)
			return lategame.roam(team, enemy, CLEAR_RADIUS)
		end,
		clear = function()
			for _, u in ipairs(Spring.GetAllUnits()) do
				if not preexisting[u] then Spring.DestroyUnit(u, false, true) end
			end
			return 0
		end,
	},
	syncedCallins = {
		GameFrame = function(frame)
			if frame % 15 == 0 then lategame.heal() end
		end,
	},
	run = function(ctx)
		local team = Spring.GetMyTeamID()
		local enemy
		for _, t in ipairs(Spring.GetTeamList()) do
			if not Spring.AreTeamsAllied(t, team) and t ~= Spring.GetGaiaTeamID() then enemy = t break end
		end
		ctx.call("snapshot")
		-- run.py --filter fight (the config is only readable unsynced, so it is passed along)
		local fight = ctx.wants("fight") and not ctx.wants("move") and 1 or 0
		local made = tonumber(ctx.call("spawn", team, enemy or team, fight)) or 0
		ctx.check("spawned", made >= N * 2, made .. " units and buildings")
		-- the first seconds: every unit asks for a path at once
		ctx.window("lategame_start", function() ctx.waitSimSeconds(10) end)
		ctx.window("lategame_steady", function()
			for _ = 1, SIM_SECONDS / 20 do
				ctx.waitSimSeconds(20)
				ctx.call("roam", team, enemy or team)
			end
		end)
		local alive = 0
		for _, t in ipairs({ team, enemy or team }) do alive = alive + #Spring.GetTeamUnits(t) end
		ctx.check("still_running", alive > N, alive .. " units alive after " .. SIM_SECONDS .. " s")
		ctx.call("clear")
	end,
}
