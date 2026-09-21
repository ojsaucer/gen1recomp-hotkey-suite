# Changelog

## [1.10.0] - 2026-09-20

### Added

- **Gen 2 support (Gold / Silver / Crystal).** The suite now loads and runs on
  a Gen 2 boot alongside Gen 1, with the same modules, the same settings and
  the same bindings. Gold is a second engine beside Red rather than a skin over
  it, so the battle modules no longer read the battle's internals directly:
  every phase, message and ball read now goes through one adapter that probes
  for the capability it needs instead of asking which game is running.
  - The move list is `moveSelect` on Red and `moves` on Gold; the command menu
    is `menu` on both.
  - Red parks on a battle message by raising a flag, Gold by holding a frame
    count that only a button clears. AUTO TEXT reads both.
  - The level-up stats window is a screen pushed over the battle on Red and a
    phase on the battle itself on Gold. LEVEL UP advances both.
  - Gold runs the whole learn-a-move flow as phases rather than pushed boxes.
    LEARN TEXT pages its preamble and, as on Red, never touches the
    forget-a-move decision itself.
  - SKIP LV SFX releases Gold's sound hold for the level-up fanfare and the
    exp bar. The caught-a-mon jingle shares that same field and is left alone.
  - The ball menu throws through Gold's own item path, which spends the ball
    itself, and reads the BALL pocket rather than a list of ball names. Gold's
    Bug Contest is counted off its own PARK BALL counter instead of the pack.
- **Start-menu bindings survive switching generations.** Gold labels the same
  menus PACK, OPTION and STATUS where Red has ITEM, OPTION**S** and the
  trainer card. Because settings are stored per installation rather than per
  save, those three now bind to the same hotkey in both games.

### Changed

- The settings screens no longer borrow the engine's `OptionsMenu` or its
  `OptionRows`. Both are Gen 1 shapes: `OptionRows` has no Gen 2 counterpart
  at all, and `OptionsMenu` ignores caller-supplied rows on Gen 2, so the
  suite's own lists came up showing the game's OPTION screen instead of
  themselves. The suite now owns every screen it opens. They are unchanged on
  Gen 1, to the pixel — including BACK sitting below the list, the wrap order,
  and the exit sound.

### Fixed on Gen 2

- **The menu hotkeys and the radial menu did nothing on Gold**, and the battle
  command menu never opened. All three had the same cause: the suite read
  Red's object graph directly, and Gold keeps the same facts elsewhere.
  - Gold runs the overworld as a field on the game with an empty state stack,
    where Gen 1 runs it as the bottom state. Every overworld hotkey tests that
    stack to decide whether it may fire, so all of them were silently disabled.
    The suite now locates the world on either engine, and defers to Gold's own
    `World:busy()` — which accounts for the script VM, map setup, text and
    choice boxes, field-move tails, fishing and headbutt — rather than
    re-deriving a narrower answer.
  - Gold's start-menu rows are data, and carry no function to call; the suite
    kept only rows that carried one, so it kept none. It now opens a row
    through the engine's own dispatch. The row's id arrives as its `value` —
    the rows the engine hands a mod are built fresh for display and have no
    `id` field at all, so keying on `id` dropped every one of them.
    SAVE, POKEDEX, POKEMON, PACK, POKEGEAR, STATUS, OPTION and MODS are all
    bindable. QUIT is deliberately not: Gold confirms it inside the menu, and
    dispatching it directly would skip that prompt and discard unsaved play.
  - Gold's battle screen holds its fighter one level down, names the move list
    `moves`, and keeps no data table of its own, so every readiness check
    failed. Those reads now go through the adapter. Gold also keeps the
    fighter's HP on the fighter itself where Gen 1 nests it one level deeper;
    because the command and ball menus gate on HP and the move menu does not,
    the move menu worked on Gold while those two stayed dead.

### Known limitations on Gen 2

