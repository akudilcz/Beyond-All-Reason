local widget = widget ---@type Widget

--------------------------------------------------------------------------------
-- Drag trace: records everything Lua can see about a left-button drag, to find
-- out why box selects and shift-drag build lines end before the physical
-- release in late-game (low FPS) play.
--
-- The widget is always loaded and always records into a small ring buffer, so
-- the drag that just went wrong is captured before the trace is switched on.
-- Live logging is off until requested:
--
--   /dragtrace         toggle live logging; switching it on first dumps the
--                      ring buffer (the last DRAG_TRACE_BUFFER events)
--   /dragtrace on|off  set live logging explicitly
--   /dragtrace dump    dump the ring buffer without changing live logging
--
-- Every line goes to infolog.txt prefixed "[dragtrace]", so
-- `grep dragtrace infolog.txt` gives the whole trace. The widget never takes
-- mouse ownership (MousePress returns false), so it cannot itself change what
-- the engine does with the drag.
--
-- What each line means:
--   PRESS       widget:MousePress for LMB. "chord=" shows whether RMB/MMB were
--               already held (the engine never draws a box or click-selects
--               for a chorded press). "dup=1" means a second LMB press arrived
--               while a drag was in progress with no release in between: the
--               engine then marks the press chorded and restarts the drag.
--   RELEASE     Spring.GetMouseState LMB went true -> false, with drag length,
--               frames and whether a box existed on the previous frame.
--   BOX VANISH  the engine stopped reporting a selection box while LMB was
--               still held (chorded press, Rml capture, draw mode, FPS mode).
--   KEYUP       a modifier key release delivered while LMB was held. On window
--               focus loss the engine synthesises a release for every held
--               key and mouse button in the same batch; a KEYUP burst next to
--               a RELEASE with no physical key release points at that path.
--   SHIFT       KeyInput's modifier snapshot (GetModKeyState) disagrees with
--               the live key state (GetKeyState) while LMB is held.
--   CMD         the active command changed while LMB was held (a widget
--               swapped or cleared the build command mid drag).
--   STALL       a frame longer than STALL_SECONDS (>= 5 s is what makes the
--               window manager on Linux, and Windows, take focus from the app).
--   OFFSCREEN   the engine's offscreen flag flipped (pointer left/entered the
--               window).
--   RMB STUCK   RMB reported held for more than RMB_STUCK_SECONDS (a lost RMB
--               release makes every later LMB press chorded until RMB is
--               clicked again).
--------------------------------------------------------------------------------

function widget:GetInfo()
	return {
		name = "Drag trace (debug)",
		desc = "Records the LMB drag lifecycle; /dragtrace logs it to infolog.txt to diagnose drags ending early",
		author = "Andrew Kudilczak",
		date = "September 2026",
		license = "GNU GPL, v2 or later",
		layer = -1000000,
		enabled = true,
		handler = true,
	}
end

local spGetMouseState = Spring.GetMouseState
local spGetSelectionBox = Spring.GetSelectionBox
local spGetModKeyState = Spring.GetModKeyState
local spGetKeyState = Spring.GetKeyState
local spGetActiveCommand = Spring.GetActiveCommand
local spGetSelectedUnitsCount = Spring.GetSelectedUnitsCount
local spGetGameFrame = Spring.GetGameFrame
local spGetTimer = Spring.GetTimer
local spDiffTimers = Spring.DiffTimers
local spEcho = Spring.Echo

local KEY_LSHIFT, KEY_RSHIFT = 304, 303
local KEY_LCTRL, KEY_RCTRL = 306, 305
local KEY_LALT, KEY_RALT = 308, 307
local MOD_KEYS = {
	[KEY_LSHIFT] = "lshift", [KEY_RSHIFT] = "rshift",
	[KEY_LCTRL] = "lctrl", [KEY_RCTRL] = "rctrl",
	[KEY_LALT] = "lalt", [KEY_RALT] = "ralt",
}

local STALL_SECONDS = 0.25
local RMB_STUCK_SECONDS = 5
local DRAG_TRACE_BUFFER = 400

local live = false
local ring = {}      -- ring buffer of formatted lines
local ringNext = 1   -- next slot to write
local ringCount = 0

local startTimer = spGetTimer()
local prev = {
	lmb = false, rmb = false, mmb = false, offscreen = false,
	hasBox = false, box = nil,
	activeCmd = nil, shiftSnap = false, shiftLive = false,
}
local drag = nil -- { t0, x0, y0, frames, hadBox, presses }
local rmbDownSince = nil
local rmbStuckLogged = false

local function now()
	return spDiffTimers(spGetTimer(), startTimer)
end

local function record(fmt, ...)
	local line = string.format("[dragtrace] t=%.3f gf=%d " .. fmt, now(), spGetGameFrame(), ...)
	ring[ringNext] = line
	ringNext = (ringNext % DRAG_TRACE_BUFFER) + 1
	if ringCount < DRAG_TRACE_BUFFER then
		ringCount = ringCount + 1
	end
	if live then
		spEcho(line)
	end
end

local function dumpRing()
	spEcho(string.format("[dragtrace] ---- dump of the last %d recorded events ----", ringCount))
	local first = (ringCount < DRAG_TRACE_BUFFER) and 1 or ringNext
	for i = 0, ringCount - 1 do
		spEcho(ring[((first - 1 + i) % DRAG_TRACE_BUFFER) + 1])
	end
	spEcho("[dragtrace] ---- end of dump ----")
end

local function setLive(enable)
	if enable and not live then
		dumpRing()
	end
	live = enable
	spEcho("[dragtrace] live logging " .. (live and "ON" or "OFF"))
end

