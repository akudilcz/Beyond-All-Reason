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
local START_FRAME = 4096
local RUN_FRAMES = 3000
local SPEED = 20

return {
	name = "sync_repro",
	timeout = 900,
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

		local done = ctx.waitUntil(function() return Spring.GetGameFrame() > START_FRAME + RUN_FRAMES + 30 end, 800)
		Spring.SendCommands("setminspeed 1", "setmaxspeed 1")
		ctx.check("battle_ran", done, "reached frame " .. Spring.GetGameFrame())

		local written = ctx.waitUntil(function() return VFS.FileExists("synctest_synchash.json", VFS.RAW) end, 10)
		ctx.check("checksums_written", written, "synctest_synchash.json in the write dir")
	end,
}
