local OptionsMenu = require("src.ui.OptionsMenu")
local Font = require("src.render.Font")
local Marquee = require("src.ui.Marquee")
local PaletteFX = require("src.render.PaletteFX")
local Screens = require("src.ui.Screens")
local Strings = require("src.core.Strings")
local TextBox = require("src.render.TextBox")
local Theme = require("src.ui.Theme")

-- src.ui.OptionRows is a Gen 1 only module with no Gen 2 adapter, so requiring
-- it would keep the whole suite off Gold.  It is a small leaf that depends on
-- nothing generation-specific (Font, Marquee, Theme are shared), so the two
-- entry points the settings screen uses are vendored here verbatim instead.
local OptionRows = { VISIBLE = 4 }

-- Font.drawBox(0, y, 20, 4) spends column 19 on the frame, so a line drawn to
-- the 160px screen edge prints over its own border.
local CONTENT_RIGHT = 152
local function fits(x) return math.floor((CONTENT_RIGHT - x) / 8) end

function OptionRows.clampScroll(index, scroll, total)
  if index <= scroll then
    return index - 1
  elseif index > scroll + OptionRows.VISIBLE then
    return index - OptionRows.VISIBLE
  end
  return scroll
end

function OptionRows.draw(game, rows, index, scroll)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)
  for slot = 1, OptionRows.VISIBLE do
    local i = scroll + slot
    local row = rows[i]
    if not row then break end
    Font.drawBox(0, (slot - 1) * 4, 20, 4)
    love.graphics.setColor(0, 0, 0, 1)
    local label = row.label or ""
    local value = row.value and row.value(game) or ""
    if i == index then
      local key = tostring(row.id or row.label) .. "\0" .. tostring(value)
      label = Marquee.scroll(label, fits(16), key)
      value = Marquee.scroll(value, fits(24), key)
    else
      label = Marquee.clip(label, fits(16))
      value = Marquee.clip(value, fits(24))
    end
    Font.draw(label, 16, ((slot - 1) * 4 + 1) * 8)
    Font.draw(value, 24, ((slot - 1) * 4 + 2) * 8)
    if i == index then
      Font.drawCode(Theme.cursor, 8, ((slot - 1) * 4 + 1) * 8)
    end
  end
  if scroll + OptionRows.VISIBLE < #rows then
    Font.drawCode(Theme.moreArrow, 144, 128)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

local INPUTS = {
  { id = "keyboard", label = "KEYBOARD" },
  { id = "gamepad", label = "GAMEPAD" },
}

-- Modules are grouped by where the player actually uses them, so the list
-- stays navigable as more of them ship.
local CONTEXTS = {
  { id = "overworld", label = "OVERWORLD" },
  { id = "battle", label = "BATTLE" },
  { id = "general", label = "GENERAL" },
}
local DEFAULT_CONTEXT = "general"

-- A row is a hotkey binding when it can both open the capture screen and be
-- cleared; that is what decides whether the SELECT half of the legend applies.
local function hasBindings(rows)
  for _, row in ipairs(rows or {}) do
    if type(row.activate) == "function" and type(row.unassign) == "function" then
      return true
    end
  end
  return false
end

