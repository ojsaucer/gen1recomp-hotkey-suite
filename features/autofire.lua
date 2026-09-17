return function(mod, suite)
  local shared = suite.shared
  local Font = require("src.render.Font")
  local MODES = { "toggle", "hold" }
  local METHODS = { "fixed", "next" }
  local SPEEDS = {
    { label = "SLOW (5/S)", rate = 5 },
    { label = "MEDIUM (10/S)", rate = 10 },
    { label = "FAST (15/S)", rate = 15 },
    { label = "VERY FAST (20/S)", rate = 20 },
    { label = "TURBO (30/S)", rate = 30 },
  }
  local TARGETS = { "a", "b", "start", "select", "up", "down", "left", "right" }
  local NOTICES = {
    "off", "top_left", "top_right", "bottom_left", "bottom_right",
    "top_center", "bottom_center",
  }
  local NOTICE_LABEL = {
    off = "OFF", top_left = "TOP LEFT", top_right = "TOP RIGHT",
    bottom_left = "BOTTOM LEFT", bottom_right = "BOTTOM RIGHT",
    top_center = "TOP CENTER", bottom_center = "BOTTOM CENTER",
  }
  local LABEL = {
    a = "A", b = "B", start = "START", select = "SELECT",
    up = "UP", down = "DOWN", left = "LEFT", right = "RIGHT",
  }
  local state = {
    active = false, target = nil, source = nil, selector = nil, accumulator = 0,
  }

  local function config()
    local cfg = mod.save:get("autofire", {})
    if type(cfg) ~= "table" then cfg = {} end
    if cfg.enabled == nil then cfg.enabled = false end
    if cfg.mode ~= "toggle" and cfg.mode ~= "hold" then cfg.mode = "toggle" end
    if cfg.method ~= "fixed" and cfg.method ~= "next" then cfg.method = "fixed" end
    cfg.speed = tonumber(cfg.speed)
    if not cfg.speed or cfg.speed % 1 ~= 0 or not SPEEDS[cfg.speed] then
      cfg.speed = 2
    end
    if not LABEL[cfg.target] then cfg.target = "a" end
    if not NOTICE_LABEL[cfg.notice] then cfg.notice = "off" end
    cfg.bindings = type(cfg.bindings) == "table" and cfg.bindings or {}
    return cfg
  end
  local function save(cfg) mod.save:set("autofire", cfg) end
  local function stop()
    state.active, state.target, state.source = false, nil, nil
    state.selector, state.accumulator = nil, 0
  end
  local function start(game, target, source)
    local cfg = config()
    if cfg.mode == "toggle" and state.active and state.target == target then
      stop()
      return
    end
    state.active, state.target, state.source = true, target, source
    state.accumulator = 0
    mod.input:tap(game, target)
  end
  local function mapped(game, inputId, name)
    local input = game and game.input
    local map = inputId == "keyboard" and input and input.keyBindings
      or inputId == "gamepad" and input and input.padBindings
    return map and map[name] or nil
  end

  local specs = {}
  for _, inputId in ipairs({ "keyboard", "gamepad" }) do
    local currentInput = inputId
    specs[inputId] = shared.registerHotkey({
      id = "autofire." .. inputId,
      input = inputId,
      context = "any",
      enabled = function() return config().enabled end,
      get = function() return config().bindings[currentInput] end,
      set = function(value)
        local cfg = config()
        cfg.bindings[currentInput] = value
        save(cfg)
        stop()
      end,
      onFire = function(game)
        local cfg = config()
        if cfg.method == "fixed" then start(game, cfg.target)
        else state.selector = currentInput end
      end,
      onBreak = function()
        state.selector = nil
        if config().mode == "hold" then stop() end
      end,
    })

    shared.onRaw(inputId, function(name, pressed, game)
      local cfg = config()
      if not cfg.enabled then return false end
      if cfg.method ~= "next" or state.selector ~= currentInput then return false end
      local target = mapped(game, currentInput, name)
      if not target or not LABEL[target] then return false end
      local source = currentInput .. ":" .. name
      if pressed then
        start(game, target, source)
        return true
      elseif not pressed and cfg.mode == "hold" and state.source == source then
        stop()
        return true
      end
      return false
    end)
  end

  mod.hooks:wrap("input.step", function(next, game, dt)
    next(game, dt)
    if not state.active then return end
    local cfg = config()
    if not cfg.enabled then
      stop()
      return
    end
    state.accumulator = state.accumulator + dt
    local interval = 1 / SPEEDS[cfg.speed].rate
    while state.accumulator >= interval do
      state.accumulator = state.accumulator - interval
      mod.input:tap(game, state.target or cfg.target)
    end
  end)

  mod.hooks:wrap("render.hud", function(next, game, viewport)
    next(game, viewport)
    local cfg = config()
    if not state.active or cfg.mode ~= "toggle" or cfg.notice == "off"
        or not viewport then return end
    local text, width, height = "AUTOFIRE", Font.width("AUTOFIRE") + 8, 16
    local x = cfg.notice:find("right", 1, true) and (160 - width - 2)
      or (cfg.notice:find("center", 1, true) and math.floor((160 - width) / 2) or 2)
    local y = cfg.notice:find("bottom", 1, true) and (144 - height - 2) or 2
    local g = love.graphics
    g.push("all")
    g.origin()
    g.translate(viewport.gameX or 0, viewport.gameY or 0)
    g.scale(viewport.scale or 1)
    g.setColor(1, 1, 1, 0.9)
    g.rectangle("fill", x, y, width, height)
    g.setColor(0, 0, 0, 1)
    g.rectangle("line", x, y, width, height)
    Font.draw(text, x + 4, y + 4)
    g.pop()
  end)

  local function rows(_, inputId)
    local function cycle(field, values, labels)
      return function(_, dir)
        local cfg = config()
        cfg[field] = shared.cycle(values, cfg[field], dir)
        save(cfg)
        stop()
        return true
      end, function()
        local value = config()[field]
        return labels and labels[value] or tostring(value):upper()
      end
    end
    local methodStep, methodValue = cycle("method", METHODS,
      { fixed = "FIXED BUTTON", next = "NEXT INPUT" })
    local modeStep, modeValue = cycle("mode", MODES)
    local targetStep, targetValue = cycle("target", TARGETS, LABEL)
    local noticeStep, noticeValue = cycle("notice", NOTICES, NOTICE_LABEL)
    local spec = specs[inputId]
    return {
      shared.enabledRow("afEnabled",
        function() return config().enabled end,
        function(value)
          local cfg = config()
          cfg.enabled = value
          save(cfg)
          if not value then stop() end
        end),
      { id = "afMethod", label = "METHOD", value = methodValue, step = methodStep },
      { id = "afMode", label = "MODE", value = modeValue, step = modeStep },
      { id = "afSpeed", label = "SPEED",
        value = function() return SPEEDS[config().speed].label end,
        step = function(_, dir)
          local cfg = config()
          cfg.speed = ((cfg.speed - 1 + (dir or 1)) % #SPEEDS) + 1
          save(cfg)
          return true
        end },
      { id = "afTarget", label = "FIXED BUTTON", value = targetValue,
        step = targetStep },
      { id = "afNotice", label = "AF NOTICE", value = noticeValue,
        step = noticeStep },
      { id = "afBinding", label = "HOTKEY",
        value = function() return shared.comboLabel(spec:get()) end,
        activate = function(g) shared.captureCombo(g, "AUTOFIRE HOTKEY", spec) end,
        unassign = function() shared.setBinding(spec, nil); return true end },
    }
  end

  suite.register("keyboard", { id = "autofire", label = "AUTOFIRE HOTKEYS", rows = rows })
  suite.register("gamepad", { id = "autofire", label = "AUTOFIRE HOTKEYS", rows = rows })

  shared.registerReset(function()
    local cfg = config()
    cfg.enabled = false
    save(cfg)
    stop()
  end)

  shared.autofire = {
    config = config, save = save, state = state, stop = stop,
    speeds = SPEEDS, targets = TARGETS, labels = LABEL, start = start,
    specs = specs,
  }
end
