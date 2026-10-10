# Community PRs: review log

Open upstream PRs (game and lobby) reviewed for this fork, so later passes only look at new ones. Policy: "What gets in" in the [README](../README.md). Carried PRs are the `Merge PR #N` commits on `master`.

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
