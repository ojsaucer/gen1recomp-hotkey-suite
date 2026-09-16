package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Runtime = require("src.mods.Runtime")
local Data = require("src.core.Data")
Data:load()

local run = T.sdk.loadMod("mods/hotkey_suite", { data = Data })
T.eq(#run.errors, 0, "suite loads clean (" .. tostring(run.errors[1]) .. ")")

local ex = run.loader.exports.hotkey_suite
T.neq(ex, nil, "suite exports are reachable")
T.eq(#ex.features.keyboard, 4, "keyboard includes travel and battle hotkeys")
T.eq(#ex.features.gamepad, 5, "gamepad includes radial, travel, and battle hotkeys")

local expected = {
  keyboard = {
    autofire = true, menu_hotkeys = true, travel = true, battle_hotkeys = true,
  },
  gamepad = {
    autofire = true, menu_hotkeys = true, radial = true, travel = true,
    battle_hotkeys = true,
  },
}
for inputId, wanted in pairs(expected) do
  for _, feature in ipairs(ex.features[inputId]) do wanted[feature.id] = nil end
  T.eq(next(wanted), nil, inputId .. " feature registry is complete")
end

local rows = Runtime.call("ui.options.rows", function(_, value) return value end,
  {}, {})
T.eq(#rows, 1, "suite adds one root OPTIONS row")
T.eq(rows[1].id, "hotkeySuite", "root row is Hotkey Suite")
T.eq(rows[1].value(), "0 ON / 0 SET",
  "root row summarizes active and assigned hotkeys")

for _, id in ipairs({
  "HotkeySuiteInputs", "HotkeySuiteCategories", "HotkeySuiteSettings",
  "HotkeySuiteCapture", "HotkeySuiteRadial",
}) do
  T.neq(run.loader.content.screens:get(id), nil, id .. " is registered")
end
local settings = run.loader.content.screens:get("HotkeySuiteSettings").new(
  { data = Data }, "keyboard", ex.features.keyboard[1])
T.neq(settings.sgbPalettes, nil,
  "custom settings screen implements the renderer palette contract")

local af = ex.shared.autofire
T.eq(af.config().mode, "toggle", "autofire defaults to toggle")
T.eq(af.config().target, "a", "autofire defaults to A")
T.eq(af.config().speed, 2, "missing autofire speed is normalized and assigned")
T.eq(af.speeds[af.config().speed].rate, 10, "autofire defaults to 10/s")
T.eq(af.specs.keyboard:get(), nil, "keyboard autofire starts unbound")
T.eq(af.specs.gamepad:get(), nil, "gamepad autofire starts unbound")
T.eq(ex.shared.radial.spec:get(), nil, "radial menu starts unbound")
T.eq(ex.shared.radial.config().enabled, true, "radial menu defaults on")
T.eq(ex.shared.radial.config().position, "center",
  "radial menu defaults to center")
for _, inputId in ipairs({ "keyboard", "gamepad" }) do
  for _, actionId in ipairs({ "fly", "center", "bike" }) do
    T.eq(ex.shared.travel.specs[inputId][actionId]:get(), nil,
      inputId .. " " .. actionId .. " starts unbound")
  end
  T.eq(ex.shared.battleHotkeys.specs.commands[inputId]:get(), nil,
    inputId .. " battle command mode starts unbound")
  T.eq(ex.shared.battleHotkeys.specs.run[inputId]:get(), nil,
    inputId .. " instant run starts unbound")
end
T.eq(ex.shared.battleHotkeys.config().legendPosition, "top_center",
  "custom battle UI legend defaults to top center")
T.eq(ex.shared.battleHotkeys.config().legendScale, 1,
  "custom battle UI legend defaults to 100 percent")
T.eq(ex.shared.battleHotkeys.commands.up.action, "fight",
  "UP maps to the top-left FIGHT command")
T.eq(ex.shared.battleHotkeys.commands.right.action, "party",
  "RIGHT maps to the top-right PKMN command")
T.eq(ex.shared.battleHotkeys.commands.left.action, "item",
  "LEFT maps to the bottom-left ITEM command")
T.eq(ex.shared.battleHotkeys.commands.down.action, "run",
  "DOWN maps to the bottom-right RUN command")
T.eq(ex.shared.battleHotkeys.customBattleUI({
  bottomUIVisible = function() return false end,
}), true, "hidden native battle UI identifies a custom UI owner")
T.eq(ex.shared.battleHotkeys.customBattleUI({
  bottomUIVisible = function() return true end,
}), false, "visible native battle UI keeps native arrow placement")
for _, actionId in ipairs({ "fly", "center", "bike" }) do
  T.eq(ex.shared.travel.config().touch[actionId], nil,
    "touch " .. actionId .. " starts off")
end
local afRows = ex.features.keyboard[1].rows({}, "keyboard")
T.neq(afRows[#afRows].unassign, nil, "hotkey rows expose SELECT-to-unassign")

local menuSpec = ex.shared.menuHotkeys.ensureSpec("keyboard", "pokedex")
T.eq(ex.shared.bindingAllowed("gamepad", {
  { input = "gamepad", name = "a" },
}), false, "gamepad A cannot be assigned by itself")
T.eq(ex.shared.bindingAllowed("gamepad", {
  { input = "gamepad", name = "b" },
  { input = "gamepad", name = "leftshoulder" },
}), true, "gamepad A/B remain available in combinations")
ex.shared.setBinding(af.specs.keyboard, {
  { input = "keyboard", name = "k" },
  { input = "keyboard", name = "leftctrl" },
})
T.eq(ex.shared.comboLabel(af.specs.keyboard:get()), "K+LEFTCTRL",
  "combination labels use canonical ordering")
ex.shared.setBinding(menuSpec, {
  { input = "keyboard", name = "leftctrl" },
  { input = "keyboard", name = "k" },
})
T.eq(af.specs.keyboard:get(), nil,
  "an exact combination assigned elsewhere evicts the old binding")
T.neq(menuSpec:get(), nil, "the newly assigned combination is retained")
ex.shared.setBinding(menuSpec, nil)

T.eq(ex.shared.triggerStep(false, 0.34), nil, "LT stays released below press threshold")
T.eq(ex.shared.triggerStep(false, 0.35), true, "LT presses at the lower threshold")
T.eq(ex.shared.triggerStep(true, 0.21), nil, "LT remains held above release threshold")
T.eq(ex.shared.triggerStep(true, 0.20), false, "LT releases at the lower threshold")

local chordFires, singleFires = 0, 0
local chordBinding = {
  { input = "gamepad", name = "triggerleft" },
  { input = "gamepad", name = "triggerright" },
}
local chordSpec = ex.shared.registerHotkey({
  id = "test.trigger.chord", input = "gamepad", context = "any",
  get = function() return chordBinding end,
  set = function(value) chordBinding = value end,
  onFire = function() chordFires = chordFires + 1 end,
})
local singleBinding = { { input = "gamepad", name = "x" } }
local singleSpec = ex.shared.registerHotkey({
  id = "test.single", input = "gamepad", context = "any",
  get = function() return singleBinding end,
  set = function(value) singleBinding = value end,
  onFire = function() singleFires = singleFires + 1 end,
})
ex.shared.dispatchInput("gamepad", "triggerleft", true, {}, {})
T.eq(chordFires, 0, "holding the first trigger does not fire a chord early")
ex.shared.dispatchInput("gamepad", "triggerright", true, {}, {})
T.eq(chordFires, 1, "pressing the second trigger completes a held chord")
ex.shared.dispatchInput("gamepad", "triggerright", false, {}, {})
ex.shared.dispatchInput("gamepad", "triggerleft", false, {}, {})
ex.shared.dispatchInput("gamepad", "x", true, {}, {})
T.eq(singleFires, 1, "single-button gamepad hotkeys remain supported")
ex.shared.dispatchInput("gamepad", "x", false, {}, {})
ex.shared.setBinding(chordSpec, nil)
ex.shared.setBinding(singleSpec, nil)

local specificFires, subsetFires = 0, 0
local specificBinding = {
  { input = "gamepad", name = "triggerright" },
  { input = "gamepad", name = "y" },
}
local specificSpec = ex.shared.registerHotkey({
  id = "test.specific.chord", input = "gamepad", context = "any",
  get = function() return specificBinding end,
  set = function(value) specificBinding = value end,
  onFire = function() specificFires = specificFires + 1 end,
})
local subsetBinding = { { input = "gamepad", name = "y" } }
local subsetSpec = ex.shared.registerHotkey({
  id = "test.specific.single", input = "gamepad", context = "any",
  get = function() return subsetBinding end,
  set = function(value) subsetBinding = value end,
  onFire = function() subsetFires = subsetFires + 1 end,
})
ex.shared.dispatchInput("gamepad", "triggerright", true, {}, {})
ex.shared.dispatchInput("gamepad", "y", true, {}, {})
T.eq(specificFires, 1, "held modifier plus final input fires the combination")
T.eq(subsetFires, 0, "completed combination suppresses its single-input subset")
ex.shared.dispatchInput("gamepad", "y", false, {}, {})
ex.shared.dispatchInput("gamepad", "triggerright", false, {}, {})
ex.shared.dispatchInput("gamepad", "y", true, {}, {})
T.eq(subsetFires, 1, "single-input hotkey still fires without its modifier")
ex.shared.dispatchInput("gamepad", "y", false, {}, {})
ex.shared.setBinding(specificSpec, nil)
ex.shared.setBinding(subsetSpec, nil)

T.eq(ex.shared.context({ stack = { states = { { isOverworld = true } } } }),
  "overworld", "overworld context is recognized")
T.eq(ex.shared.context({ stack = { states = {
  { isOverworld = true }, { screenId = "BattleMenu" },
} } }), "battle", "battle overlays override the overworld context")

local passthroughCalls, hotkeyCalls = 0, 0
local testBinding = { { input = "keyboard", name = "a" } }
local passthroughSpec = ex.shared.registerHotkey({
  id = "test.passthrough",
  input = "keyboard",
  context = "any",
  get = function() return testBinding end,
  set = function(value) testBinding = value end,
  onFire = function() hotkeyCalls = hotkeyCalls + 1 end,
})
Runtime.call("input.key", function()
  passthroughCalls = passthroughCalls + 1
end, {}, { phase = "pressed", key = "a" })
T.eq(passthroughCalls, 1, "assigned hotkeys preserve vanilla input handling")
T.eq(hotkeyCalls, 1, "assigned hotkeys still fire after vanilla handling")
ex.shared.setBinding(passthroughSpec, nil)

local fakeGame = { save = { player = { name = "BLUE" } } }
Runtime.call("ui.start_menu.items", function(_, value) return value end, fakeGame, {
  { id = "modded_menu", label = "MODDED", activate = function() end },
  { label = "ASCENDANT", onSelect = function() end },
})
T.eq(ex.shared.startMenuItems(fakeGame)[1].id, "modded_menu",
  "hook-discovered modded START-menu items remain available")
T.eq(ex.shared.startMenuItems(fakeGame)[2].id, "ascendant",
  "final aggregated custom START-menu entries remain available")
T.eq(ex.shared.stableMenuId({}, { label = "POKéDEX" }, 1), "pokedex",
  "accented Pokédex label gets a stable action id")
T.eq(ex.shared.stableMenuId({ save = { player = { name = "BLUE" } } },
  { label = "BLUE" }, 6), "trainer_card",
  "player-name menu entry gets a stable trainer-card id")

local clearBinding = { { input = "keyboard", name = "q" } }
local clearSpec = ex.shared.registerHotkey({
  id = "test.clear.all", input = "keyboard", context = "any",
  get = function() return clearBinding end,
  set = function(value) clearBinding = value end,
  onFire = function() end,
})
ex.shared.clearAllBindings()
T.eq(clearSpec:get(), nil, "suite-wide unassign clears registered hotkeys")

T.finish("hotkey_suite_test")