- **The FLY travel hotkey is unavailable on Gold.** The engine does not expose
  FLY to mods there yet — it is absent from the field-action list and there is
  no supported way to raise its destination picker. The row stays visible and
  reads `UNSUPPORTED` rather than accepting a binding that could never fire.
  RETURN CENTER and BICYCLE are unaffected.

## [1.9.1] - 2026-09-20

### Fixed

- **AUTO TEXT left several battle messages waiting for a button**, most
  noticeably after learning a move: "1, 2 and…", " Poof!", "… forgot …! And…"
  and "… learned …!" each stopped for an A press, as did "… did not learn …!"
  and "HM techniques can't be deleted!". Those messages are drawn in their own
  window pushed over the battle rather than by the battle's own message queue,
  which was the only thing AUTO TEXT watched. It now advances both. Yes/no
  prompts, move selection and menus are still entirely yours — advancing the
  pages of the learn-a-move prompt remains LEARN TEXT's separate opt-in.

## [1.9.0] - 2026-09-20

### Added

- **SKIP LV SFX now also silences the learn-a-move jingle.** Learning a move
  plays the same blocking fanfare a level-up does, in both of the game's
  paths: straight into a free slot, and through the "delete an older move?"
  screen. Both are now covered by the one setting.
- **LEARN TEXT, a new Battle Text setting.** When a Pokémon with four moves
  learns a new one, the game makes you page through "… is trying to learn …",
  "But … can't learn more than 4 moves!" and "Delete an older move to make
  room for …?" before the YES/NO appears. LEARN TEXT advances those pages for
  you and **stops at the decision** — whether to forget a move is always left
  to you. It uses the module's existing SPEED setting.

### Fixed

- **Move accuracy showed no `%` sign.** The Gen 1 font has no percent glyph
  in its charmap, so printing one drew nothing and left the accuracy as a
  bare number with no unit. The sign is now drawn from primitives, the same
  way the power icon is, and is sized to fit its column.

### Note

**LEARN TEXT ships off**, like every other setting in this suite, and the
learn-a-move fanfare is only silenced if SKIP LV SFX is already on.

## [1.8.0] - 2026-09-19

### Added

- **Move info in the battle command menu.** A new **MOVE INFO** setting adds a
  second line to each move in the custom legend showing its attack power next
  to a sword icon, its type abbreviated to three characters, and its accuracy
  as `##%`. Status moves show `--` for power, and moves that never miss show
  `--%`. Types added by other mods are read through the engine's type chart,
  so they display their own names rather than a blank.
- **UI LAYOUT for the battle command menu.** The legend can now be forced to
  `GRID 2x2` or `LIST 1x4` instead of `AUTO`. `AUTO` keeps the compact grid
  when there is room for it and drops to a single column when the grid would
  otherwise have to shrink to stay on screen.
- **SKIP LV SFX in the Battle Text module.** An On/Off setting that skips the
  level-up fanfare during battle. The fanfare is one of the sounds the game
  blocks on, so skipping it removes the pause that comes with every level-up.
  Only the level-up jingle is affected — the fanfares for catching a Pokémon,
  filling a Pokédex page and learning a move all still play normally.

### Fixed

- **The battle command menu could be drawn off-screen in portrait.** The
  legend was positioned against the *window* rather than the *playfield*. On a
  phone held upright the window is far taller than the game's 10:9 frame, so
  bottom-anchored legends landed in the letterbox below the game and
  right-anchored ones could sit outside it entirely. The legend now anchors to
  the playfield, and its scale is clamped against both the available width and
  the available height, so it stays inside the frame at every anchor, scale
  and layout.
- **UI SCALE offers smaller steps.** The scale list gains 50%, 60% and 90%,
  and the automatic floor drops from 50% to 25%, which gives small or portrait
  screens enough room to show the new move info line.

### Note

As with every other option in this suite, **MOVE INFO and SKIP LV SFX ship
turned off**, and `UI LAYOUT` defaults to `AUTO`. Nothing changes until you
turn it on.

