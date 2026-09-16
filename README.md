# Hotkey Suite for Gen1Recomp

A modular accessibility and input suite for **Keyboard** and **Gamepad** in Pokémon Red, Blue, and Yellow.

Configure everything from one menu:  
`OPTIONS > HOTKEY SUITE > KEYBOARD / GAMEPAD`

---

## Features

### ⚡ Autofire
- **Toggle or Hold** activation with 5 adjustable repeat speeds.
- Supports **Fixed Target** (any Game Boy button) or **Next Input** mode.
- Optional on-screen HUD status indicator with customizable position.

### 📜 Menu Hotkeys & Radial Menu
- **Instant Shortcuts:** Bind any START-menu option to single buttons or multi-key combos (up to 4 inputs).
- **Dynamic Mod Discovery:** Automatically finds and binds menu tabs added by other mods (such as Kanto Ascendant).
- **Radial Wheel:** Hold a hotkey, point either analog stick, and release to select. Includes 9 screen anchor positions.

### 🚲 Travel Hotkeys (Overworld)
- **Fly:** Instant Town Map flight when HM02 is in your Bag.
- **Return to Pokémon Center:** Immediate teleport to your last visited Pokémon Center.
- **Bicycle:** Fast toggle whenever the Bicycle is in your Bag.

### ⚔️ Battle Hotkeys
- **Command Mode:** Hold a hotkey and press D-Pad / Direction keys (`Up`, `Right`, `Left`, `Down`) to directly select **FIGHT**, **PKMN**, **ITEM**, or **RUN**—or choose moves 1–4.
- **Instant Run:** Dedicated hotkey to attempt fleeing directly from the main battle menu.
- **Custom Battle UI Compatible:** Automatically adapts to modded battle UIs (e.g. Floating Battle HUD, Voxel Ascendant) with a floating directional legend and real move names.

---

## Binding & Input Highlights

- **Multi-Button Combos:** Bind chords with up to 4 simultaneous keys or buttons.
- **Reliable Triggers:** Full analog `LT` and `RT` detection with built-in hysteresis.
- **Smart Conflict Resolution:** Exact duplicate bindings auto-evict older assignments. Chord modifiers (e.g. `RT+Y`) take priority without misfiring single-button hotkeys (`Y`).
- **Quick Unassign:** Press **Select** or **Start** on any option to clear its binding, or use **Unassign All** to clear all hotkeys at once.
- **Context-Aware:** Menu and travel hotkeys only fire in the overworld; battle hotkeys only fire during battle.

---

## Installation

1. Download the latest `hotkey_suite.zip` from [Releases](https://github.com/ojsaucer/gen1recomp-hotkey-suite/releases).
2. Place the `hotkey_suite` folder into your `mods/` directory.
3. Enable **Hotkey Suite** in the launcher and configure in **OPTIONS > HOTKEY SUITE**.

---

## License

MIT


