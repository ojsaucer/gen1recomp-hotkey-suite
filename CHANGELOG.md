# Changelog

## [1.3.0] - 2026-09-15

### Added

- A suite-level `UNASSIGN ALL` row beside Keyboard, Gamepad, and Touchscreen.
  It uses a Yes/No confirmation that defaults to No.
- Nine placement choices for the radial menu.

### Changed

- Suite-wide unassignment clears all keyboard/gamepad bindings and disables
  assigned touchscreen controls while preserving unrelated behavior settings.

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