## [1.7.2] - 2026-09-19

### Fixed

- **The launcher could not update the mod.** The manifest was missing the
  optional `github` field, and the engine treats an absent value as "no
  auto-update UI for this mod" — so the MODS panel showed neither **Update**
  nor **Versions**. The manifest now declares
  `"github": "ojsaucer/gen1recomp-hotkey-suite"`, which points the launcher at
  this repository's GitHub Releases.
- **Release archives had the wrong shape.** Every file was nested inside a
  `hotkey_suite/` folder, but the launcher's **Import mod .zip**, **Update**
  and **Versions** paths all install archives whose files sit at the *archive
  root*. Release assets are now built flat and follow the engine's naming
  convention, `hotkey_suite-<version>.zip`.

### Added

- A ready-to-use GitHub Actions release workflow (`release.yml`) that
  validates the manifest, checks every Lua file's syntax, builds the
  root-level archive, excludes `tests/`, and publishes the tagged release. It
  is provided alongside this release rather than committed, because adding a
  workflow file requires a token scope this project's automation doesn't hold.

### Upgrade note

Because the launcher reads the `github` field from the copy of the mod you
already have installed, **this one update must be installed by hand** — the
installed 1.7.1 has no such field and so cannot offer itself an update. Install
1.7.2 once (extract `hotkey_suite-1.7.2.zip` into `mods/hotkey_suite/`), and
**Update** / **Versions** will work from then on.

## [1.7.1] - 2026-09-19

### Fixed

- **Every module came up OFF on each launch, with settings intact on disk.**
  The 1.7.0 settings writer emitted a file that already began with `return`,
  and the reader prepended a second one, producing `return return {` — a
  syntax error. *Every* load failed, so the suite started from defaults
  (disabled, unbound) on every boot while the settings screens, the file on
  disk, and the legacy importer all still showed the correct values. The
  importer then rewrote the file from the save slot each launch, which is why
  the settings looked perfectly preserved while nothing actually worked.
  Settings are now read back correctly; a file written by any earlier build
  is still accepted.
- A settings file that exists but cannot be parsed is now reported in the log
  instead of silently falling back to defaults, and is left untouched on disk
  until a setting is changed.

## [1.7.0] - 2026-09-18

### Fixed

- **Settings now survive restarts, crashes and loading a save.** This is the
  root cause behind several long-standing reports: hotkeys that read as
  assigned but fired nothing, settings that reverted on restart, and every
  binding going dead after a crash. Configuration was stored in `mod.save`,
  which the engine backs with `save.modData` — save-slot state that only
  reaches disk when the player saves in-game, and which `Game:adoptSave`
  **replaces outright** on NEW GAME and CONTINUE. Because every hotkey
  compiles its combination once at registration, swapping that table out
  from under the suite left the input broker holding boot-time (empty)
  combinations while the settings screens still displayed the real ones.
  Configuration has moved to `mod.cache`, which is installation-scoped,
  independent of save slots, and written straight through to disk the moment
  a setting changes.
- Existing settings are imported automatically the first time 1.7.0 runs.
  The import is one-way and latches immediately, so loading an older save
  later can never overwrite settings changed since.
- Keys bound to a hotkey no longer double-fire that hotkey while you are
  editing bindings in the suite's own settings screens.
- Help text no longer scrolls past before it can be read. `TextBox` only
  waits for a button at a *page* break; within a page it advances line to
  line on its own, scrolling a two-line window. Help strings carried no page
  breaks, so they typed straight through and left only their last two lines
  on screen. Help is now pre-broken into two-line pages at the engine's own
  wrap width, so each page holds for `A`.
- Autofire no longer drives the suite's own screens. A toggled-on autofire
  kept tapping its target over the settings and help screens, where its
  `AUTOFIRE` badge is not drawn to show it was still running.

### Added

- **Battle Text module.** `AUTO TEXT` advances battle messages on its own,
  `LEVEL UP` also dismisses the level-up stat window, and `SPEED` sets the
  rate for both. Auto text moved here out of Battle Command Menu, where it
  never thematically belonged.
