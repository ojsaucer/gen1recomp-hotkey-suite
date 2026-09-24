return function(mod, suite)
  local shared = suite.shared
  local Screens = require("src.ui.Screens")
  local TextBox = require("src.render.TextBox")
  local ACTIONS = {
    { id = "fly", label = "FLY", short = "FLY",
      help = "Opens the fly map to pick a town you have visited. Needs a "
        .. "POKEMON that knows FLY, the badge for it, and open ground." },
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
    if shared.chromeAvailable(game) then
      game.stack:push(TextBox.new(game, text))
      return
    end
    -- FireRed has no state stack to push a TextBox onto; its field dialogue
    -- is the singleton src/ui/game3/message, which is what the engine's own
    -- field actions write their refusals to.  Its box is one line wider than
    -- Red's, so the hard break that keeps Red inside 18 columns is dropped.
    local ok, Message = pcall(require, "src.ui.game3.message")
    if ok and type(Message) == "table" and type(Message.show) == "function" then
      Message.show((text:gsub("\n", " ")), function() Message.close() end)
    end
  end

  local function ready(game)
    return shared.canOpenMenu(game) and shared.world.ownsFrame(game)
  end

  -- Tri-state on purpose.  Red and Gold both keep the bag on game.save, but
  -- FireRed keeps it on the session and hands mods the raw Game3, so there is
  -- no inventory to read -- and "I could not find your bag" must never be
  -- reported to the player as "you do not have one".  nil means unknown, and
  -- every caller lets the engine's own check refuse instead: useFieldAction
  -- already gates the BICYCLE on Bag.has (src/world/game3/WorldAPI.lua:219).
  local function hasItem(game, id)
    local inventory = game and game.save and game.save.inventory
    if type(inventory) ~= "table" then return nil end
    return (inventory[id] or 0) > 0
  end

  -- FLY is the one action an engine can withhold.  Red hands it to mods
  -- directly; Gold reaches the same place through the field-move pipeline;
  -- FireRed offers neither, because its destinations are the region map's
  -- town spawn points and nothing exposes them (see shared.world.flyMode).
  -- Probed, never assumed from the game id.
  --
  -- The answer is remembered because the row's label is drawn from the
  -- options screen, where there may be no live overworld to probe -- and an
  -- engine we have not managed to ask yet must not be branded UNSUPPORTED.
  -- Only a live world that answers to neither shape is a definite no.
  local flyKnown
  local function flyMode()
    local api = mod.world
    local ow = api and api.overworld and api:overworld() or nil
    local mode = shared.world.flyMode(api, ow)
    if mode then
      flyKnown = mode
    elseif ow then
      flyKnown = false
    end
    if flyKnown == false then return nil end
    return flyKnown or "fieldmove"
  end

  local function supported(actionId)
    if actionId ~= "fly" then return true end
    return flyMode() ~= nil
  end

  local function useFly(game)
    if not ready(game) then return false end
    local ow = mod.world:overworld()
    if not ow then return false end
    local mode = shared.world.flyMode(mod.world, ow)
    if mode == "fieldmove" then
      -- partyMoveUser runs the engine's own fieldmove.eligibility hook chain,
      -- so another mod's idea of who may fly is honoured here too.
      local mon = ow:partyMoveUser("FLY")
      if not mon then
        notify(game, "No POKEMON knows\nFLY.")
        return false
      end
      -- A refusal -- no STORM BADGE, or standing indoors -- has already put
      -- the engine's own line on the screen, so there is nothing to add.
      local result = ow:useFieldMove("FLY", mon)
      return (result and result.ok) and true or false
    end
    if mode ~= "picker" then
      notify(game, "FLY can't be used\nfrom a hotkey here.")
      return false
    end
    if hasItem(game, "HM_FLY") == false then
      notify(game, "HM02 FLY is\nrequired.")
      return false
    end
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
    local ow = mod.world:overworld()
    if not ow then return false end
    local mode = shared.world.centerMode(ow)
    if mode == "spawn" or mode == "healPoint" then
      -- healPoint is Gold's and FireRed's lastHeal: nil until somewhere has
      -- been healed at.
      if not ow:healPoint() then
        notify(game, "Visit a POKEMON\nCENTER first.")
        return false
      end
      if mode == "healPoint" then ow:warpToHealPoint() else ow:warpToSpawn() end
      return true
    end
    if mode ~= "teleportOut" then
      notify(game, "RETURN CENTER can't\nbe used here.")
      return false
    end
    if not game.save.lastHeal then
      notify(game, "Visit a POKEMON\nCENTER first.")
      return false
    end
    ow:beginTeleportOut()
    return true
  end

  local function useBike(game)
    if not ready(game) then return false end
    if hasItem(game, "BICYCLE") == false then
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
    ready = ready,
    flyMode = flyMode,
    run = function(game, id)
      return run[id] and run[id](game) or false
    end,
    specs = specs,
  }
end
