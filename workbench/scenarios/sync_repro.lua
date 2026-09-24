-- Simulation determinism: runs BAR's seeded synctest battle (dbg_synctest, the same
-- one RecoilEngine's sync CI uses) starting at a fixed absolute frame, and lets it
-- write per-frame sync checksums to synctest_synchash.json. The workbench runner
-- collects that file per cell and the report compares the checksum streams across
-- engines: two builds that claim identical simulation must produce identical streams.
--
-- Run it on its own and with a fixed seed so nothing else perturbs the synced state:
--   run.py --only sync_repro --seed 1234 --engine base=... --engine dev=...
--
-- Frame 4096 is where the engine resets its running sync checksum, so the measured
-- window starts clean regardless of what happened before it.
--
-- It also records a game-state digest every DIGEST_EVERY frames (all units' ids, types,
-- exact positions and health). Sync checksums count every synced write, including ones
-- undone in the same frame (a weapon test turning its unit and back), so an optimisation
-- that skips such work changes the checksums without changing the game; the state
-- digests tell those apart from real differences.
local START_FRAME = 4096
local RUN_FRAMES = 3000
local SPEED = 20
local DIGEST_EVERY = 100

-- synced: "frame:digest" strings
local digests = {}

-- exact and platform-independent: %.9g round-trips a float32, the hash stays below 2^53
local function stateDigest()
	local units = Spring.GetAllUnits()
	table.sort(units)
	local h = #units
	for _, u in ipairs(units) do
		local x, y, z = Spring.GetUnitPosition(u)
		local hp = Spring.GetUnitHealth(u)
		local line = string.format("%d %d %.9g %.9g %.9g %.9g", u, Spring.GetUnitDefID(u) or -1, x or 0, y or 0, z or 0, hp or 0)
		for i = 1, #line do
			h = (h * 31 + line:byte(i)) % 2147483629
		end
	end
	return string.format("%d", h)
end

return {
	name = "sync_repro",
	timeout = 2400,
	synced = {
		digests = function()
			return table.concat(digests, ",")
		end,
	},
	syncedCallins = {
		GameFrame = function(frame)
			if frame >= START_FRAME and frame <= START_FRAME + RUN_FRAMES and (frame - START_FRAME) % DIGEST_EVERY == 0 then
				digests[#digests + 1] = frame .. ":" .. stateDigest()
			end
		end,
	},
	run = function(ctx)
		if not Platform.hasSyncChecksums then
			ctx.check("sync_checksums_available", false, "engine built without SYNCCHECK")
			return
		end
		-- dbg_synctest only accepts runs with cheats enabled (or devhelper permissions)
		if not Spring.IsCheatingEnabled() then
			Spring.SendCommands("cheat")
			ctx.waitUntil(function() return Spring.IsCheatingEnabled() end, 10)
		end
		Spring.SendCommands("setmaxspeed " .. SPEED, "setminspeed " .. SPEED)

		-- totalFrames areaFraction offsetX offsetZ unitMultiplier startFrame
		Spring.SendLuaRulesMsg(string.format("$st$:synctest %d 0.5 0.25 0.25 1 %d", RUN_FRAMES, START_FRAME))

		local done = ctx.waitUntil(function() return Spring.GetGameFrame() > START_FRAME + RUN_FRAMES + 30 end, 2300)
		Spring.SendCommands("setminspeed 1", "setmaxspeed 1")
		ctx.check("battle_ran", done, "reached frame " .. Spring.GetGameFrame())

		local written = ctx.waitUntil(function() return VFS.FileExists("synctest_synchash.json", VFS.RAW) end, 10)
		ctx.check("checksums_written", written, "synctest_synchash.json in the write dir")

		-- compared across engines by the report ("game state vs baseline")
		local d, err = ctx.call("digests")
		ctx.check("state_digests", d ~= nil and d ~= "", d or err)
	end,
}
