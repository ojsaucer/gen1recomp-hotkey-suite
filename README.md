# Hotkey Suite

Hotkey Suite is one modular accessibility and input hub for keyboard, gamepad,
and touchscreen players in Pokémon Red, Blue, and Yellow.

## Menu hierarchy

`OPTIONS > HOTKEY SUITE > KEYBOARD / GAMEPAD / TOUCHSCREEN > FEATURE > SETTINGS`

Only one row is added to the main OPTIONS menu. Features register themselves
under an input branch, so future additions do not need to rewrite the menu.

## Included features

### Keyboard

- **Autofire:** fixed-button or next-input activation, toggle/hold modes, five
  repeat speeds, any native Game Boy target, an optional toggle-state notice,
  and a rebindable hotkey combination.
- **Menu Hotkeys:** bind any currently available START-menu entry. The list is
  built live, so entries added or removed by other mods are included.
- **Travel Hotkeys:** configurable Fly, Return to Pokémon Center, and Bicycle
  actions. Fly requires HM02 in the Bag; Return uses the native Teleport
  animation without requiring a Pokémon to know Teleport; Bicycle requires
  the Bicycle and preserves the game's normal terrain restrictions.
- **Battle Hotkeys:** hold an assigned command-mode combination, then press
  Up, Right, Left, or Down to choose FIGHT, PKMN, ITEM, or RUN directly.
  The same directions choose move slots 1–4 on the move-selection screen.
  A separate hotkey attempts RUN directly from the main battle menu.

### Gamepad

- **Autofire:** the keyboard feature set with gamepad binding and reliable
  analog LT/RT support.
- **Menu Hotkeys:** live START-menu bindings for controller combinations.
- **Radial Menu:** hold a configurable button or combination, aim either stick, and release
  to choose from the live START-menu entries.
- **Travel Hotkeys:** the same three overworld-only travel actions with
  gamepad combinations, including LT and RT.
- **Battle Hotkeys:** the same held command mode, with D-pad directions as
  the secondary input, plus a separate instant-Run binding. The normal battle
  controls remain active when the command-mode hotkey is not held.

### Touchscreen

- **Autofire:** an optional HUD button using the shared target, speed, and
  toggle/hold settings.
- **Menu Shortcuts:** up to three configurable shortcuts sourced from the live
  START menu. The strip uses the unobstructed top edge while the overworld is
  active and no menu/dialogue is covering it.
- **Travel Hotkeys:** optional FLY, PC-return, and BIKE buttons. Touch controls
  wrap onto a second row when more than four suite buttons are enabled.
- **Battle Hotkeys:** an optional four-button command overlay that directly
  selects FIGHT, PKMN, ITEM, or RUN from the battle command menu.

The touchscreen layer uses `render.hud` and `input.pointer`. Native touch
controls receive first refusal in the engine, and other pointer mods receive
the event before this suite claims one of its visible cells. This avoids
stealing touches from the D-pad, A/B, Start/Select, or another mod.

## Binding behavior

- Every keyboard and gamepad hotkey starts unbound. Both touchscreen features
  also start off.
- A hotkey can contain up to four simultaneously held keyboard keys or gamepad
  buttons. LT and RT use hysteresis so they bind and release consistently.
- Gamepad A and B cannot be assigned alone because doing so can interfere with
  menu confirmation and cancellation. They remain available within multi-button
  combinations.
- Assigning the exact same combination to another action automatically clears
  the previous action. Subsets and supersets remain available as distinct
  combinations.
- When one press completes both a combination and one of its shorter subset
  bindings, only the longest completed combination activates. The shorter
  binding still works normally when pressed without the held modifier.
- Highlight an assignable row and press **Select** or **Start** to unassign it.
  On rows without an assignment, Start retains its normal Back behavior.
- The input-scheme menu includes **Unassign All**. It asks for Yes/No
  confirmation, defaults to No, then clears all keyboard/gamepad assignments
  and disables assigned touchscreen controls without resetting preferences.
- Menu Hotkeys and Radial Menu only activate in a clear overworld state.
  Autofire remains available in battles and other gameplay contexts.
- Travel Hotkeys only activate in a clear overworld state. Gen 1's Fly HM is
  HM02 (`HM_FLY` internally); HM05 is Flash.
- Battle command mode only acts on the settled battle command menu. While its
  hotkey is held, Up/Right/Left/Down map to the top-left/top-right/bottom-left/
  bottom-right commands. On move selection, those directions map to move slots
  1/2/3/4. The vanilla cursor is replaced with four directional arrows in
  either menu.
- If another mod claims and hides the native battle UI, command mode avoids
  drawing into the hidden menu and instead displays a compact directional
  legend in the final HUD pass. Its corner/edge position and 75–150% scale are
  configurable. Move-selection labels use the active Pokémon's live move
  names. This works with installed floating and replacement battle UIs without
  depending on their private coordinates.
- The instant-Run hotkey only acts on the main battle command menu and follows
  the game's normal escape rules.
- While the radial menu is open, its stick is forwarded to the game as neutral
  and is neutralized again when the wheel closes, preventing stuck movement.
- Radial Menu has ON/OFF, stick, nine-position placement, and 75–150% scale
  settings. It defaults to enabled, centered, and 100%. The root Hotkey Suite
  row reports active and assigned totals as `N ON / M SET`.

## Compatibility

Hotkey Suite discovers START-menu items at use time through the same factory
and hook used by the game. Discovery runs after other menu decorators, so
aggregated entries such as Kanto Ascendant's `ASCENDANT` hub are included. It
does not maintain a fixed list of vanilla tabs.
The standalone `autofire_hotkey`, `menu_hotkeys`, and `radial_menu` mods
conflict because enabling them together would install duplicate input hooks.

## Installation

Copy `hotkey_suite` into the game's `mods` directory and enable it in the
launcher. Disable the three superseded standalone mods.

## Validation

From a Gen1Recomp checkout:

```sh
python3 tools/modkit.py validate mods/hotkey_suite --base imported
python3 tools/modkit.py lint mods/hotkey_suite
luajit mods/hotkey_suite/tests/hotkey_suite_test.lua
```

## License

MIT
