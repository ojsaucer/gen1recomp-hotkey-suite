# Hotkey Suite for Gen1Recomp

A modular accessibility and input suite for **Keyboard** and **Gamepad** in Pokémon Red, Blue, Yellow, Gold, Silver, Crystal, FireRed, and LeafGreen.

Configure everything from one place:  
`OPTIONS > HOTKEY SUITE` — or, on FireRed and LeafGreen, `START > HOTKEY SUITE`

> ### ⚠️ Everything starts OFF
> **Every module ships disabled and every hotkey ships unbound.** Installing the
> suite changes nothing about how the game plays until you opt in. Open a module,
> flip **ENABLED** to **ON**, then assign the hotkeys you want.

Settings are saved per installation, not per save file, and are written to disk
the moment you change them. Press **START** on any setting for help.

---

## Features

Each module below has its own **ENABLED** master switch (**OFF** by default).

### ⚡ Autofire Hotkeys
- **Toggle or Hold** activation with 5 adjustable repeat speeds.
- Supports **Fixed Target** (any Game Boy button) or **Next Input** mode.
- Optional on-screen HUD status indicator with customizable position.

### 📜 Menu Hotkeys & Radial Menu
- **Instant Shortcuts:** Bind any START-menu option to single buttons or multi-key combos (up to 4 inputs).
- **Dynamic Mod Discovery:** Automatically finds and binds menu tabs added by other mods (such as Kanto Ascendant).
- **Radial Wheel:** Hold a hotkey, point either analog stick, and release to select. Includes 9 screen anchor positions.
- **Swap Without Backing Out:** Opening a different menu hotkey closes whatever menu is currently open first, so you can jump straight from one menu to another.

### 🚲 Travel Hotkeys (Overworld)
- **Fly:** Instant Town Map flight when HM02 is in your Bag.
- **Return to Pokémon Center:** Immediate teleport to your last visited Pokémon Center.
- **Bicycle:** Fast toggle whenever the Bicycle is in your Bag.

### ⚔️ Battle Command Menu
- **Command Mode:** Hold a hotkey and press D-Pad / Direction keys (`Up`, `Right`, `Left`, `Down`) to directly select **FIGHT**, **PKMN**, **ITEM**, or **RUN**—or choose moves 1–4.
- **Instant Run:** Dedicated hotkey to attempt fleeing directly from the main battle menu.
- **Custom Battle UI Compatible:** Automatically adapts to modded battle UIs (e.g. Floating Battle HUD, Voxel Ascendant) with a floating directional legend and real move names.
- **Move Info:** Optionally adds a second line to each move showing its attack power beside a sword icon, its type abbreviated to three characters, and its accuracy as `##%`.
- **UI Layout & Scale:** Choose `AUTO`, `GRID 2x2`, or `LIST 1x4`, with scales from 50% to 150%. The legend anchors to the playfield and shrinks to fit, so it stays on screen even in portrait on mobile.

### 💬 Battle Text
- **Auto Text:** Automatically advances battle messages at a configurable speed (`Slow`, `Medium`, `Fast`, `Very Fast`) while leaving menus, move selection, and yes/no prompts fully under your control. This includes the messages that run on their own window over the battle, such as the "1, 2 and… Poof!" sequence after a move is forgotten.
- **Level Up:** Also dismisses the level-up stat window automatically.
- **Skip Lv SFX:** Skips the level-up fanfare and the one for learning a new move, removing the pause the game takes to play them. Fanfares for catching a Pokémon, new Pokédex entries, and winning a battle are untouched.
- **Learn Text:** When a Pokémon with four moves learns a new one, advances the pages in front of the "delete an older move?" prompt and stops at the YES/NO. The choice is always left to you.

### 🔴 Ball Menu
- **Ball Menu:** Battle-only hotkey opening a compact **single-line** selector. Cycle ball types with Left/Right, throw with `A`, cancel with `B`.
- **Quick Throw:** Alternate behavior that instantly throws your preferred ball, falling back to the first ball in your Bag.
- **9 UI Positions:** Keeps the selector clear of custom battle UIs.

---

## Binding & Input Highlights

- **Multi-Button Combos:** Bind chords with up to 4 simultaneous keys or buttons.
- **Reliable Triggers:** Full analog `LT` and `RT` detection with built-in hysteresis.
- **Smart Conflict Resolution:** Exact duplicate bindings auto-evict older assignments. Chord modifiers (e.g. `RT+Y`) take priority without misfiring single-button hotkeys (`Y`).
- **Quick Unassign:** Press **Select** on any option to clear its binding, or use **Unassign All** to reset every module back to OFF and unbound.
- **Context-Aware:** Menu and travel hotkeys only fire in the overworld; battle hotkeys only fire during battle.

---

## Compatibility

Settings and bindings are stored per installation rather than per save, so a
hotkey assigned in one game is already live in all of them.

| | Gen 1 (Red / Blue / Yellow) | Gen 2 (Gold / Silver / Crystal) | Gen 3 (FireRed / LeafGreen) |
|---|---|---|---|
| Autofire | ✅ | ✅ | ✅ |
| Menu hotkeys | ✅ | ✅ | ✅ |
| Travel — Bicycle / Return Center | ✅ | ✅ | ✅ |
| Travel — Fly | ✅ | ✅ | `UNSUPPORTED` |
| Battle command menu / Battle text / Ball menu | ✅ | ✅ | — |
| Radial wheel | ✅ | ✅ | — |
| In-game settings screen | ✅ `OPTIONS` | ✅ `OPTIONS` | ✅ `START` |

- **FLY** is the one action an engine can withhold. Red hands it to mods
  directly and Gold reaches the same place through its field-move pipeline, but
  FireRed's fly destinations are the region map's town spawn points and nothing
  exposes them, so the row reads `UNSUPPORTED` there and accepts no binding that
  could never fire. RETURN CENTER and BICYCLE work in all three.
- **Configuring on Gen 3.** FireRed's option list is closed to mods, so the
  suite takes the Start Menu instead and sits just above **EXIT**. The screen
  behind that entry is drawn with FireRed's own chrome — its window frames, its
  font, its dimmed-row selection — but it is the same menu: same tree, same
  buttons, same help on **START**. Bindings are stored per installation, so a
  hotkey assigned on Red is already live on FireRed and vice versa.
- Works alongside custom battle UI mods (Floating Battle HUD, Voxel Ascendant, Kanto Ascendant): the Battle Command Menu detects modded battle layouts and draws a floating legend with real move names instead of fighting for the vanilla cursor.

---

## Installation

1. Download the latest `hotkey_suite-<version>.zip` from [Releases](https://github.com/ojsaucer/gen1recomp-hotkey-suite/releases).
2. Create a `hotkey_suite` folder inside your `mods/` directory and extract the archive into it. The archive is flat, so `manifest.json` and `main.lua` must end up directly inside `mods/hotkey_suite/`.
3. Enable **Hotkey Suite** in the launcher, then open **OPTIONS > HOTKEY SUITE** (**START > HOTKEY SUITE** on FireRed and LeafGreen).
4. Pick an input type, open a module, switch **ENABLED** to **ON**, and assign your hotkeys.

### Updating

> **Upgrading from 1.7.1 or earlier?** Install 1.7.2 by hand once,
> then you can update within the launcher itself.
---

## License

MIT


