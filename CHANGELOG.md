# Changelog

## [1.13.0] - 2026-10-05

### Added

- **A QUICK EXIT setting on Gen 3's MENU HOTKEYS screen, directly below
  ENABLED, on by default.** On Red and Gold, `activateMenuItem`'s
  `closeMenus()` unwinds the whole stack before pushing the chosen screen, so
  a menu hotkey never puts the Start Menu on screen at all — CANCEL already
  lands back in the overworld in one press. FireRed cannot dispatch that way:
  `src/ui/game3/start_menu.lua`'s `confirm()` is the only entry point in, and
  it requires the Start Menu to already be open (Gen3Compat backs it with
  `Hud.openStartMenu`). Canceling out of, say, BAG used to return to a Start
  Menu the player never opened, needing a second CANCEL to reach the
  overworld. QUICK EXIT closes that gap: once whatever the hotkey opened has
  been backed out of and the Start Menu is the only thing left on FireRed's
  own UI stack, it is closed automatically too, landing exactly where Red and
  Gold already do. Turning it OFF restores the Start-Menu-behind-it behaviour,
  the same as pressing START yourself would leave. The setting has no effect
  on Red or Gold, which were never affected by the gap.

## [1.12.0] - 2026-10-04

### Added

- **A settings screen on Gen 3, drawn with FireRed's own chrome.** Hotkeys no
  longer have to be assigned from a Gen 1 or Gen 2 boot: `START > HOTKEY
  SUITE` opens the same INPUT / CONTEXT / MODULE / SETTINGS tree the other two
  generations show, and the combo capture prompt comes with it.
  - The tree is not a second copy. `main.lua` publishes the input list, the
    context list and the module lookup once, and both presentations read from
    those, so a module registered tomorrow appears on all three generations
    without either screen being touched.
  - Every button means on Gen 3 exactly what it means on Gen 1 — A opens or
    sets, left/right adjust, SELECT clears a binding, START shows a module's
    help, B backs out one level — including the small asymmetries: the
    navigation lists end in a BACK row and close on START, the settings lists
    do not and spend START on help instead.
  - Help text is regrouped into two-line pages that each hold for A, the same
    treatment Gen 1 gives it, measured against FireRed's dialogue box.
  - The list geometry, the frame, the dimming that marks the current row and
    the bobbing scroll arrows are FireRed's, taken from its own OPTION menu,
    and the window frame follows whichever one the player chose. Parity is a
    promise about behaviour, not about pixels.
- **`START > HOTKEY SUITE` as the Gen 3 entry point.** Gen 3's option list
  raises no mod hook, so there is no OPTIONS row to add. Its Start Menu does,
  and an entry there may carry its own `onSelect`, so the suite takes that
  route and sits just above EXIT.

### Changed

- **Combo capture is one state machine with two faces.** Arming the capture is
  now separate from drawing it, so the Gen 1 screen and the Gen 3 layer share
  the identical rules about which keys count, when a combination is complete
  and what a bare A or B may not be bound to.
- **The suite knows when its own screen is up on Gen 3.** The check that stops
  the suite reacting to a keypress while the player is editing the keypress
  used to scan `game.stack`, which Gen 3 does not have. It now asks the active
  presentation, so synthesized input cannot type through the help text or
  steal a combination mid-capture on any generation.

### Fixed

- **Menu hotkeys on Gen 3 opened the Start Menu and stopped there.** Asking
  what is on the start menu means calling `StartMenu.new`, and on FireRed
  that does not build a menu the way it does on Red and Gold — Gen3Compat
  backs it with `Hud.openStartMenu`, so the question *opens* the menu. The
  hotkey asked first and dispatched second, and in between it had made the
  world busy by its own doing: an open menu is a busy world as far as
  `Hud.busy()` is concerned, so the dispatch then declined to act. The
  refresh was redundant in the first place — the dispatcher already refreshes
  itself, after its gate — so it is gone, and the reason it must not come
  back is written where someone would reach for it.
- **The Start Menu row read `HOTKEY SUITE` and ran past the menu's frame.**
  FireRed sizes that window to its widest stock label, so the row is now
  `HOTKEYS`. The screen behind it still calls itself HOTKEY SUITE.

### Not yet on Gen 3

The radial wheel and the autofire HUD badge are still Gen 1 chrome and remain
withheld on FireRed, as do the battle modules. An inactive module reports
itself as OFF, so nothing here is a difference the player can be surprised by.

## [1.11.0] - 2026-09-27

### Added

