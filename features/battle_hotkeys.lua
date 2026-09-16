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

  local function config()
    local cfg = mod.save:get("battleHotkeys", {})
    if type(cfg) ~= "table" then cfg = {} end
    cfg.bindings = type(cfg.bindings) == "table" and cfg.bindings or {}
    if cfg.touch == nil then cfg.touch = false end
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
    if not config().touch or not viewport or not commandReady(battleState(game)) then
      return
    end
    local scale = viewport.scale or 1
    local cells = {
      { direction = "up", x = 4, y = 4 },
      { direction = "right", x = 122, y = 4 },
      { direction = "left", x = 4, y = 116 },
      { direction = "down", x = 122, y = 116 },
    }
    local g = love.graphics
    g.push("all")
    g.origin()
    g.translate(viewport.gameX or 0, viewport.gameY or 0)
    g.scale(scale, scale)
    for _, cell in ipairs(cells) do
      local label = COMMANDS[cell.direction].label
      g.setColor(1, 1, 1, 0.88)
      g.rectangle("fill", cell.x, cell.y, 34, 24)
      g.setColor(0, 0, 0, 1)
      g.rectangle("line", cell.x, cell.y, 34, 24)
      Font.draw(label,
        cell.x + math.floor((34 - Font.width(label)) / 2), cell.y + 8)
      touchRects[#touchRects + 1] = {
        direction = cell.direction,
        x = (viewport.gameX or 0) + cell.x * scale,
        y = (viewport.gameY or 0) + cell.y * scale,
        w = 34 * scale,
        h = 24 * scale,
      }
    end
    g.pop()
  end, 30000)

  mod.hooks:wrap("input.pointer", function(next, game, ev)
    if next(game, ev) then return true end
    if ev.phase ~= "pressed" then return false end
    for _, rect in ipairs(touchRects) do
      if ev.x >= rect.x and ev.x <= rect.x + rect.w
          and ev.y >= rect.y and ev.y <= rect.y + rect.h then
        return choose(game, rect.direction)
      end
    end
    return false
  end)

  local function rows(_, inputId)
    local commandSpec = specs.commands[inputId]
    local runSpec = specs.run[inputId]
    return {
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

  local function touchRows()
    return {
      {
        id = "battle.commands.touch",
        label = "COMMAND BUTTONS",
        value = function() return config().touch and "ON" or "OFF" end,
        step = function()
          local cfg = config()
          cfg.touch = not cfg.touch
          save(cfg)
          return true
        end,
        unassign = function()
          local cfg = config()
          cfg.touch = false
          save(cfg)
          return true
        end,
      },
    }
  end

  suite.register("keyboard", {
    id = "battle_hotkeys", label = "BATTLE HOTKEYS", rows = rows,
  })
  suite.register("gamepad", {
    id = "battle_hotkeys", label = "BATTLE HOTKEYS", rows = rows,
  })
  suite.register("touchscreen", {
    id = "battle_hotkeys", label = "BATTLE HOTKEYS", rows = touchRows,
  })

  shared.registerStats(function()
    return config().touch and 1 or 0, config().touch and 1 or 0
  end)

  shared.registerReset(function()
    local cfg = config()
    cfg.touch = false
    save(cfg)
    active.keyboard, active.gamepad = false, false
  end)

  shared.battleHotkeys = {
    active = active,
    choose = choose,
    chooseMove = chooseMove,
    config = config,
    customBattleUI = customBattleUI,
    customLegend = function() return customLegend end,
    commands = COMMANDS,
    runFromMenu = runFromMenu,
    specs = specs,
  }
end
