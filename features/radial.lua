return function(mod, suite)
  local shared = suite.shared
  local Font = require("src.render.Font")
  local Screens = require("src.ui.Screens")
  local active
  local POSITIONS = {
    "top_left", "top_center", "top_right",
    "center_left", "center", "center_right",
    "bottom_left", "bottom_center", "bottom_right",
  }
  local POSITION_LABELS = {
    top_left = "TOP LEFT", top_center = "TOP CENTER",
    top_right = "TOP RIGHT", center_left = "CENTER LEFT",
    center = "CENTER", center_right = "CENTER RIGHT",
    bottom_left = "BOTTOM LEFT", bottom_center = "BOTTOM CENTER",
    bottom_right = "BOTTOM RIGHT",
  }

  local function config()
    local cfg = mod.save:get("radial", {})
    if type(cfg) ~= "table" then cfg = {} end
    if cfg.enabled == nil then cfg.enabled = false end
    cfg.stick = cfg.stick == "right" and "right" or "left"
    if not POSITION_LABELS[cfg.position] then cfg.position = "center" end
    return cfg
  end
  local function save(cfg) mod.save:set("radial", cfg) end

  local function neutralize(screen)
    if screen then
      shared.neutralizeStick(screen.game, screen.joystick, screen.stick)
    end
  end

  local Screen = {}
  Screen.__index = Screen
  Screen.isOpaque = false
  function Screen:sgbPalettes(game)
    return require("src.render.PaletteFX").wholeNamed(game.data, "MEWMON")
  end
  function Screen:update(dt) self.fade = math.min(1, self.fade + dt * 12) end
  function Screen:setAxis(axis, value)
    local stick = (axis == "leftx" or axis == "lefty") and "left"
      or ((axis == "rightx" or axis == "righty") and "right")
    if stick ~= self.stick then return end
    if axis:sub(-1) == "x" then self.x = value else self.y = value end
    if math.sqrt(self.x * self.x + self.y * self.y) < 0.35 then
      self.selected = nil
      return
    end
    local atan2 = math.atan2 or math.atan
    local angle = atan2(self.y, self.x)
    self.selected = (math.floor((angle + math.pi / #self.items)
      / (2 * math.pi / #self.items)) % #self.items) + 1
  end
  function Screen:close(activate)
    local item = activate and self.selected and self.items[self.selected]
    neutralize(self)
    if self.game.stack:top() == self then self.game.stack:pop() end
    if active == self then active = nil end
    if item then shared.activateMenuItem(self.game, item.id) end
  end
  local function drawBox(x, y, w, h)
    local g = love.graphics
    local r, green, b, a = g.getColor()
    g.setColor(1, 1, 1, 1)
    g.rectangle("fill", x, y, w, h)
    g.setColor(r, green, b, a)
    local border = Font.BORDER
    Font.drawCode(border.tl, x, y)
    Font.drawCode(border.tr, x + w - 8, y)
    Font.drawCode(border.bl, x, y + h - 8)
    Font.drawCode(border.br, x + w - 8, y + h - 8)
    for dx = 8, w - 16, 8 do
      Font.drawCode(border.h, x + dx, y)
      Font.drawCode(border.h, x + dx, y + h - 8)
    end
    Font.drawCode(border.v, x, y + 8)
    Font.drawCode(border.v, x + w - 8, y + 8)
  end
  local function centerFor(position)
    local x = position:find("left", 1, true) and 56
      or position:find("right", 1, true) and 104 or 80
    local y = position:find("top", 1, true) and 52
      or position:find("bottom", 1, true) and 92 or 72
    return x, y
  end
  function Screen:draw()
    local g = love.graphics
    local cfg = config()
    local centerX, centerY = centerFor(cfg.position)
    local minX, maxX = -centerX, 160 - centerX
    local minY, maxY = -centerY, 144 - centerY
    g.push()
    g.translate(centerX, centerY)
    local function drawItem(i, item, selected)
      local angle = (i - 1) * 2 * math.pi / #self.items
      local anchorX = math.cos(angle) * 44
      local anchorY = math.sin(angle) * 44
      local label = selected and item.label or item.label:sub(1, 3)
      local textWidth = Font.width(label)
      local x = math.floor(anchorX - textWidth / 2)
      local y = math.floor(anchorY - 4)
      x = math.max(minX, math.min(maxX - textWidth, x))
      if selected then
        local w = math.min(maxX - minX,
          math.max(24, math.ceil((textWidth + 16) / 8) * 8))
        local boxX = math.floor(anchorX - w / 2 + 0.5)
        local boxY = math.floor(anchorY - 12 + 0.5)
        boxX = math.max(minX, math.min(maxX - w, boxX))
        boxY = math.max(minY, math.min(maxY - 24, boxY))
        g.setColor(1, 1, 1, 1)
        drawBox(boxX, boxY, w, 24)
        g.setColor(0, 0, 0, 1)
        x = boxX + math.floor((w - textWidth) / 2)
        y = boxY + 8
      else
        g.setColor(1, 1, 1, 1)
      end
      Font.draw(label, x, y)
    end
    for i, item in ipairs(self.items) do
      if i ~= self.selected then drawItem(i, item, false) end
    end
    if self.selected and self.items[self.selected] then
      drawItem(self.selected, self.items[self.selected], true)
    end
    g.pop()
    g.setColor(1, 1, 1, 1)
  end

  local function open(game, ev)
    if active or not config().enabled or not shared.canOpenMenu(game) then
      return false
    end
    local items = shared.refreshStartMenuItems(game)
    if #items == 0 then return false end
    local cfg = config()
    Screens.push(game, "HotkeySuiteRadial", items, cfg.stick, ev and ev.joystick)
    neutralize(active)
    return true
  end

  mod.content.screens:register("HotkeySuiteRadial", {
    new = function(game, items, stick, joystick)
      active = setmetatable({
        game = game, items = items, stick = stick, joystick = joystick,
        x = 0, y = 0, fade = 0,
      }, Screen)
      return active
    end,
  })

  local spec = shared.registerHotkey({
    id = "radial.gamepad",
    input = "gamepad",
    context = "overworld",
    enabled = function() return config().enabled end,
    get = function() return config().binding end,
    set = function(value)
      local cfg = config()
      cfg.binding = value
      save(cfg)
      if active then active:close(false) end
    end,
    onFire = function(game, ev) open(game, ev) end,
    onBreak = function()
      if active then active:close(true) end
    end,
  })

  mod.hooks:wrap("input.gamepad", function(next, game, ev)
    if ev.phase == "axis" and active
        and (ev.axis == active.stick .. "x" or ev.axis == active.stick .. "y") then
      active:setAxis(ev.axis, ev.value or 0)
      local neutral = {}
      for key, value in pairs(ev) do neutral[key] = value end
      neutral.value = 0
      return next(game, neutral)
    end
    return next(game, ev)
  end)

  mod.hooks:wrap("screen.render_visible", function(next, screen)
    if active then
      local found = false
      local states = active.game and active.game.stack and active.game.stack.states
      for _, state in ipairs(states or {}) do
        if state == active then found = true break end
      end
      if not found then active = nil end
    end
    local base = active and active.game and active.game.stack
      and active.game.stack.states and active.game.stack.states[1]
    if active and screen ~= active and screen ~= base then
      return false
    end
    return next(screen)
  end)

  suite.register("gamepad", {
    id = "radial", label = "RADIAL MENU",
    rows = function()
      return {
        shared.enabledRow("radialEnabled",
          function() return config().enabled end,
          function(value)
            local cfg = config()
            cfg.enabled = value
            save(cfg)
            if not value and active then active:close(false) end
          end),
        { id = "radialBinding", label = "HOTKEY",
          value = function() return shared.comboLabel(spec:get()) end,
          activate = function(game)
            shared.captureCombo(game, "RADIAL HOTKEY", spec)
          end,
          unassign = function() shared.setBinding(spec, nil); return true end },
        { id = "radialStick", label = "STICK",
          value = function() return config().stick:upper() end,
          step = function(_, dir)
            local cfg = config()
            cfg.stick = shared.cycle({ "left", "right" }, cfg.stick, dir)
            save(cfg)
            return true
          end },
        { id = "radialPosition", label = "POSITION",
          value = function() return POSITION_LABELS[config().position] end,
          step = function(_, dir)
            local cfg = config()
            cfg.position = shared.cycle(POSITIONS, cfg.position, dir)
            save(cfg)
            return true
          end },
      }
    end,
  })

  shared.registerReset(function()
    local cfg = config()
    cfg.enabled = false
    save(cfg)
    if active then active:close(false) end
  end)

  shared.radial = {
    spec = spec, config = config, active = function() return active end,
  }
end