- **Gen 3 support (FireRed / LeafGreen).** The suite now loads and runs on a
  Gen 3 boot alongside Gen 1 and Gen 2. Bindings are stored per installation
  rather than per save, so every hotkey already assigned on Red or Gold is
  live on FireRed the moment it boots — there is nothing to set up twice.
  - **Autofire** works in full: every mode, speed, target and the NEXT INPUT
    method.
  - **Menu hotkeys** open the START menu screens. FireRed's rows are pure data
    with no callback to rewire, and Game3 has no `openStartMenuItem` to hand
    an id to, so dispatch goes through the engine's own `StartMenu.confirm()`
    — the same path the player's A press takes, so the flag gates that built
    the list, the menu sound and the SAVE and RETIRE prompts all still run.
    BAG, TRAINER CARD and OPTION bind to the same hotkeys as Red's ITEM,
    trainer card and OPTIONS.
  - **Travel hotkeys:** BICYCLE and RETURN CENTER. FireRed splits the trip to
    the POKEMON CENTER the way Gold does but names the second half
    `warpToHealPoint`, and both halves are reachable, so the hotkey needs
    nothing the engine does not already do for a blackout.

### Changed

- **The generation adapter now answers for three engines rather than two.**
  FireRed is further from Red than Gold is: it has no state stack, keeps
  nothing world-shaped on the game object at all, and reaches mods through a
  compatibility layer. Every one of those differences is stated once, in
  `features/gen.lua`, and every helper still probes for the capability it
  needs rather than asking which game is running.
  - "Where is the world" gains a third answer. Red stacks it, Gold hangs it
    off the game, and FireRed exposes it only through the mod API, whose
    `:overworld()` is already nil unless the game is in the field.
  - "May the player act" defers to FireRed's own gate, the one its field
    actions apply a moment later, rather than re-deriving it here.
- **The FLY row reads `UNSUPPORTED` rather than `GEN 1 ONLY`.** Gold has taken
  a binding since 1.10.0, so the old label was already wrong there, and on
  FireRed it would have been actively misleading. The row still refuses a
  binding only when a live world has answered to neither route.

### Not yet on Gen 3

The suite's own screens — the settings list, the capture prompt, the radial
wheel and the autofire badge — are Gen 1 chrome: one font atlas, one 160x144
frame, one state stack. FireRed shares none of the three. Those are withheld
there rather than drawn broken, and a native FireRed settings screen is the
next piece of work. Until it lands, Gen 3 hotkeys are configured from a Gen 1
or Gen 2 boot of the same installation. The battle modules are likewise
inactive on Gen 3 for now. Nothing about this is a behaviour difference the
player can be surprised by: an inactive module reports itself as OFF.

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
  - **The control arrows sat on the wrong letters on Gold.** The legend is
    painted into the battle's native tile grid, and the suite was painting
    Gen 1's cells. Both engines step the command rows by 16px, so the rows
    were right and only the columns were wrong — the arrows landed a whole
    column to the left, over FIGHT and PACK. Gold's command cursor now comes
    from Gold's own box and column-spacing tiles, including the contest
    layout and the wide layout's 18-tile gutter. Gold's move list also never
    reflows into two columns the way Gen 1's does when wide — the gutter only
    widens the box — so its arrows now stay in a single column beside the
    move names.

- **Every travel hotkey was dead on Gold**, FLY included — and RETURN CENTER
  and BICYCLE with it. They each asked Red's question before firing: "is the
  overworld the one and only state on the stack?" Gold runs the overworld as
  a field and updates it only while that stack is *empty*, so the answer was
  never yes. The frame test now fits either engine.
- **FLY now works on Gold**, through the engine's own field-move pipeline.
  Fly is missing from the field-action table Gold's `WorldAPI` walks, but the
  pipeline that table feeds handles `FLY` like any other field move, so the
  hotkey goes in there instead of reimplementing anything. Every one of the
  engine's gates is kept: the STORM badge, the outdoors-only check that counts
  a POKEMON CENTER as indoors, the engine's own refusal lines, the native fly
  map and the bird. Who may fly is resolved through Gold's
  `fieldmove.eligibility` hook chain, so another mod's answer is honoured.
  The row is capability-probed rather than keyed to the game: an engine that
  offers neither route still reads `GEN 1 ONLY` and accepts no binding.
- **RETURN CENTER refused forever on Gold**, even standing in a POKEMON
  CENTER. Red teleports out through one `World` method gated by the save's
  `lastHeal`; Gold has neither name, so the hotkey fell into "visit a POKEMON
  CENTER first" every time. Gold keeps the same trip in two halves — the heal
  point, which reads the blackout override ahead of the spawn table so the
  Fast Ship and Mr. POKEMON's house resolve the way the cart does, and the
  warp itself. The hotkey now uses them, and Gold's heal point serves as its
  `lastHeal`: nothing to return to is still a refusal.

### Known limitations on Gen 2

- Gold's own menus remain the authority on anything the suite only opens: QUIT
  is still not bindable, for the reason above.

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
