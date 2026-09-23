# BAR Test Workbench — Design

Date: 2026-09-23
Status: approved design, pending spec review

## Goal

A repeatable test bench for Beyond All Reason on the Recoil engine that:

1. Measures performance (frame time, sim time, draw time, per-subsystem timers) so two engine builds or two settings can be compared with numbers.
2. Checks game logic per unit type (weapon range, movement, core behaviours) and flags regressions.
3. Guards the low-FPS UI bugs fixed on `fix/lowfps-drag-select` (box select, drag-build).
4. Proves simulation determinism: replaying a recorded battle must reach exactly the same game state.

Benchmarks come first. An interactive in-game panel on top of the same scenarios is out of scope for this spec.

The bar for success is adoption: developers should reach for it by default because it is the fastest way to answer "did my change make anything slower or break any unit?".

## Developer experience requirements

- **One command**: `python tools/workbench/run.py --builds master,integration --suite smoke` runs, collects and opens the report. Sensible defaults for everything else (engine path discovery from the BAR data dir, default map, default profile).
- **Fast feedback tiers**: `smoke` (< 10 min), `standard` (< 45 min), `full` (overnight). Any single scenario or unit can be run on its own with `--only <pattern>`.
- **Actionable failures**: every failed check says what was expected, what happened, the unit/weapon/frame involved, and how to reproduce that single case (the exact `--only` command and the start script it used).
- **Trustworthy numbers**: repetitions with warm-up windows, medians and spread, and a "noise floor" note in the report so a 2% delta on a noisy metric is not flagged as a regression. Regressions are flagged only beyond both a relative threshold and the measured spread.
- **Report worth opening**: a single self-contained HTML page with a summary of regressions and improvements at the top, and per-scenario charts and per-unit tables below.
- **Easy to extend**: adding a scenario is one Lua file using `workbench_util`; per-unit checks cover new units automatically.

## Constraints

- Runs **windowed on the user's PC** with the real renderer (GPU required). Headless/CI runs are not a goal of v1, though scenario code must not depend on rendering unless it measures rendering.
- **No engine changes.** Everything lives in the BAR repo so any engine build (stock `master`, `perf/render-fixes`, `integration`, future releases) can be benchmarked and compared.
- Offline only: local host, `HostPort=0`, Lua AI or no AI.
- Reuse existing BAR test infrastructure: `luaui/Widgets/dbg_test_runner.lua`, `common/testing/*` (assertions, `SyncedRun` proxy, results/Mocha JSON reporter).

## Architecture

```
tools/workbench/                 (host side, Python 3, runs on Windows)
  run.py          matrix runner: builds x settings x scenarios -> launches spring.exe
  report.py       reads result JSON, writes compare.html
  settings/*.cfg  named settings profiles (low, default, high, shadows-off, ...)
  templates/      start-script template, report HTML template

luaui/Tests/workbench/           (in-game, run by dbg_test_runner)
  perf/           performance scenarios
  units/          per-unit-type behaviour scenarios (generated from UnitDefs)
  ui/             low-FPS input regression scenarios
  repro/          determinism record/replay scenarios

luaui/Widgets/dbg_workbench_metrics.lua   frame/profiler sampling, JSON writer
luarules/gadgets/dbg_workbench_statehash.lua  synced per-frame state hash (repro)
common/testing/workbench_util.lua         shared helpers (spawn grids, army setup, timing)
```

### Data flow

1. `run.py` takes a matrix: engine builds (paths to `spring.exe`), settings profiles, scenario patterns, repetitions.
2. For each cell it writes an isolated write-dir: `springsettings.cfg` from the profile, a start script from the template (offline, devmode, `testmode` modoption selecting the scenario pattern), links `games/BAR.sdd` and the map.
3. It launches `spring.exe --isolation --write-dir <dir> <startscript>` with a hard timeout.
4. In game, `dbg_test_runner` runs the selected scenarios. Scenarios call `workbench_util` to set up, then mark measurement windows; `dbg_workbench_metrics` samples during those windows.
5. Each scenario writes `testlog/workbench/<scenario>.json`. The engine exits when the run finishes.
6. `run.py` collects the JSON files (plus `infolog.txt` on failure) into `results/<timestamp>/<build>/<profile>/`.
7. `report.py` compares runs and writes a self-contained `compare.html` (tables and charts; deltas judged against the spread across repetitions, see Developer experience).

## Scenarios

### Performance (`perf/`)

