return function(mod, suite)
  local shared = suite.shared

  local SPEEDS = {
    { label = "SLOW", delay = 0.70 },
    { label = "MEDIUM", delay = 0.45 },
    { label = "FAST", delay = 0.25 },
    { label = "VERY FAST", delay = 0.12 },
  }

  local timer = 0

  local function config()
    local cfg = shared.store.get("battleText", nil)
    if type(cfg) ~= "table" then cfg = {} end
    -- AUTO TEXT and its speed used to live on the Battle Command Menu. Seed
    -- them from there until this module stores a value of its own, so the
    -- split does not silently reset anyone's configuration.
    if cfg.autoText == nil or cfg.speed == nil then
      local legacy = shared.store.get("battleHotkeys", nil)
      if type(legacy) == "table" then
        if cfg.autoText == nil and legacy.autoText ~= nil then
          cfg.autoText = legacy.autoText
          if cfg.enabled == nil and legacy.autoText == true then
            cfg.enabled = legacy.enabled == true
          end
        end
        if cfg.speed == nil then cfg.speed = tonumber(legacy.autoTextSpeed) end
      end
    end
    if cfg.enabled == nil then cfg.enabled = false end
    if cfg.autoText == nil then cfg.autoText = false end
    if cfg.levelUp == nil then cfg.levelUp = false end
    cfg.speed = tonumber(cfg.speed)
    if not cfg.speed or cfg.speed % 1 ~= 0 or not SPEEDS[cfg.speed] then
      cfg.speed = 2
    end
    return cfg
  end

  local function save(cfg)
    shared.store.set("battleText", cfg)
    timer = 0
  end

  local function battleState(game)
    local commandMenu = shared.commandMenu
    if commandMenu and type(commandMenu.battleState) == "function" then
      return commandMenu.battleState(game)
    end
    local states = game and game.stack and game.stack.states
    for i = #(states or {}), 1, -1 do
      local state = states[i]
      if type(state) == "table"
          and (state.isBattle or state.isBattleState
            or type(state.chooseMenu) == "function") then
        return state
      end
    end
  end

  -- The level-up stat window is a local class inside the engine's
  -- BattleState.lua (PrintStatsBox .LevelUpStatsBox), so it cannot be
  -- identified by name from a mod.  It is matched structurally instead: it is
  -- the only battle-time state whose instance carries nothing but `game`,
  -- `mon`, `onDone` and the optional `keepOpen`, and whose `mon` is a real
  -- party member.  Anything with an extra field is some other screen and is
  -- left alone.
  local STAT_BOX_FIELDS = {
    game = true, mon = true, onDone = true, keepOpen = true,
  }
  local function isLevelUpStatBox(state)
    if type(state) ~= "table" then return false end
    if type(state.update) ~= "function" or type(state.draw) ~= "function" then
      return false
    end
    if rawget(state, "game") == nil then return false end
    local mon = rawget(state, "mon")
    if type(mon) ~= "table" or type(mon.stats) ~= "table" then return false end
    for key in pairs(state) do
      if not STAT_BOX_FIELDS[key] then return false end
    end
    return true
  end

  -- What, if anything, this module is allowed to advance right now.
  local function pending(game)
    local cfg = config()
    if not cfg.enabled then return nil, cfg end
    local battle = battleState(game)
    if not battle then return nil, cfg end
    local stack = game and game.stack
    local top = stack and type(stack.top) == "function" and stack:top() or nil
    if cfg.levelUp and top ~= battle and isLevelUpStatBox(top) then
      return "levelUp", cfg
    end
    if cfg.autoText then
      local commandMenu = shared.commandMenu
      local waiting = commandMenu
        and type(commandMenu.textWaiting) == "function"
        and commandMenu.textWaiting(game, battle)
      if waiting then return "text", cfg end
    end
    return nil, cfg
  end

  mod.hooks:wrap("input.step", function(next, game, dt)
    next(game, dt)
    local kind, cfg = pending(game)
    if not kind then
      timer = 0
      return
    end
    timer = timer + (dt or 0)
    if timer >= SPEEDS[cfg.speed].delay then
      timer = 0
      mod.input:tap(game, "a")
    end
  end)

  local function rows()
    return {
      shared.enabledRow("battleText.enabled",
        function() return config().enabled end,
        function(value)
          local cfg = config()
          cfg.enabled = value
          save(cfg)
        end),
      {
        id = "battleText.autoText",
        label = "AUTO TEXT",
        value = function() return config().autoText and "ON" or "OFF" end,
        help = "Advances battle messages for you. Menus, move select and "
          .. "yes/no prompts stay under your control.",
        step = function()
          local cfg = config()
          cfg.autoText = not cfg.autoText
          save(cfg)
          return true
        end,
        unassign = function()
          local cfg = config()
          cfg.autoText = false
          save(cfg)
          return true
        end,
      },
      {
        id = "battleText.levelUp",
        label = "LEVEL UP",
        value = function() return config().levelUp and "ON" or "OFF" end,
        help = "Also dismisses the level-up stat window. Turn AUTO TEXT on as "
          .. "well to advance the message in front of it. Learning a new move "
          .. "still asks you.",
        step = function()
          local cfg = config()
          cfg.levelUp = not cfg.levelUp
          save(cfg)
          return true
        end,
        unassign = function()
          local cfg = config()
          cfg.levelUp = false
          save(cfg)
          return true
        end,
      },
      {
        id = "battleText.speed",
        label = "SPEED",
        value = function() return SPEEDS[config().speed].label end,
        help = "How long each message is held before it is advanced. Used by "
          .. "both AUTO TEXT and LEVEL UP.",
        step = function(_, dir)
          local cfg = config()
          cfg.speed = ((cfg.speed - 1 + (dir or 1)) % #SPEEDS) + 1
          save(cfg)
          return true
        end,
      },
    }
  end

  suite.register("keyboard", {
    id = "battle_text", label = "BATTLE TEXT", context = "battle", rows = rows,
  })
  suite.register("gamepad", {
    id = "battle_text", label = "BATTLE TEXT", context = "battle", rows = rows,
  })

  shared.registerReset(function()
    local cfg = config()
    cfg.enabled = false
    cfg.autoText = false
    cfg.levelUp = false
    save(cfg)
  end)

  shared.battleText = {
    config = config,
    isLevelUpStatBox = isLevelUpStatBox,
    pending = pending,
    speeds = SPEEDS,
  }
end
