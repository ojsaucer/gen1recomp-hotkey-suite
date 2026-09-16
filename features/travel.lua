return function(mod, suite)
  local shared = suite.shared
  local Screens = require("src.ui.Screens")
  local TextBox = require("src.render.TextBox")
  local ACTIONS = {
    { id = "fly", label = "FLY", short = "FLY" },
    { id = "center", label = "RETURN CENTER", short = "PC" },
    { id = "bike", label = "BICYCLE", short = "BIKE" },
  }

  local function config()
    local cfg = mod.save:get("travel", {})
    if type(cfg) ~= "table" then cfg = {} end
    cfg.bindings = type(cfg.bindings) == "table" and cfg.bindings or {}
    cfg.bindings.keyboard = type(cfg.bindings.keyboard) == "table"
      and cfg.bindings.keyboard or {}
    cfg.bindings.gamepad = type(cfg.bindings.gamepad) == "table"
      and cfg.bindings.gamepad or {}
    cfg.touch = type(cfg.touch) == "table" and cfg.touch or {}
    return cfg
  end
  local function save(cfg) mod.save:set("travel", cfg) end

  local function notify(game, text)
    game.stack:push(TextBox.new(game, text))
  end

  local function ready(game)
    local stack = game and game.stack
    local states = stack and stack.states
    return shared.canOpenMenu(game) and states and #states == 1
      and stack:top() == states[1]
  end

  local function hasItem(game, id)
    local inventory = game and game.save and game.save.inventory
    return inventory and (inventory[id] or 0) > 0
  end

  local function useFly(game)
    if not ready(game) then return false end
    if not hasItem(game, "HM_FLY") then
      notify(game, "HM02 FLY is\nrequired.")
      return false
    end
    local ow = mod.world:overworld()
    if not ow then return false end
    Screens.push(game, "TownMap", {
      fly = true,
      onFly = function(mapId)
        local live = mod.world:overworld()
        if live then live:flyTo(mapId) end
      end,
    })
    return true
  end

  local function returnToCenter(game)
    if not ready(game) then return false end
    if not game.save.lastHeal then
      notify(game, "Visit a POKEMON\nCENTER first.")
      return false
    end
    local ow = mod.world:overworld()
    if not ow then return false end
    ow:beginTeleportOut()
    return true
  end

  local function useBike(game)
    if not ready(game) then return false end
    if not hasItem(game, "BICYCLE") then
      notify(game, "A BICYCLE is\nrequired.")
      return false
    end
    local ok = mod.world:useFieldAction("bicycle")
    if not ok then
      notify(game, "The BICYCLE can't\nbe used here.")
      return false
    end
    return true
  end

  local run = { fly = useFly, center = returnToCenter, bike = useBike }
  local specs = { keyboard = {}, gamepad = {} }

  for _, inputId in ipairs({ "keyboard", "gamepad" }) do
    for _, action in ipairs(ACTIONS) do
      local currentInput, currentAction = inputId, action
      specs[inputId][action.id] = shared.registerHotkey({
        id = "travel." .. inputId .. "." .. action.id,
        input = inputId,
        context = "overworld",
        get = function()
          return config().bindings[currentInput][currentAction.id]
        end,
        set = function(value)
          local cfg = config()
          cfg.bindings[currentInput][currentAction.id] = value or false
          save(cfg)
        end,
        onFire = function(game) return run[currentAction.id](game) end,
      })
    end
  end

  local function rows(_, inputId)
    local rows = {}
    for _, action in ipairs(ACTIONS) do
      local current = action
      local spec = specs[inputId][current.id]
      rows[#rows + 1] = {
        id = "travel." .. current.id,
        label = current.label,
        value = function() return shared.comboLabel(spec:get()) end,
        activate = function(game)
          shared.captureCombo(game, current.label .. " HOTKEY", spec)
        end,
        unassign = function() shared.setBinding(spec, nil); return true end,
      }
    end
    return rows
  end

  local function touchRows()
    local rows = {}
    for _, action in ipairs(ACTIONS) do
      local current = action
      rows[#rows + 1] = {
        id = "travel.touch." .. current.id,
        label = current.label,
        value = function()
          return config().touch[current.id] and "ON" or "OFF"
        end,
        step = function()
          local cfg = config()
          cfg.touch[current.id] = not cfg.touch[current.id]
          save(cfg)
          return true
        end,
        unassign = function()
          local cfg = config()
          cfg.touch[current.id] = false
          save(cfg)
          return true
        end,
      }
    end
    return rows
  end

  suite.register("keyboard", {
    id = "travel", label = "TRAVEL HOTKEYS", rows = rows,
  })
  suite.register("gamepad", {
    id = "travel", label = "TRAVEL HOTKEYS", rows = rows,
  })
  suite.register("touchscreen", {
    id = "travel", label = "TRAVEL HOTKEYS", rows = touchRows,
  })

  shared.registerStats(function()
    local cfg = config()
    local active = 0
    for _, action in ipairs(ACTIONS) do
      if cfg.touch[action.id] then active = active + 1 end
    end
    return active, active
  end)

  shared.registerReset(function()
    local cfg = config()
    for _, action in ipairs(ACTIONS) do cfg.touch[action.id] = false end
    save(cfg)
  end)

  shared.travel = {
    actions = ACTIONS,
    config = config,
    run = function(game, id)
      return run[id] and run[id](game) or false
    end,
    touchActions = function()
      local cfg, out = config(), {}
      for _, action in ipairs(ACTIONS) do
        if cfg.touch[action.id] then out[#out + 1] = action end
      end
      return out
    end,
    specs = specs,
  }
end
