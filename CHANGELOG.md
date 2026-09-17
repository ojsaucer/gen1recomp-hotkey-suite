# Changelog

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