- **Per-setting help.** Press `START` on any setting for an explanation of
  what it does. Every setting except each module's `ENABLED` switch has one.
- **Controls legend.** Screens with bindable hotkeys now show `SEL:CLEAR
  ST:HELP` along the bottom, so the unassign and help keys are discoverable
  rather than folklore. It replaces the old `BACK` row — `B` still backs out.

### Changed

- **Options are reorganized** into
  `OPTIONS > HOTKEY SUITE > KEYBOARD/GAMEPAD > OVERWORLD/BATTLE/GENERAL >
  MODULES`. Each module is filed under the context it is used in — Travel and
  Menu Hotkeys under `OVERWORLD`, Ball Menu and the battle modules under
  `BATTLE`, Autofire under `GENERAL` — so the list stays navigable as more
  modules are added.
- `BATTLE MENU` is now `BATTLE CMD MENU` (Battle Command Menu).

### Removed

- The `START MENU > ASCENDANT` entry. Kanto Ascendant's collector only files
  items under four hardcoded groups (quests / research / partners / events),
  and its `ASCENDANT > SETTINGS` screen builds its children from a private
  registry with no third-party injection point, so no contextually sensible
  placement was reachable. `OPTIONS > HOTKEY SUITE` is the single entry
  point and works on every install, with or without Kanto Ascendant.

## [1.6.1] - 2026-09-17

### Fixed

- Selecting `HOTKEY SUITE` from `START MENU > ASCENDANT > EVENTS + TITLES`
  crashed with `module 'src.ui.HotkeySuiteInputs' not found`. Kanto
  Ascendant's own menu collector calls `item.onSelect()` with **no
  arguments** (confirmed by reading its `ascendant_menu.lua`), but the entry
  added in 1.6.0 expected `game` as a parameter, so it received `nil` and
  `Screens.push(nil, "HotkeySuiteInputs")` fell through to a bare
  `require("src.ui.HotkeySuiteInputs")`. `onSelect` now closes over `game`
  from the `ui.start_menu.items` hook itself instead of expecting it as an
  argument, matching how Kanto Ascendant's own internal rows are written.
  Opening `HOTKEY SUITE` from `OPTIONS` was unaffected by this bug.

## [1.6.0] - 2026-09-17

### Added

- **Kanto Ascendant integration**: Hotkey Suite now adds an optional Start
  Menu entry that Kanto Ascendant's own collector relocates into its
  `START MENU > ASCENDANT` hub (under `EVENTS + TITLES`), matching the same
  soft-integration contract Voxel Ascendant uses. Without Kanto Ascendant
  installed, the entry simply behaves as an ordinary Start Menu row that
  opens the same Hotkey Suite settings screen.

### Changed

- Renamed the `AUTOFIRE` module to `AUTOFIRE HOTKEYS` for consistency with
  the rest of the suite's module names.

### Fixed

- Menu Hotkeys and the Radial Menu can once again open a *different* menu
  immediately after one is already open, without first backing all the way
  out to the overworld. The v1.4.0 crash hardening had tightened
  `canOpenMenu` to require an empty screen stack, which unintentionally
  blocked the existing "swap menus" flow (`closeMenus` popping the old menu
  before the new one opens); the nil-safety hardening is kept, but the
  empty-stack requirement is removed.
- The Ball Menu's single-line selector box and its text now align exactly.
  The border was snapped to the 8px tile grid while the text used the
  original unsnapped pixel position, so any position other than a flush
  top/bottom edge (including the default centering math) could draw the
  border a few pixels away from the text. The border now draws at the same
  pixel-exact position as the text, the same fix already applied to the
  Radial Menu's highlight box.

## [1.5.0] - 2026-09-17

### Added

- Every module now carries an `ENABLED` master switch as its first setting.
  All six modules ship **OFF**, so a fresh install never reacts to input.