local function handleDragTrace(_, _, words)
	local arg = words[1]
	if arg == "on" then
		setLive(true)
	elseif arg == "off" then
		setLive(false)
	elseif arg == "dump" then
		dumpRing()
	elseif arg == nil then
		setLive(not live)
	else
		spEcho("[dragtrace] usage: /dragtrace [on|off|dump]")
	end
	return true
end

local function b(v)
	return v and 1 or 0
end

local function boxStr(box)
	if not box then
		return "box=nil"
	end
	return string.format("box=%d,%d-%d,%d", box[1], box[2], box[3], box[4])
end

function widget:Initialize()
	widgetHandler:AddAction("dragtrace", handleDragTrace, nil, "t")
	record("initialized; view=%dx%d", Spring.GetViewGeometry())
end

function widget:Shutdown()
	widgetHandler:RemoveAction("dragtrace", "t")
end

function widget:MousePress(x, y, button)
	if button == 1 then
		local _, _, _, mmb, rmb = spGetMouseState()
		local alt, ctrl, _, shift = spGetModKeyState()
		local dup = (drag ~= nil)
		record("PRESS lmb x=%d y=%d chord(rmb=%d mmb=%d) mods(a=%d c=%d s=%d) dup=%d cmd=%s",
			x, y, b(rmb), b(mmb), b(alt), b(ctrl), b(shift), b(dup), tostring(spGetActiveCommand()))
		if dup then
			drag.presses = drag.presses + 1
		else
			drag = { t0 = now(), x0 = x, y0 = y, frames = 0, hadBox = false, presses = 1 }
		end
	elseif button == 3 then
		local alt, ctrl, _, shift = spGetModKeyState()
		record("PRESS rmb x=%d y=%d mods(a=%d c=%d s=%d) lmbHeld=%d", x, y, b(alt), b(ctrl), b(shift), b(prev.lmb))
	end
	return false
end

function widget:KeyRelease(key, mods)
	local name = MOD_KEYS[key]
	if name and prev.lmb then
		record("KEYUP %s while lmb held; mods(a=%d c=%d s=%d) liveKeyState=%d", name,
			b(mods.alt), b(mods.ctrl), b(mods.shift), b(spGetKeyState(key)))
	end
	return false
end

function widget:Update(dt)
	local t = now()

	if dt > STALL_SECONDS then
		record("STALL dt=%.3fs lmb=%d", dt, b(prev.lmb))
	end

	local mx, my, lmb, mmb, rmb, offscreen = spGetMouseState()
	local x1, y1, x2, y2 = spGetSelectionBox()
	local hasBox = (x1 ~= nil)
	local alt, ctrl, _, shiftSnap = spGetModKeyState()
	local shiftLive = spGetKeyState(KEY_LSHIFT) or spGetKeyState(KEY_RSHIFT)
	local activeCmd = spGetActiveCommand()

	if offscreen ~= prev.offscreen then
		record("OFFSCREEN=%d lmb=%d x=%d y=%d", b(offscreen), b(lmb), mx, my)
	end

	if lmb and not prev.lmb and drag == nil then
		-- the engine saw a press that no widget:MousePress reported (Rml or a
		-- receiver consumed it before Lua); still track it
		record("LMB DOWN (no PRESS callin) x=%d y=%d", mx, my)
		drag = { t0 = t, x0 = mx, y0 = my, frames = 0, hadBox = false, presses = 0 }
	end

	if lmb then
		if drag then
			drag.frames = drag.frames + 1
			if hasBox then
				drag.hadBox = true
			end
		end
		if prev.hasBox and not hasBox then
			record("BOX VANISH while lmb held: x=%d y=%d dt=%.3f prev %s mods(a=%d c=%d s=%d) cmd=%s",
				mx, my, dt, boxStr(prev.box), b(alt), b(ctrl), b(shiftSnap), tostring(activeCmd))
		end
		if shiftSnap ~= shiftLive and (prev.shiftSnap ~= shiftSnap or prev.shiftLive ~= shiftLive) then
			record("SHIFT snapshot=%d live=%d while lmb held", b(shiftSnap), b(shiftLive))
		end
		if activeCmd ~= prev.activeCmd then
			record("CMD changed while lmb held: %s -> %s", tostring(prev.activeCmd), tostring(activeCmd))
		end
	elseif prev.lmb then
		local d = drag or { t0 = t, x0 = -1, y0 = -1, frames = 0, hadBox = false, presses = 0 }
		record("RELEASE x=%d y=%d from %d,%d len=%.3fs frames=%d presses=%d hadBox=%d boxLastFrame=%d dt=%.3f selected=%d mods(a=%d c=%d s=%d) cmd=%s",
			mx, my, d.x0, d.y0, t - d.t0, d.frames, d.presses, b(d.hadBox), b(prev.hasBox), dt,
			spGetSelectedUnitsCount(), b(alt), b(ctrl), b(shiftSnap), tostring(activeCmd))
		drag = nil
	end

	if rmb then
		if not rmbDownSince then
			rmbDownSince = t
			rmbStuckLogged = false
		elseif not rmbStuckLogged and (t - rmbDownSince) > RMB_STUCK_SECONDS then
			record("RMB STUCK: reported held for %.1fs (every lmb press is chorded until rmb is re-clicked)", t - rmbDownSince)
			rmbStuckLogged = true
		end
	else
		if rmbStuckLogged then
			record("RMB released after %.1fs", t - rmbDownSince)
		end
		rmbDownSince = nil
	end

	prev.lmb, prev.rmb, prev.mmb, prev.offscreen = lmb, rmb, mmb, offscreen
	prev.hasBox = hasBox
	prev.box = hasBox and { x1, y1, x2, y2 } or prev.box
	prev.activeCmd = activeCmd
	prev.shiftSnap, prev.shiftLive = shiftSnap, shiftLive
end
