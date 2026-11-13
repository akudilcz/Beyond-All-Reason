# Community PRs: review log

Open upstream PRs (game and lobby) reviewed for this fork, so later passes only look at new ones. Policy: "What gets in" in the [README](../README.md). Carried PRs are the `Merge PR #N` commits on `master`.

## 2026-11-13

Reviewed: open, non-draft PRs updated since 2026-10-25 that weren't reviewed in the last round, skipping the Mission API, new units and hats.

Merged: #9998 (Legacy build keys keep cycling after Context Build swaps a building). Ported upstream's follow-up to our carried #9214 (b037940baf: Set Target needs a targetable weapon, factories don't count as repairers; spec fixture moved into our SpecEnv setup).

Skipped:

| PR | Why |
|---|---|
| #10080, #10077, #10051, #10050, #10049, #10048, #10047, #10002, #9874, #9873, #9859, #7149 | Mission API |
| #10084 | Scout aim scripts change aiming (sim); conflicts after #10085 |
| #9756 | Recompiles 846 bos files; conflicts after #10085 |
| #10075 | Restores terrain under surviving buildings on a poll (sim change), 400 lines |
| #10011 | Changes unit-cap transfer on share/take (rule change); author unsure |
| #9838, #9801, #9775, #9245, #9913 | Gameplay or balance |
| #9964 | Maintainer wants one selection-volume convention first (issue #9992) |
| #9996 | Changes drag-input behaviour; one of two designs, unreviewed; overlaps the drag code under investigation |
| #9215 | Selection-caching rework across 16 files; conflicts with our #9214/#9787 |
| #9467 | Conflicts in `barwidgets.lua`; overlaps #9655 |
| #9676 | Depends on an unmerged engine PR and a submodule bump; CI failing |
| #8797 | On hold over an engine heading bug; conflicts |
| #9294 | Removes widgets |
| #10001, #9868, #9096, #9093, #8560, #8253, #7485, #7399 | Features |
| #10041, #9935, #9924, #9880, #9869, #9524, #9392, #9142, #9129, #8527, #8207, #7622 | Changes requested |
| #9804, #9545, #9819, #9793, #9803, #9484, #9541, #9555 | Reviewed in earlier rounds, not materially changed |

Lobby (BYAR-Chobby): #1276 skipped (changes requested).

## 2026-10-25

Reviewed: open, non-draft PRs updated since 2026-10-10 that weren't reviewed in the last round, skipping the Mission API, new units and hats.

Merged: #9827 (radar circles stay visible when zoomed out), #9792 (building ground AO no longer shows through slopes), #9818 (alt set target works with the no-ground variant and re-sends only changed target lists), #9787 (alt-drag area filter keeps the aircraft under the cursor; its spec adapted to SpecEnv, our #9214 filter and #9047).

Superseded upstream since the last round: #9619 (Rampart wreck) and the #9548 options fix; both conflicts took upstream's version.

Skipped:

| PR | Why |
|---|---|
| #9804 | Changes where right-click quick mex places the mex (control change) |
| #9545, #9565 | Pregame insertion and Area Mex insertion: features, 500 to 1,600 lines |
| #9791 | Recompiles 172 unit scripts and changes hit tilt, which moves pieces (sim) |
| #9805, #9819, #9730, #9821, #9808, #9793 | Weapon aim, targeting, volumes or unit stats: gameplay or balance |
| #9803, #9484 | New target-priority and interceptor behaviour (gameplay) |
| #9541, #8935, #9555, #9506 | Changes requested |

Lobby (BYAR-Chobby): #1276 skipped (changes requested).

## 2026-10-10

Merged: #9619 (Rampart wreck), #9584 (keybind editor key names), #9527 (autogroup numbers after construction), #9497 ("guarding" select filter), #9405 (geothermal ruins on scripted-geo maps), #9321 (cone light flicker), #8140 (Commando aiming script), and commit 5c60367c33 from #9548 (options error with the old user squad widget).

Skipped:

| PR | Why |
|---|---|
| #9590 | Adds `maxrange` to 16 unit defs: changes approach range for every order (a stat change) |
| #9548 (rest) | Changes default squad keybinds |
| #9472 | Author: "needs testing in case it's crashy"; unreviewed |
| #9465 | Stockpile bar redesign awaiting UX review |
| #9460 | Changes what the no-nukes option blocks (rule change), maintainer objection |
| #9402 | Torpedo sound range affects gameplay; final tuning differs |
| #9320 | Critter companion design still under discussion |
| #9530 | Test-harness support for follow-up PRs we don't take |
| #9047 | Changes requested; changes Ctrl behaviour for area attack |
| #8736 | Adds a per-frame projectile-moving gadget; reviewer holding it |

Lobby (BYAR-Chobby), all skipped: #1231 (chat box rewrite, conflicts, maintainer flagged inaccuracies), #1233 (reset-widgets button deletes settings; maintainer objections), #1152 (reported to stop the rejoin popup appearing).