- **Auto Text** for the Battle Command Menu: automatically advances battle
  messages with a `SLOW` / `MEDIUM` / `FAST` / `VERY FAST` `TEXT SPEED` setting.
  It only advances settled battle messages, so menus, move selection, and
  yes/no prompts stay under manual control.

### Changed

- Renamed the `BATTLE HOTKEYS` module to `BATTLE CMD MENU` (Battle Command
  Menu); its feature id is now `command_menu`.
- The ball selector is now a single line. Left/Right cycles ball types, `A`
  throws, and `B` cancels, so it no longer covers replacement battle UIs.
- `UNASSIGN ALL` now also returns every module to `OFF`, so no module can be
  left switched on with nothing bound.
- Documentation now states up front that all modules and hotkeys start off.

### Fixed

- A module master switch is now honored by the input broker itself. Previously
  a switch could read `ON` while the module did nothing, which is what made
  the radial menu look enabled on a fresh save.

## [1.4.0] - 2026-09-17

### Added

- **Ball Menu / Quick Throw Hotkey**: Assignable battle-only hotkey for keyboard
  and gamepad to open a custom Poké Ball selection UI showing ball types and
  current bag quantities, or directly quick-throw a preferred ball. Includes 9
  customizable UI anchor locations.

### Changed

- Simplified the root Hotkey Suite options row to display `# SET` (assigned
  hotkeys count), removing the superfluous active count label.

### Fixed

- Hardened overworld menu safety checks against nil screen states during warps,
  map transitions, and script movements (e.g. Victory Road boulder puzzles).
- Added physical input state reconciliation for keyboard keys and gamepad
  buttons to prevent ghost held inputs from blocking combos after screen changes.
- Wrapped hotkey action and listener execution in protected calls so isolated
  errors never break subsequent hotkeys or input polling.

## [1.3.0] - 2026-09-15

### Added

- A suite-level `UNASSIGN ALL` row beside Keyboard and Gamepad.
  It uses a Yes/No confirmation that defaults to No.
- Nine placement choices for the radial menu.

### Changed

- Streamlined scope to focus exclusively on Keyboard and Gamepad accessibility,
  removing touchscreen controls.
- Suite-wide unassignment clears all keyboard/gamepad bindings while
  preserving unrelated behavior settings.

## [1.2.5] - 2026-09-15

### Fixed

- Radial-menu selected boxes and full labels now render after every
  unselected label, keeping the complete highlight effect in the foreground.
- A completed combination now takes precedence over matching shorter bindings
  on the same press. For example, holding RT and pressing Y activates RT+Y
  without also activating a separately assigned Y hotkey.

## [1.2.4] - 2026-09-15

### Added

- Configurable position and 75%, 100%, 125%, or 150% scale for the custom
  battle UI directional legend.
- The custom move-selection legend now reads the active Pokémon's current move
  names directly from battle state.

### Fixed

- START-menu discovery now observes the final decorated list, including
  aggregated custom entries such as Kanto Ascendant's `ASCENDANT` hub.

## [1.2.3] - 2026-09-15

### Added

- Catch-all compatibility for replacement battle UIs that claim the documented
  bottom-UI visibility hook, including the installed Voxel Ascendant and
  Floating Battle HUD implementations.

### Changed

- When another mod owns the battle command surface, command mode no longer
  paints or erases at native menu coordinates. A compact 2x2 directional
  legend is drawn in the final HUD pass instead, independent of the custom
  UI's scaling, camera, and private layout geometry.

## [1.2.2] - 2026-09-15

### Fixed

- Command-mode arrows now use the native classic or wide battle-menu anchors.
- Wide + Fill + Extended HUD arrows render into the engine's separately
  anchored battle HUD canvas instead of the scaled battle-scene canvas.
- Radial highlight boxes now use pixel-positioned borders so their centers
  exactly match the stable label anchors, except when clamped at an edge.

## [1.2.1] - 2026-09-15

### Added

