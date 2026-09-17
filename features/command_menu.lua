return function(mod, suite)
  local shared = suite.shared
  local Font = require("src.render.Font")
  local Sound = require("src.core.Sound")
  local active = { keyboard = false, gamepad = false }
  local specs = { commands = {}, run = {} }
  local touchRects = {}
  local customLegend

  local COMMANDS = {
    up = { index = 1, action = "fight", label = "FIGHT" },
    right = { index = 2, action = "party", label = "PKMN" },
    left = { index = 3, action = "item", label = "ITEM" },
    down = { index = 4, action = "run", label = "RUN" },
  }
  local DIRECTIONS = {
    up = "up", right = "right", left = "left", down = "down",
    dpup = "up", dpright = "right", dpleft = "left", dpdown = "down",
  }
  local DIRECTION_FOR_INDEX = { "up", "right", "left", "down" }
  local DIRECTION_ANGLE = {
    right = 0, down = math.pi / 2, left = math.pi, up = -math.pi / 2,
  }
  local LEGEND_POSITIONS = {
    "top_left", "top_center", "top_right",
    "bottom_left", "bottom_center", "bottom_right",
  }
  local LEGEND_POSITION_LABELS = {
    top_left = "TOP LEFT", top_center = "TOP CENTER",
    top_right = "TOP RIGHT", bottom_left = "BOTTOM LEFT",
    bottom_center = "BOTTOM CENTER", bottom_right = "BOTTOM RIGHT",
  }
  local LEGEND_SCALES = { 0.75, 1, 1.25, 1.5 }
  local AUTO_TEXT_SPEEDS = {
    { label = "SLOW", delay = 0.70 },
    { label = "MEDIUM", delay = 0.45 },
    { label = "FAST", delay = 0.25 },
    { label = "VERY FAST", delay = 0.12 },
  }

  local function config()
    local cfg = mod.save:get("battleHotkeys", {})
    if type(cfg) ~= "table" then cfg = {} end
    if cfg.enabled == nil then cfg.enabled = false end
    cfg.bindings = type(cfg.bindings) == "table" and cfg.bindings or {}
    if cfg.autoText == nil then cfg.autoText = false end
    cfg.autoTextSpeed = tonumber(cfg.autoTextSpeed)
    if not cfg.autoTextSpeed or cfg.autoTextSpeed % 1 ~= 0
        or not AUTO_TEXT_SPEEDS[cfg.autoTextSpeed] then
      cfg.autoTextSpeed = 2
    end
    if not LEGEND_POSITION_LABELS[cfg.legendPosition] then
      cfg.legendPosition = "top_center"
    end
    local validScale = false
    for _, value in ipairs(LEGEND_SCALES) do
      if cfg.legendScale == value then validScale = true break end
    end
    if not validScale then cfg.legendScale = 1 end
    return cfg
  end

  local function save(cfg)
    mod.save:set("battleHotkeys", cfg)
  end

  local function battleState(game)
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

  local function commandReady(battle)
    if not battle or battle.phase ~= "menu" or battle.demo then return false end
    if battle.safari then return (battle.safari.balls or 0) > 0 end
    local player = battle.player
    if not player or not player.mon or player.mon.hp <= 0 then return false end
    return true
  end

  local function moveReady(battle)
    return battle and battle.phase == "moveSelect"
      and battle.player and type(battle.player.curMoves) == "table"
      and not battle.moveSwapIndex
  end

  local function customBattleUI(battle)
    if not battle or type(battle.bottomUIVisible) ~= "function" then
      return false
    end
    local ok, visible = pcall(battle.bottomUIVisible, battle)
    return ok and visible == false
  end

  local function choose(game, direction)
    local command = COMMANDS[direction]
    local battle = battleState(game)
    if not command or not commandReady(battle) then return false end
    battle.menuIndex = command.index
    Sound.play(battle.data, "Press_AB")
    if battle.safari then
      battle:chooseSafari(({ "ball", "bait", "rock", "run" })[command.index])
    else
      battle:chooseMenu(command.action)
    end
    return true
  end

  local function chooseMove(game, direction)
    local command = COMMANDS[direction]
    local battle = battleState(game)
    local moves = battle and battle.player and battle.player.curMoves
    if not command or not moveReady(battle) or not moves[command.index] then
      return false
    end
    battle.moveIndex = command.index
    Sound.play(battle.data, "Press_AB")
    battle:chooseMove(command.index)
    return true
  end

  local function runFromMenu(game)
    local battle = battleState(game)
    if not commandReady(battle) then return false end
    battle.menuIndex = 4
    Sound.play(battle.data, "Press_AB")
    if battle.safari then
      battle:chooseSafari("run")
    else
      battle:chooseMenu("run")
    end
    return true
  end

  for _, inputId in ipairs({ "keyboard", "gamepad" }) do
    local current = inputId
    specs.commands[inputId] = shared.registerHotkey({
      id = "battle.commands." .. inputId,
      input = inputId,
      context = "battle",
      enabled = function() return config().enabled end,
      get = function() return config().bindings[current] end,
      set = function(value)
        local cfg = config()
        cfg.bindings[current] = value or false
        save(cfg)
        if not value then active[current] = false end
      end,
      onFire = function() active[current] = true end,
      onBreak = function() active[current] = false end,
    })
    specs.run[inputId] = shared.registerHotkey({
      id = "battle.run." .. inputId,
      input = inputId,
      context = "battle",
      enabled = function() return config().enabled end,
      get = function() return config().bindings[current .. "Run"] end,
      set = function(value)
        local cfg = config()
        cfg.bindings[current .. "Run"] = value or false
        save(cfg)
      end,
      onFire = function(game) return runFromMenu(game) end,
    })
  end

  for _, inputId in ipairs({ "keyboard", "gamepad" }) do
    local current = inputId
    shared.onRaw(inputId, function(name, pressed, game)
      if not config().enabled then
        active[current] = false
        return
      end
      local direction = DIRECTIONS[name]
      if pressed and active[current] and direction then
        local battle = battleState(game)
        if moveReady(battle) then
          chooseMove(game, direction)
        else
          choose(game, direction)
        end
      end
    end)
  end

  local function drawArrow(x, y, direction)
    love.graphics.push()
    love.graphics.translate(x + 4, y + 4)
    love.graphics.rotate(DIRECTION_ANGLE[direction])
    Font.drawCode(0xED, -4, -4)
    love.graphics.pop()
  end

  -- Auto Text Skip taps the same A the player would press, and only while the
  -- battle itself is the top state and is parked on a message waiting for
  -- input. Choice prompts (yes/no, nickname, learn-move) push their own screen
  -- on top, so they stay under manual control.
  local autoText = { accumulator = 0 }

  local function textWaiting(game, battle)
    if not battle then return false end
    if battle.demo then return false end
    local stack = game and game.stack
    if not stack or type(stack.top) ~= "function" then return false end
    if stack:top() ~= battle then return false end
    if battle.phase == "menu" or battle.phase == "moveSelect"
        or battle.phase == "mimicSelect" then
      return false
    end
    return battle.msgWaiting == true or battle.msgPrompt == true
      or battle.waitingForInput == true
  end

  mod.hooks:wrap("input.step", function(next, game, dt)
    next(game, dt)
    local cfg = config()
    if not cfg.enabled or not cfg.autoText then
      autoText.accumulator = 0
      return
    end
    local battle = battleState(game)
    if not textWaiting(game, battle) then
      autoText.accumulator = 0
      return
    end
    autoText.accumulator = autoText.accumulator + (dt or 0)
    local delay = AUTO_TEXT_SPEEDS[cfg.autoTextSpeed].delay
    if autoText.accumulator >= delay then
      autoText.accumulator = 0
      mod.input:tap(game, "a")
    end
  end)

  local function legendLabels(battle)
    if commandReady(battle) then
      return { "FIGHT", "PKMN", "ITEM", "RUN" }
    end
    if moveReady(battle) then
      local labels = {}
      for index = 1, 4 do
        local move = battle.player.curMoves[index]
        local def = move and battle.data and battle.data.moves
          and battle.data.moves[move.id]
        labels[index] = move and tostring(def and def.name or move.id) or "-"
      end
      return labels
    end
  end

  local function legendOrigin(position, width, height, nativeWidth, nativeHeight)
    local margin = 4
    local x = margin
    if position:find("right", 1, true) then
      x = nativeWidth - width - margin
    elseif position:find("center", 1, true) then
      x = (nativeWidth - width) / 2
    end
    local y = position:find("bottom", 1, true)
      and nativeHeight - height - margin or margin
    return math.floor(math.max(0, x) + 0.5),
      math.floor(math.max(0, y) + 0.5)
  end

  local function onBattleHUD(battle, draw)
    local renderer = battle.game and battle.game.renderer
    local hud = battle.extendedHUD and battle:extendedHUD()
      and renderer and renderer.battleHUDCanvas
    if not hud then return draw() end
    local previous = love.graphics.getCanvas()
    love.graphics.setCanvas(hud)
    draw()
    love.graphics.setCanvas(previous)
  end

  mod.hooks:wrap("battle.overlay", function(next, battle)
    next(battle)
    if not (active.keyboard or active.gamepad) then return end
    if customBattleUI(battle) then return end
    onBattleHUD(battle, function()
      love.graphics.push("all")
      love.graphics.setColor(1, 1, 1, 1)
      local wide = battle.wideLayout and battle:wideLayout()
      if commandReady(battle) then
        local xs
        if wide then
          xs = battle.safari and { 8, 160 } or { 168, 232 }
        else
          xs = battle.safari and { 8, 104 } or { 72, 120 }
        end
        for index = 1, 4 do
          local col = (index - 1) % 2
          local row = math.floor((index - 1) / 2)
          love.graphics.rectangle("fill", xs[col + 1], 112 + row * 16, 8, 8)
        end
        love.graphics.setColor(0, 0, 0, 1)
        for index, direction in ipairs(DIRECTION_FOR_INDEX) do
          local col = (index - 1) % 2
          local row = math.floor((index - 1) / 2)
          drawArrow(xs[col + 1], 112 + row * 16, direction)
        end
      elseif moveReady(battle) then
        if wide then
          local xs = { 8, 112 }
          for index = 1, 4 do
            local col = (index - 1) % 2
            local row = math.floor((index - 1) / 2)
            love.graphics.rectangle("fill", xs[col + 1],
              112 + row * 16, 8, 8)
          end
          love.graphics.setColor(0, 0, 0, 1)
          for index, direction in ipairs(DIRECTION_FOR_INDEX) do
            local col = (index - 1) % 2
            local row = math.floor((index - 1) / 2)
            drawArrow(xs[col + 1], 112 + row * 16, direction)
          end
        else
          for index = 1, 4 do
            love.graphics.rectangle("fill", 40, 96 + index * 8, 8, 8)
          end
          love.graphics.setColor(0, 0, 0, 1)
          for index, direction in ipairs(DIRECTION_FOR_INDEX) do
            drawArrow(40, 96 + index * 8, direction)
          end
        end
      end
      love.graphics.pop()
    end)
  end)

  mod.hooks:wrap("render.hud", function(next, game, viewport)
    next(game, viewport)
    touchRects = {}
    customLegend = nil
    local battle = battleState(game)
    local labels = (active.keyboard or active.gamepad)
      and customBattleUI(battle) and legendLabels(battle) or nil
    if labels and viewport then
      local scale = viewport.scale or 1
      local nativeWidth = (viewport.width or viewport.gameWidth
        or 160 * scale) / scale
      local nativeHeight = (viewport.height or viewport.gameHeight
        or 144 * scale) / scale
      local cfg = config()
      local maxLabelWidth = 0
      for _, label in ipairs(labels) do
        maxLabelWidth = math.max(maxLabelWidth, Font.width(label))
      end
      local cellW, cellH = math.max(72, maxLabelWidth + 24), 16
      local legendScale = math.min(cfg.legendScale,
        math.max(0.5, (nativeWidth - 8) / (cellW * 2)))
      local legendW, legendH = cellW * 2 * legendScale,
        cellH * 2 * legendScale
      local startX, startY = legendOrigin(cfg.legendPosition,
        legendW, legendH, nativeWidth, nativeHeight)
      local g = love.graphics
      g.push("all")
      g.origin()
      g.translate(startX * scale, startY * scale)
      g.scale(scale * legendScale, scale * legendScale)
      for index, direction in ipairs(DIRECTION_FOR_INDEX) do
        local col = (index - 1) % 2
        local row = math.floor((index - 1) / 2)
        local x = col * cellW
        local y = row * cellH
        g.setColor(1, 1, 1, 0.88)
        g.rectangle("fill", x, y, cellW, cellH)
        g.setColor(0, 0, 0, 1)
        g.rectangle("line", x, y, cellW, cellH)
        drawArrow(x + 4, y + 4, direction)
        Font.draw(labels[index], x + 16, y + 4)
      end
      g.pop()
      customLegend = {
        battle = battle, labels = labels, position = cfg.legendPosition,
        scale = legendScale,
      }
    end
  end, 30000)

  local function rows(_, inputId)
    local commandSpec = specs.commands[inputId]
    local runSpec = specs.run[inputId]
    return {
      shared.enabledRow("battle.enabled",
        function() return config().enabled end,
        function(value)
          local cfg = config()
          cfg.enabled = value
          save(cfg)
          if not value then
            active.keyboard, active.gamepad = false, false
            autoText.accumulator = 0
          end
        end),
      {
        id = "battle.commands.binding",
        label = "CMD MODE",
        value = function() return shared.comboLabel(config().bindings[inputId]) end,
        activate = function(game)
          shared.captureCombo(game, "CMD MODE HOTKEY", commandSpec)
        end,
        unassign = function()
          shared.setBinding(commandSpec, nil)
          return true
        end,
      },
      {
        id = "battle.run.binding",
        label = "RUN",
        value = function()
          return shared.comboLabel(config().bindings[inputId .. "Run"])
        end,
        activate = function(game)
          shared.captureCombo(game, "RUN HOTKEY", runSpec)
        end,
        unassign = function()
          shared.setBinding(runSpec, nil)
          return true
        end,
      },
      {
        id = "battle.autoText",
        label = "AUTO TEXT",
        value = function() return config().autoText and "ON" or "OFF" end,
        step = function()
          local cfg = config()
          cfg.autoText = not cfg.autoText
          save(cfg)
          autoText.accumulator = 0
          return true
        end,
        unassign = function()
          local cfg = config()
          cfg.autoText = false
          save(cfg)
          autoText.accumulator = 0
          return true
        end,
      },
      {
        id = "battle.autoTextSpeed",
        label = "TEXT SPEED",
        value = function()
          return AUTO_TEXT_SPEEDS[config().autoTextSpeed].label
        end,
        step = function(_, dir)
          local cfg = config()
          cfg.autoTextSpeed = ((cfg.autoTextSpeed - 1 + (dir or 1))
            % #AUTO_TEXT_SPEEDS) + 1
          save(cfg)
          return true
        end,
      },
      {
        id = "battle.legend.position",
        label = "UI POSITION",
        value = function()
          return LEGEND_POSITION_LABELS[config().legendPosition]
        end,
        step = function(_, dir)
          local cfg = config()
          cfg.legendPosition = shared.cycle(
            LEGEND_POSITIONS, cfg.legendPosition, dir)
          save(cfg)
          return true
        end,
      },
      {
        id = "battle.legend.scale",
        label = "UI SCALE",
        value = function()
          return ("%d%%"):format(math.floor(config().legendScale * 100 + 0.5))
        end,
        step = function(_, dir)
          local cfg = config()
          cfg.legendScale = shared.cycle(
            LEGEND_SCALES, cfg.legendScale, dir)
          save(cfg)
          return true
        end,
      },
    }
  end

  suite.register("keyboard", {
    id = "command_menu", label = "BATTLE CMD MENU", rows = rows,
  })
  suite.register("gamepad", {
    id = "command_menu", label = "BATTLE CMD MENU", rows = rows,
  })

  shared.registerReset(function()
    local cfg = config()
    cfg.enabled = false
    cfg.autoText = false
    save(cfg)
    active.keyboard, active.gamepad = false, false
    autoText.accumulator = 0
  end)

  shared.commandMenu = {
    active = active,
    autoTextSpeeds = AUTO_TEXT_SPEEDS,
    choose = choose,
    chooseMove = chooseMove,
    config = config,
    customBattleUI = customBattleUI,
    customLegend = function() return customLegend end,
    commands = COMMANDS,
    runFromMenu = runFromMenu,
    specs = specs,
    textWaiting = textWaiting,
  }
  shared.battleHotkeys = shared.commandMenu
end