| Scenario | Setup | Measures |
|---|---|---|
| `mass_move_{500,2000,5000}` | Grid of one ground unit type per side, move order across the map | sim ms/frame, pathing and move timers, frame time |
| `battle` | Two mirrored mixed armies ordered to fight | sim, weapons, projectiles, particles, draw |
| `render_sweep` | Fixed scene + scripted camera path, repeated per settings profile | frame time p50/p95/p99, draw timers |

The camera path is deterministic (fixed keyframes, fixed duration). Settings are applied by `run.py` through the profile, not by the scenario, so every render sweep runs identical Lua.

### Per-unit-type (`units/`)

Generated at runtime by iterating `UnitDefs` (skipping non-buildable, dummy and objective-only defs by filter list). Each check is its own test case named `<check>:<unitDefName>` so results are per unit.

- **Weapon range**: for each weapon, place a stationary target at `range - margin` and `range + margin`. Pass if the unit fires on the first (damage recorded via `UnitDamaged` callin) and not the second within a timeout. Weapon types that cannot target ground units (anti-air only, etc.) use a suitable target type.
- **Movement**: move order across flat terrain, up a slope and into water where the movedef allows. Pass if the unit arrives within `distance / maxSpeed * slack`, never exceeds `maxSpeed * tolerance`, and isn't stuck (position unchanged for N seconds while ordered).
- **Core behaviours** (by capability flags): builders build a structure; factories produce a unit; transports load and unload; aircraft take off and land; cloakers cloak and are not visible to an enemy observer; radar and jammer affect enemy radar coverage.
- **Per-unit cost**: spawn N of one type, idle and then moving; record sim ms and draw ms per unit to spot outliers.

### UI regression (`ui/`)

Uses the engine's input emulation (`debug.emulateKey*` / emulated mouse buttons used by the test runner) with an artificially lowered frame rate (a busy-loop widget that stalls each draw frame to about 8 fps):

- Box-select a known group with press, drag and release inside two frames. Expect exactly that group selected.
- Shift-drag build a line of structures, then release the mouse before Shift in the same frame. Expect a queued line of the right length.

### Reproducibility (`repro/`)

- `dbg_workbench_statehash` (synced gadget) folds every unit and feature's id, defID, position, health, build progress, command queue length, and team resources into a 64-bit hash every frame, and appends `frame,hash` to a file every 30 frames plus the final frame.
- Record phase: run `battle` with a fixed seed and record the demo.
- Replay phase: `run.py` replays the demo on the same or another build with the gadget active.
- Compare: identical hash sequences mean pass; otherwise the report shows the first diverging frame and the unit fields that differ (the gadget also dumps per-unit state at the first divergence frame when given the expected hash file).

## Metrics

`dbg_workbench_metrics` samples during marked windows:

- frame time per draw frame (from `Spring.GetFrameTimer` deltas) → p50/p95/p99/max
- sim frame time and count (from `GetProfilerTimeRecord` on the engine's timer names; names discovered via `GetProfilerRecordNames`)
- selected per-subsystem timers (Sim::Path, Sim::Los, Sim::Unit::Weapon, Draw::World::*, Lua) as mean and p95
- unit and projectile counts, Lua memory

JSON schema per scenario: `{ scenario, build: {engineVersion, gameVersion, branch?}, profile, repetition, windows: [{name, frames, frameTimeMs:{p50,p95,p99,max}, timers:{name:{meanMs,p95Ms}}, counts:{...}}], checks: [{name, pass, detail}] }`.

## Error handling

- Hard timeout per engine launch in `run.py`. On timeout or crash the cell is recorded as `error` with the tail of `infolog.txt`, and the matrix continues.
- Per-scenario timeouts inside the runner (`dbg_test_runner`'s existing mechanism). A scenario failure marks that scenario failed without stopping the others.
- Settings profiles are validated before launch (unknown keys are reported, not silently ignored).

## Testing the workbench itself

- `workbench_util` and the report's statistics have unit tests (Lua selftests, Python `unittest`).
- A smoke matrix (1 build × 1 profile × `mass_move_500` + 3 unit types + repro on 600 frames) must complete in under 10 minutes and is the acceptance check for each phase.

## Phasing

1. Runner (`run.py`, profiles, start-script template), metrics widget, `mass_move_*`, weapon-range checks, JSON output, minimal `report.py`.
2. `battle`, `render_sweep`, movement, core behaviours, per-unit cost, full HTML report.
3. UI regression scenarios and reproducibility (state hash gadget, record/replay, divergence report).

## Out of scope

Interactive panel; headless/CI execution; engine-side instrumentation; network/multiplayer scenarios.