-- TextBox.paginate only starts a new PAGE at a form feed; *within* a page it
-- advances line to line with no button press, scrolling a hard two-line
-- window (TextBox:beginLine drops shown[1] once two lines are up). A help
-- string carrying no markers therefore types straight through every line it
-- wraps to and leaves only its last two on screen.
--
-- So the wrapping is done here, with the engine's own paginator at the
-- engine's own width (which respects a themed box), and the result is
-- regrouped into explicit two-line pages. Each page then ends on the normal
-- "waiting" branch and holds for A.
local function paginateHelp(text)
  local lines = {}
  for _, page in ipairs(TextBox.paginate(text)) do
    for _, line in ipairs(page) do
      -- the soft wrap cuts *on* the space, so it rides along on the line end
      local trimmed = line:gsub("%s+$", "")
      if trimmed ~= "" then lines[#lines + 1] = trimmed end
    end
  end
  if #lines == 0 then return text end
  local pages = {}
  for i = 1, #lines, 2 do
    pages[#pages + 1] = table.concat(lines, "\n", i, math.min(i + 1, #lines))
  end
  return table.concat(pages, "\f")
end

local SettingsScreen = {}
SettingsScreen.__index = SettingsScreen
SettingsScreen.isOpaque = true
-- Read by the input broker: suite hotkeys must not fire while the player is
-- editing them.
SettingsScreen.isHotkeySuiteScreen = true

function SettingsScreen:sgbPalettes(game)
  return PaletteFX.wholeNamed(game.data, "MEWMON")
end

function SettingsScreen:update()
  local input = self.game.input
  local total = #self.rows
  local row = self.rows[self.index]
  if total == 0 then
    if input:wasPressed("b") then self.game.stack:pop() end
    return
  end
  if input:wasPressed("up") then
    self.index = self.index > 1 and self.index - 1 or total
  elseif input:wasPressed("down") then
    self.index = self.index < total and self.index + 1 or 1
  elseif input:wasPressed("start") then
    if row and row.help then
      local box = TextBox.new(self.game, paginateHelp(row.help))
      -- Found by shared.suiteScreenOpen's stack scan, so nothing the suite
      -- synthesizes can advance the help text out from under the player.
      box.isHotkeySuiteScreen = true
      self.game.stack:push(box)
    end
  elseif input:wasPressed("select") then
    if row and row.unassign then row.unassign(self.game) end
  elseif input:wasPressed("a") then
    if row and row.activate then row.activate(self.game)
    elseif row and row.step then row.step(self.game, 1) end
  elseif input:wasPressed("left") or input:wasPressed("right") then
    local dir = input:wasPressed("left") and -1 or 1
    if row and row.step then row.step(self.game, dir) end
  elseif input:wasPressed("b") then
    self.game.stack:pop()
  end
  self.scroll = OptionRows.clampScroll(self.index, self.scroll, total)
end

-- OptionRows keeps the bottom line for its own label; B already backs out of
-- every suite screen, so that line carries the controls legend instead.
function SettingsScreen:draw()
  OptionRows.draw(self.game, self.rows, self.index, self.scroll)
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(self.legend, 8, 136)
  love.graphics.setColor(1, 1, 1, 1)
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
    feature.context = feature.context or DEFAULT_CONTEXT
    suite.features[inputId][#suite.features[inputId] + 1] = feature
  end

  local function featuresFor(inputId, contextId)
    local out = {}
    for _, feature in ipairs(suite.features[inputId] or {}) do
      if (feature.context or DEFAULT_CONTEXT) == contextId then
        out[#out + 1] = feature
      end
    end
    return out
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
            Screens.push(g, "HotkeySuiteContexts", current.id)
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
    new = function(game, inputId, contextId)
      local rows = {}
      for _, feature in ipairs(featuresFor(inputId, contextId)) do
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

  -- OVERWORLD / BATTLE / GENERAL. A context with no modules registered for
  -- this input type is left out rather than opening an empty list.
  mod.content.screens:register("HotkeySuiteContexts", {
    new = function(game, inputId)
      local rows = {}
      for _, context in ipairs(CONTEXTS) do
        local current = context
        if #featuresFor(inputId, current.id) > 0 then
          rows[#rows + 1] = {
            id = "hotkeySuite." .. inputId .. "." .. current.id,
            label = Strings(current.label),
            activate = function(g)
              Screens.push(g, "HotkeySuiteCategories", inputId, current.id)
            end,
          }
        end
      end
      return OptionsMenu.new(game, { rows = rows })
    end,
  })

  mod.content.screens:register("HotkeySuiteSettings", {
    new = function(game, inputId, feature)
      local rows = feature.rows(game, inputId)
      return setmetatable({
        game = game, rows = rows, index = 1, scroll = 0,
        legend = hasBindings(rows) and "SEL:CLEAR ST:HELP" or "ST:HELP",
      }, SettingsScreen)
    end,
  })

  suite.load("features/shared.lua")
  suite.load("features/gen.lua")
  suite.load("features/autofire.lua")
  suite.load("features/menu_hotkeys.lua")
  suite.load("features/radial.lua")
  suite.load("features/travel.lua")
  suite.load("features/command_menu.lua")
  suite.load("features/ball_menu.lua")
  suite.load("features/battle_text.lua")

  -- Every spec compiled its combination while the store was being read for
  -- the first time; recompile once now that all of them are registered.
  suite.shared.refreshHotkeys()

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

  -- No Start Menu entry is added. Kanto Ascendant's collector only files an
  -- item under one of four hardcoded groups (quests / research / partners /
  -- events), and its ASCENDANT > SETTINGS screen builds its children from a
  -- private registry with no third-party injection point, so there is no way
  -- to reach a placement that makes contextual sense. OPTIONS > HOTKEY SUITE
  -- is the canonical entry point and is reachable on every install.

  mod.exports.registerFeature = suite.register
  mod.exports.features = suite.features
  mod.exports.shared = suite.shared
  mod.log:info("Hotkey Suite initialized")
end