- A separate keyboard/gamepad Run hotkey that only activates from the main
  battle command menu and retains the game's normal escape rules.
- Command mode now maps Up, Right, Left, and Down to move slots 1–4 while the
  move-selection screen is active.

### Changed

- Command mode's settings label and capture title now use the shorter `CMD`
  form so assignment text stays inside the options box.
- While command mode is held, the single vanilla cursor is replaced by four
  rotated direction arrows on both the battle command and move-selection
  menus.
- Radial selection boxes now expand around the same stable item anchors as
  their labels and only shift when clamped to a screen edge.

## [1.2.0] - 2026-09-15

### Added

- Battle-only command-mode hotkeys for keyboard and gamepad. Hold the assigned
  hotkey and press Up, Right, Left, or Down to directly choose FIGHT, PKMN,
  ITEM, or RUN.
- Optional touchscreen battle-command buttons, off by default.

### Changed

- Select and Start now both clear the highlighted assignment or enabled touch
  control. Start remains Back on rows without an unassign action.
- Radial-menu labels now retain one center anchor as the selected box expands
  from abbreviated text to the full dynamic START-menu label.
- The vanilla battle command cursor is hidden while command mode is held.

## [1.1.0] - 2026-09-15

### Added

- Overworld-only Fly, Pokemon Center return, and Bicycle hotkeys for keyboard,
  gamepad, and touchscreen.
- Fly opens the native destination map when HM02 is in the Bag.
- Pokemon Center return uses the native Teleport departure and last-heal warp
  without requiring a move or inventory item.
- Bicycle uses the native field-item action and keeps its normal map rules.
- The root Hotkey Suite row reports active and assigned hotkey totals.

## [1.0.0] - 2026-09-15

### Added

- One nested Hotkey Suite hierarchy for keyboard, gamepad, and touchscreen.
- Modular feature registry and independently loaded feature files.
- Fixed/next-input autofire with toggle/hold behavior and five speeds.
- Dynamic keyboard/gamepad hotkeys for every live START-menu entry.
- Gamepad radial menu using every live START-menu entry.
- Conflict-safe touchscreen autofire and three-slot menu shortcut bar.
- Reliable LT/RT threshold handling.
- Up-to-four-input keyboard and gamepad combinations with exact-conflict
  eviction.
- SELECT-to-unassign support for every hotkey row.

### Changed

- All hotkeys and touch controls now start unbound or off.
- Removed redundant `OPEN` labels from nested navigation rows.
- Hotkeys now observe inputs after vanilla handling instead of consuming them,
  so assigning A, B, or another gameplay control preserves its normal action.
- Menu Hotkeys and Radial Menu are restricted to the overworld; Autofire is
  available in battle.
- LT/RT detection now uses separate press and release thresholds.
- Combination state is tracked centrally, allowing one input (including LT or
  RT) to remain held for any duration before another input completes the
  combination. Single-button hotkeys remain supported.
- Radial Menu now has an ON/OFF setting that defaults to ON.
- The root Hotkey Suite row now displays active and assigned hotkey totals.
- Touchscreen suite controls wrap into multiple rows when necessary.

### Fixed

- Extended the combination-assignment dialog by one text row so its
  instructions remain inside the border.
- The release of the A press used to open assignment capture now reaches the
  game, preventing the next A press from being lost.
- Gamepad A and B are rejected as single-button assignments while remaining
  valid inside combinations.
- LT/RT state is also polled from connected gamepads, avoiding dropped trigger
  edges from inconsistent axis-event delivery.
- Correctly assigns the default Autofire speed when no saved speed exists,
  preventing an immediate nil-index crash when its settings screen renders.
- Added the required renderer palette contract to custom settings, capture,
  and radial screens, preventing the Autofire settings screen from crashing.
- Restored combinations for Menu Hotkeys.
- Preserved mod-added START-menu entries in Menu Hotkeys and Radial Menu.
- Neutralized radial stick input so movement cannot remain latched after the
  radial closes.
