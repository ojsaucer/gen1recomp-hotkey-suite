return function(mod, suite)
  local shared = suite.shared
  local Font = require("src.render.Font")
  local Screens = require("src.ui.Screens")
  local active

  local function optional(name)
    local ok, module = pcall(require, name)
    if ok and type(module) == "table" then return module end
    return nil
  end
  -- Red and Gold push the radial as a Gen 1 chrome screen (below); FireRed has
  -- no `game.stack` to push it onto, so it gets its own layer on FireRed's
  -- own modal stack instead, drawn with the same Chrome.mapPopupFrame +
  -- FrlgFont pairing the restyled autofire badge uses.
  local Stack = optional("src.ui.game3.stack")
  local Chrome = optional("src.ui.game3.chrome")
  local FrlgFont = optional("src.ui.game3.frlg_font")

  -- Shared between both presentations: which slice of the wheel a stick
  -- deflection lands on, and where the wheel's own center sits for a given
  -- corner/edge/center position on a `w`x`h` frame. Gen 1/2 call this at
  -- 160x144; Gen 3 calls it at FireRed's own 240x160.
  local function computeSelection(itemCount, x, y)
    if math.sqrt(x * x + y * y) < 0.35 then return nil end
    local atan2 = math.atan2 or math.atan
    local angle = atan2(y, x)
    return (math.floor((angle + math.pi / itemCount) / (2 * math.pi / itemCount))
      % itemCount) + 1
  end
  local function centerFor(position, w, h)
    local x = position:find("left", 1, true) and w * 0.35
      or position:find("right", 1, true) and w * 0.65 or w * 0.5
    local y = position:find("top", 1, true) and h * 0.3611
      or position:find("bottom", 1, true) and h * 0.6389 or h * 0.5
    return math.floor(x + 0.5), math.floor(y + 0.5)
  end
  local RADIUS = 44

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
    local cfg = shared.store.get("radial", nil)
    if type(cfg) ~= "table" then cfg = {} end
    if cfg.enabled == nil then cfg.enabled = false end
    cfg.stick = cfg.stick == "right" and "right" or "left"
    if not POSITION_LABELS[cfg.position] then cfg.position = "center" end
    return cfg
  end
  local function save(cfg) shared.store.set("radial", cfg) end

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
    self.selected = computeSelection(#self.items, self.x, self.y)
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
  function Screen:draw()
    local g = love.graphics
    local cfg = config()
    local centerX, centerY = centerFor(cfg.position, 160, 144)
    local minX, maxX = -centerX, 160 - centerX
    local minY, maxY = -centerY, 144 - centerY
    g.push()
    g.translate(centerX, centerY)
    local function drawItem(i, item, selected)
      local angle = (i - 1) * 2 * math.pi / #self.items
      local anchorX = math.cos(angle) * RADIUS
      local anchorY = math.sin(angle) * RADIUS
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

  -- ------------------------------------------------------------- Gen 3 wheel
  --
  -- FireRed's modal UI lives on src/ui/game3/stack.lua, a layer stack whose
  -- draw/update/handleInput the engine calls directly off `layer.mod` with no
  -- receiver (UiPass.drawUi's `tryDraw` calls `mod.draw()`, not `mod:draw()`).
  -- A singleton table with plain functions -- the same shape gen3_ui.lua's
  -- own `UI` uses -- fits that calling convention; `Gen3Radial:setAxis` and
  -- `Gen3Radial:close` stay colon methods below purely because only this
  -- file ever calls them, the same way `active:close(...)` already does for
  -- Gen 1's Screen.
  local Gen3Radial = { fade = 0 }

  function Gen3Radial:setAxis(axis, value)
    local stick = (axis == "leftx" or axis == "lefty") and "left"
      or ((axis == "rightx" or axis == "righty") and "right")
    if stick ~= self.stick then return end
    if axis:sub(-1) == "x" then self.x = value else self.y = value end
    self.selected = computeSelection(#self.items, self.x, self.y)
  end

  function Gen3Radial:close(activate)
    local item = activate and self.selected and self.items[self.selected]
    neutralize(self)
    if Stack then Stack.pop("hotkey_suite_radial") end
    if active == self then active = nil end
    if item then shared.activateMenuItem(self.game, item.id) end
  end

  -- Consumes input outright while the wheel is up, the same as a Gen 1
  -- opaque screen would: the wheel is driven entirely by the stick and the
  -- hotkey's own release (onBreak, below), so there is nothing here for a
  -- button press to do, and letting one fall through to Hud's own dispatch
  -- would let START open the real Start Menu on top of the wheel.
  function Gen3Radial.handleInput(_input) end

  function Gen3Radial.update(dt)
    Gen3Radial.fade = math.min(1, (Gen3Radial.fade or 0) + (dt or 0) * 12)
    -- A layer only leaves the stack through Gen3Radial:close, except a hard
    -- reset (returning to the title screen calls Stack.clear()) -- catch that
    -- case too, so a stale `active` cannot block every later hotkey press.
    if active == Gen3Radial and Stack and not Stack.has("hotkey_suite_radial") then
      active = nil
    end
  end

  function Gen3Radial.draw()
    local items = Gen3Radial.items
    if not (items and #items > 0 and Chrome and FrlgFont) then return end
    local g = love.graphics
    local cfg = config()
    local centerX, centerY = centerFor(cfg.position, 240, 160)
    local minX, maxX = -centerX, 240 - centerX
    local minY, maxY = -centerY, 160 - centerY
    g.push()
    g.translate(centerX, centerY)
    local function drawItem(i, item, selected)
      local angle = (i - 1) * 2 * math.pi / #items
      local anchorX = math.cos(angle) * RADIUS
      local anchorY = math.sin(angle) * RADIUS
      local label = selected and item.label or item.label:sub(1, 3)
      local textWidth = FrlgFont.measure(label)
      if selected then
        local tiles = math.max(1, math.ceil((textWidth + 8) / 8))
        local contentW = tiles * 8
        local boxW, boxH = (tiles + 2) * 8, 24
        local boxX = math.floor(anchorX - boxW / 2 + 0.5)
        local boxY = math.floor(anchorY - boxH / 2 + 0.5)
        boxX = math.max(minX, math.min(maxX - boxW, boxX))
        boxY = math.max(minY, math.min(maxY - boxH, boxY))
        Chrome.mapPopupFrame(boxX, boxY, tiles)
        local textX = boxX + 8 + math.floor((contentW - textWidth) / 2)
        FrlgFont.draw(label, textX, boxY + 5,
          { colors = FrlgFont.COLOR.NORMAL, maxWidth = contentW })
      else
        local x = math.floor(anchorX - textWidth / 2)
        local y = math.floor(anchorY - 4)
        x = math.max(minX, math.min(maxX - textWidth, x))
        y = math.max(minY, math.min(maxY - 8, y))
        FrlgFont.draw(label, x, y, { colors = FrlgFont.COLOR.WHITE })
      end
    end
    for i, item in ipairs(items) do
      if i ~= Gen3Radial.selected then drawItem(i, item, false) end
    end
    if Gen3Radial.selected and items[Gen3Radial.selected] then
      drawItem(Gen3Radial.selected, items[Gen3Radial.selected], true)
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
    if shared.chromeAvailable(game) then
      Screens.push(game, "HotkeySuiteRadial", items, cfg.stick, ev and ev.joystick)
    elseif Stack and Chrome and FrlgFont then
      -- FireRed has no `game.stack` to push a Gen 1 screen onto; the wheel
      -- goes on FireRed's own modal stack instead, drawn by Gen3Radial above.
      Gen3Radial.game, Gen3Radial.items = game, items
      Gen3Radial.stick, Gen3Radial.joystick = cfg.stick, ev and ev.joystick
      Gen3Radial.x, Gen3Radial.y, Gen3Radial.selected, Gen3Radial.fade = 0, 0, nil, 0
      active = Gen3Radial
      Stack.push("hotkey_suite_radial", Gen3Radial)
    else
      return false
    end
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
    onFire = function(game, ev)
      -- canOpenMenu inside open() gives the same "player is mid-step" busy
      -- answer every generation gives a caller from outside a single frame's
      -- own input poll (see shared.lua's "deferred retry" section), so
      -- holding the combo while walking is retried each frame instead of
      -- dropped, opening the wheel the moment the step lands.
      shared.deferUntilIdle(game, function(g) return open(g, ev) end, "radial")
    end,
    onBreak = function()
      -- Aiming stops meaning "select" the instant the combo lets go, whether
      -- or not the wheel ever actually opened; a still-queued open must not
      -- spring the wheel open a frame after the player has already let go.
      shared.cancelDeferred("radial")
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
    id = "radial", label = "RADIAL MENU", context = "overworld",
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
          help = "Hold this to open the radial menu, aim with the stick, then "
            .. "release to pick the highlighted entry.",
          activate = function(game)
            shared.captureCombo(game, "RADIAL HOTKEY", spec)
          end,
          unassign = function() shared.setBinding(spec, nil); return true end },
        { id = "radialStick", label = "STICK",
          value = function() return config().stick:upper() end,
          help = "Which analogue stick aims the radial menu.",
          step = function(_, dir)
            local cfg = config()
            cfg.stick = shared.cycle({ "left", "right" }, cfg.stick, dir)
            save(cfg)
            return true
          end },
        { id = "radialPosition", label = "POSITION",
          value = function() return POSITION_LABELS[config().position] end,
          help = "Where the radial menu is drawn on screen.",
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
