return function(mod, suite)
  local shared = suite.shared
  local Screens = require("src.ui.Screens")
  local TextBox = require("src.render.TextBox")
  local ACTIONS = {
    { id = "fly", label = "FLY", short = "FLY",
      help = "Opens the TOWN MAP to fly. Needs HM02 FLY and a free "
        .. "overworld." },
    { id = "center", label = "RETURN CENTER", short = "PC",
      help = "Teleports to the last POKEMON CENTER you healed at, exactly as "
        .. "DIG or an ESCAPE ROPE would." },
    { id = "bike", label = "BICYCLE", short = "BIKE",
      help = "Gets on or off the BICYCLE where the terrain allows it." },
  }

  local function config()
    local cfg = shared.store.get("travel", nil)
    if type(cfg) ~= "table" then cfg = {} end
    if cfg.enabled == nil then cfg.enabled = false end
    cfg.bindings = type(cfg.bindings) == "table" and cfg.bindings or {}
    cfg.bindings.keyboard = type(cfg.bindings.keyboard) == "table"
      and cfg.bindings.keyboard or {}
    cfg.bindings.gamepad = type(cfg.bindings.gamepad) == "table"
      and cfg.bindings.gamepad or {}
    return cfg
  end
  local function save(cfg) shared.store.set("travel", cfg) end

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

  -- FLY is the one action an engine can withhold from mods.  Gold leaves it
  -- out of mod.world:availableFieldActions() and exposes neither canFly nor
  -- flyTo, so there is no supported way to raise its destination picker.  The
  -- capability is probed rather than the game version, and the row stays
  -- visible saying so instead of quietly taking a binding that could never
  -- fire.
  local function supported(actionId)
    if actionId ~= "fly" then return true end
    local world = mod.world
    return world ~= nil and type(world.canFly) == "function"
      and type(world.flyTo) == "function"
  end

  local function useFly(game)
    if not supported("fly") then
      notify(game, "FLY can't be used\nfrom a hotkey here.")
      return false
    end
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
        enabled = function() return config().enabled end,
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
    local rows = {
      shared.enabledRow("travel.enabled",
        function() return config().enabled end,
        function(value)
          local cfg = config()
          cfg.enabled = value
          save(cfg)
        end),
    }
    for _, action in ipairs(ACTIONS) do
      local current = action
      local spec = specs[inputId][current.id]
      rows[#rows + 1] = {
        id = "travel." .. current.id,
        label = current.label,
        value = function()
          if not supported(current.id) then return "UNSUPPORTED" end
          return shared.comboLabel(spec:get())
        end,
        help = current.help,
        activate = function(game)
          if not supported(current.id) then return end
          shared.captureCombo(game, current.label .. " HOTKEY", spec)
        end,
        unassign = function() shared.setBinding(spec, nil); return true end,
      }
    end
    return rows
  end

  suite.register("keyboard", {
    id = "travel", label = "TRAVEL HOTKEYS", context = "overworld", rows = rows,
  })
  suite.register("gamepad", {
    id = "travel", label = "TRAVEL HOTKEYS", context = "overworld", rows = rows,
  })

  shared.registerReset(function()
    local cfg = config()
    cfg.enabled = false
    save(cfg)
  end)

  shared.travel = {
    actions = ACTIONS,
    config = config,
    run = function(game, id)
      return run[id] and run[id](game) or false
    end,
    specs = specs,
  }
end
