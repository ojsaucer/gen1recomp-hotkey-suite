local OptionsMenu = require("src.ui.OptionsMenu")
local OptionRows = require("src.ui.OptionRows")
local PaletteFX = require("src.render.PaletteFX")
local Screens = require("src.ui.Screens")
local Strings = require("src.core.Strings")
local TextBox = require("src.render.TextBox")

local INPUTS = {
  { id = "keyboard", label = "KEYBOARD" },
  { id = "gamepad", label = "GAMEPAD" },
}

local SettingsScreen = {}
SettingsScreen.__index = SettingsScreen
SettingsScreen.isOpaque = true

function SettingsScreen:sgbPalettes(game)
  return PaletteFX.wholeNamed(game.data, "MEWMON")
end

function SettingsScreen:update()
  local input = self.game.input
  local cancel = #self.rows + 1
  if input:wasPressed("up") then
    self.index = self.index > 1 and self.index - 1 or cancel
  elseif input:wasPressed("down") then
    self.index = self.index < cancel and self.index + 1 or 1
  elseif input:wasPressed("select") or input:wasPressed("start") then
    local row = self.rows[self.index]
    if row and row.unassign then
      row.unassign(self.game)
    elseif input:wasPressed("start") then
      self.game.stack:pop()
    end
  elseif input:wasPressed("left") or input:wasPressed("right")
      or input:wasPressed("a") then
    local row = self.rows[self.index]
    local dir = input:wasPressed("left") and -1 or 1
    if row and row.activate and input:wasPressed("a") then row.activate(self.game)
    elseif row and row.step then row.step(self.game, dir)
    elseif not row and input:wasPressed("a") then self.game.stack:pop() end
  elseif input:wasPressed("b") then
    self.game.stack:pop()
  end
  self.scroll = OptionRows.clampScroll(self.index, self.scroll, #self.rows, cancel)
end

function SettingsScreen:draw()
  OptionRows.draw(self.game, self.rows, self.index, self.scroll, Strings("BACK"),
    #self.rows + 1)
end

return function(mod)
  local suite = { features = {}, shared = {} }

  for _, input in ipairs(INPUTS) do
    suite.features[input.id] = {}
  end

  function suite.register(inputId, feature)
    assert(suite.features[inputId], "unknown input type: " .. tostring(inputId))
    assert(type(feature) == "table" and feature.id and feature.label
      and type(feature.rows) == "function", "invalid suite feature")
    suite.features[inputId][#suite.features[inputId] + 1] = feature
  end

  function suite.openSettings(game, inputId, feature)
    Screens.push(game, "HotkeySuiteSettings", inputId, feature)
  end

  function suite.load(relative)
    local source = assert(mod:read(relative), "unable to read " .. relative)
    local chunk = assert(loadstring(source, "@" .. relative))
    local install = assert(chunk(), relative .. " must return an installer")
    install(mod, suite)
  end

  mod.content.screens:register("HotkeySuiteInputs", {
    new = function(game)
      local rows = {}
      for _, input in ipairs(INPUTS) do
        local current = input
        rows[#rows + 1] = {
          id = "hotkeySuite." .. current.id,
          label = Strings(current.label),
          activate = function(g)
            Screens.push(g, "HotkeySuiteCategories", current.id)
          end,
        }
      end
      rows[#rows + 1] = {
        id = "hotkeySuite.unassignAll",
        label = Strings("UNASSIGN ALL"),
        activate = function(g)
          g.stack:push(TextBox.new(g,
            "Unassign all\nsuite hotkeys?", nil, {
              defaultNo = true,
              choice = function(yes)
                if yes then suite.shared.clearAllBindings() end
              end,
            }))
        end,
      }
      return OptionsMenu.new(game, { rows = rows })
    end,
  })

  mod.content.screens:register("HotkeySuiteCategories", {
    new = function(game, inputId)
      local rows = {}
      for _, feature in ipairs(suite.features[inputId] or {}) do
        local current = feature
        rows[#rows + 1] = {
          id = "hotkeySuite." .. inputId .. "." .. current.id,
          label = Strings(current.label),
          activate = function(g) suite.openSettings(g, inputId, current) end,
        }
      end
      return OptionsMenu.new(game, { rows = rows })
    end,
  })

  mod.content.screens:register("HotkeySuiteSettings", {
    new = function(game, inputId, feature)
      return setmetatable({
        game = game, rows = feature.rows(game, inputId), index = 1, scroll = 0,
      }, SettingsScreen)
    end,
  })

  suite.load("features/shared.lua")
  suite.load("features/autofire.lua")
  suite.load("features/menu_hotkeys.lua")
  suite.load("features/radial.lua")
  suite.load("features/travel.lua")
  suite.load("features/command_menu.lua")
  suite.load("features/ball_menu.lua")

  mod.hooks:wrap("ui.options.rows", function(next, game, rows)
    local out = next(game, rows)
    if type(out) ~= "table" then return out end
    return mod.ui.insertBefore(out, "MODS", {
      id = "hotkeySuite",
      label = Strings("HOTKEY SUITE"),
      value = function()
        local _, assigned = suite.shared.hotkeySummary()
        return assigned .. " SET"
      end,
      activate = function(g) Screens.push(g, "HotkeySuiteInputs") end,
    })
  end)

  -- Kanto Ascendant relocates any Start Menu item flagged `ascendantMenu`
  -- into its own START MENU > ASCENDANT hub (see its ascendant_menu.lua
  -- collector), the same soft-integration contract Voxel Ascendant uses to
  -- appear there without owning its own top-level row. When Kanto Ascendant
  -- is not installed, nothing reads these extra fields, so this still shows
  -- up as an ordinary Start Menu entry that opens the same settings screen.
  --
  -- Kanto Ascendant's own aggregator calls `item.onSelect()` with NO
  -- arguments (its internal rows capture their own `game` reference instead
  -- of receiving one), so `onSelect` must close over `game` from this hook
  -- rather than expect it as a parameter. Relying on a parameter here left
  -- `game` nil when opened through ASCENDANT, and `Screens.push(nil, ...)`
  -- fell through to a bare `require("src.ui.HotkeySuiteInputs")`, which does
  -- not exist as a built-in screen module.
  mod.hooks:wrap("ui.start_menu.items", function(next, game, items)
    local out = next(game, items)
    if type(out) ~= "table" then return out end
    out[#out + 1] = {
      id = "hotkey_suite_ascendant",
      label = Strings("HOTKEY SUITE"),
      ascendantMenu = true,
      ascendantLabel = Strings("HOTKEY SUITE"),
      ascendantGroup = "events",
      ascendantHelp = Strings(
        "Configure keyboard and gamepad hotkeys for Autofire Hotkeys, Menu "
        .. "Hotkeys, Radial Menu, Travel Hotkeys, Battle Command Menu, and "
        .. "Ball Menu."),
      onSelect = function() Screens.push(game, "HotkeySuiteInputs") end,
    }
    return out
  end)

  mod.exports.registerFeature = suite.register
  mod.exports.features = suite.features
  mod.exports.shared = suite.shared
  mod.log:info("Hotkey Suite initialized")
end
