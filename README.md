# Beyond All Reason, tuned and tested

**The game half of a BAR variant that plays smoother in big battles, keeps its controls working when the frame rate drops, and is checked unit by unit by a testbench that plays the game for you.**

Pairs with the engine fork [akudilcz/RecoilEngine](https://github.com/akudilcz/RecoilEngine), which has the full story: performance patches, fixes and the Recoil Workbench. Built on upstream [Beyond All Reason](https://github.com/beyond-all-reason/Beyond-All-Reason) and kept level with it.

## For players

- **Box selection that works in huge battles.** With hundreds of units and a low frame rate, dragging a selection box could select nothing, because the whole drag landed in one frame. SmartSelect now uses the final box when you release.
- **Drag-building that works at low FPS.** Shift-dragging a row of buildings works again when the game is struggling (the fix is in the engine fork; use both together).
- **Community fixes upstream hasn't merged yet**, each reviewed first. For example #9214 (area commands only target units that can carry them out), #9331 (geothermal vents some maps place twice) and #8076 (partly translated languages fall back to English per line instead of showing blanks).
- **Same balance, same controls.** No unit stats or default keybindings are changed.

There are no prebuilt downloads yet; see the engine fork for building and running it.

## For developers

**Every unit, checked every run.** The `workbench/` scenario pack drives the engine's Recoil Workbench with checks generated from the unit definitions, so new units are covered automatically:

| Scenario | What it checks | Cases |
|---|---|---|
| `unit_movement`, `ship_movement` | every ground unit, ship and submarine arrives within budget and never exceeds its max speed | 450 |
| `weapon_range_all` | every armed ground unit hits inside its range, and nothing it fires lands beyond its reach | 238 |
| `air_attack` | every armed aircraft reaches and strikes a target | 18 |
| `unit_behaviours` | every factory produces, every builder builds; transport, cloak, radar | 41 |
| `ui_lowfps` | box select and drag-build with the whole gesture inside one ~8 fps frame | 2 |
| `mass_move_*`, `big_battle`, `sync_repro` | performance at 500 to 5,000 units, and bit-identical replays | |

All 747 logic checks run in about 3.5 minutes at up to 30x game speed, on a flat arena so they measure the unit, not the map. Failures say what happened, e.g. *"took 0 damage: weapon idle, target in range, line of fire blocked"*. Writing your own scenario takes one Lua file; see the engine fork's [workbench guide](https://github.com/akudilcz/RecoilEngine/blob/master/tools/workbench/README.md).

**The Lua specs run locally** with busted (`busted --lua=lua5.1` from the repo root), or together with the engine's tests via the engine fork's `tools/workbench/test-all.sh`.

## What gets in

Low-to-medium-risk bug fixes, performance work and small UX improvements, each reviewed first. No rewrites of core systems, and no balance or default-control changes. `origin` is upstream and `fork` is this repository; we sync with `git fetch origin && git merge origin/master`.

---

# Beyond-All-Reason

![Discord](https://img.shields.io/discord/225695362004811776)

Open source RTS game built on top of the Recoil RTS Engine

## Where to download

https://www.beyondallreason.info/download

## How to play

https://www.beyondallreason.info/guides

## Development Quick Start

Beyond All Reason (BAR), consists of 2 primary components, the lobby (Chobby - https://github.com/beyond-all-reason/BYAR-Chobby) and the game code itself (this repository).

The game runs on top of the Recoil engine <https://github.com/beyond-all-reason/RecoilEngine>.

In order to develop the game (this repository) you first need a working install of the lobby/launcher. There are 2 ways to do this:

1. [Download the full BAR application](https://www.beyondallreason.info/download#How-To-Install) from the website and run it. This is probably what you will have done if you have previously installed and played the game.

2. OR if you want to develop the lobby client, follow [the guide in the Chobby README](https://github.com/beyond-all-reason/BYAR-Chobby#developing-the-lobby). First download a [release of Chobby](https://github.com/beyond-all-reason/BYAR-Chobby/releases) and then launch Chobby, this will automatically download and install the engine and other dependencies.

Once you have a working install of BAR you need a local development copy of the game code to work with. This code will live in the BAR install directory.

1. To find the BAR install directory simply open the launcher (not full game) and click the "Open install directory" button. This is one of the 3 buttons (`Toggle log` and `Upload log` are the other 2). For Windows installs this might be your user's `AppData/Local/Programs/Beyond-All-Reason/data` directory, for Linux it might be your user's `.local/state/Beyond All Reason/` directory.

2. In the BAR install directory create the empty file `devmode.txt`. E.g: `AppData/Local/Programs/Beyond-All-Reason/data/devmode.txt` or `.local/state/Beyond All Reason/devmode.txt`.

3. In the BAR install directory (inside the `data` folder on Windows) in the `games` sub-directory (create `games` if it doesn't exist) clone the code for this repository into a directory with a name ending in `.sdd`. For example:

```
git clone --recurse-submodules https://github.com/beyond-all-reason/Beyond-All-Reason.git BAR.sdd
```

Ensure that you have the correct path by looking for the file `Beyond-All-Reason/data/games/BAR.sdd/modinfo.lua` on Windows, or `.local/state/Beyond All Reason/games/BAR.sdd/modinfo.lua` on Linux.

4. Now you have the game code launch the full game from the launcher as normal. Then go to `Settings > Developer > Singleplayer` and select `Beyond All Reason Dev`.

5. Now you can launch a match normally through the game UI. This match will use the dev copy of the LUA code which is in `BAR-install-directory/data/games/BAR.sdd`.

6. If developing Chobby also clone the code into the `games` directory. Follow the guide in the [Chobby README](https://github.com/beyond-all-reason/BYAR-Chobby#developing-the-lobby).

7. (Optional, Advanced) If you want to run automated integration tests, see the [testing documentation](tools/headless_testing/README.md)

More on the `.sdd` directory to run raw LUA and the structure expected by Spring Engine is [documented here](https://springrts.com/wiki/Gamedev:Structure).

---

## Automated Testing

### Prereqs

**Lua 5.1**

_debian/linux_

```zsh
sudo apt install -y lua5.1
```

_windows_ (MSYS2 UCRT64)

```zsh
pacman -S --needed mingw-w64-ucrt-x86_64-lua51
```

_macOS_

```zsh
brew install lua@5.1
```

**Lux Package Manager**
Follow the [Lux Getting Started Guide](https://lux.lumen-labs.org/tutorial/getting-started/).

Or follow the Cargo instructions to manually build [on the Lux Github](https://github.com/lumen-oss/lux?tab=readme-ov-file#wrench-building-from-source)

### Install Project Packages

From the repo root (where `lux.toml` lives):

```zsh
lux --max-jobs=2 update
```
Note: in my testing `--max-jobs` was super specific to my machine and anything above that number would sometimes cause deadlocks.


### Running Tests

Run the full suite (via [Busted](https://lunarmodules.github.io/busted/)):

```zsh
# preferred for predictable CLI behavior
busted
```

Filter by tag:

```zsh
busted -t focus
```

Optionally, run through Lux’s wrapper:

```zsh
lx test
# run the emmylua type check
lx check
# or to drop into a shell so you can run `busted` manually
lx shell --test
busted
8 successes / 0 failures / 0 errors / 0 pending : 0.246881 seconds
```

See Lux [Guides](https://lux.lumen-labs.org/guides/formatting-linting) for more information.

Inspect objects inline while debugging:

```lua
print(VFS.Include("inspect.lua")(someObject))
```

### VS Code Test Switcher (optional)

This handy plugin lets you switch between the test and the code-being-tested just by tapping `Cmd+Shift+Y`.

VSCode Plugin: https://marketplace.visualstudio.com/items?itemName=bmalehorn.test-switcher

Then open **User Settings (JSON)** and add:

```json
"test-switcher.rules": [
    {
        "pattern": "spec/(.*)_spec\\.lua",
        "replacement": "$1.lua"
    },
    {
        "pattern": "spec/builder_specs/(.*)_spec\\.lua",
        "replacement": "spec/builders/$1.lua"
    },
    {
        "pattern": "spec/builders/(.*)\\.lua",
        "replacement": "spec/builder_specs/$1_spec.lua"
    },
    {
        "pattern": "(luarules|common|luaui|gamedata)/(.*)\\.lua",
        "replacement": "spec/$1/$2_spec.lua"
    }
],
```
