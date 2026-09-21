return function(mod, suite)
  local shared = suite.shared
  local Font = require("src.render.Font")
  local Sound = require("src.core.Sound")
  local TypeChart = require("src.battle.TypeChart")
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
  local LEGEND_SCALES = { 0.5, 0.6, 0.75, 0.9, 1, 1.25, 1.5 }
  local LEGEND_LAYOUTS = { "auto", "grid", "list" }
  local LEGEND_LAYOUT_LABELS = {
    auto = "AUTO", grid = "GRID 2x2", list = "LIST 1x4",
  }

  -- Three characters so every row's type column starts and ends on the same
  -- pixel whatever the move is.  Gen 2's two extra types are here so the
  -- column keeps its width if this ever runs on Gold.
  local TYPE_ABBR = {
    NORMAL = "NRM", FIGHTING = "FGT", FLYING = "FLY", POISON = "PSN",
    GROUND = "GRD", ROCK = "RCK", BUG = "BUG", GHOST = "GHO",
    STEEL = "STL", FIRE = "FIR", WATER = "WTR", GRASS = "GRS",
    ELECTRIC = "ELC", PSYCHIC = "PSY", ICE = "ICE", DRAGON = "DRG",
    DARK = "DRK", FAIRY = "FAI",
  }

  -- Pixel columns inside a move cell's second line, measured from the cell's
  -- left edge.  Fixed rather than flowed so power, type and accuracy line up
  -- down the whole legend instead of drifting with each move's name.
  local INFO_INDENT = 8
  local INFO_POWER_ICON = INFO_INDENT
  local INFO_POWER_TEXT = INFO_INDENT + 9
  local INFO_TYPE = INFO_POWER_TEXT + 26
  local INFO_ACC = INFO_TYPE + 28
  local INFO_WIDTH = INFO_ACC + 32 - INFO_INDENT

  local function config()
    local cfg = shared.store.get("battleHotkeys", nil)
    if type(cfg) ~= "table" then cfg = {} end
    if cfg.enabled == nil then cfg.enabled = false end
    cfg.bindings = type(cfg.bindings) == "table" and cfg.bindings or {}
    if not LEGEND_POSITION_LABELS[cfg.legendPosition] then
      cfg.legendPosition = "top_center"
    end
    local validScale = false
    for _, value in ipairs(LEGEND_SCALES) do
      if cfg.legendScale == value then validScale = true break end
    end
    if not validScale then cfg.legendScale = 1 end
    if not LEGEND_LAYOUT_LABELS[cfg.legendLayout] then
      cfg.legendLayout = "auto"
    end
    if cfg.moveInfo == nil then cfg.moveInfo = false end
    return cfg
  end

  local function save(cfg)
    shared.store.set("battleHotkeys", cfg)
  end

  local function battleState(game)
    return shared.battle.find(game)
  end

  local function commandReady(battle)
    if not shared.battle.commandMenuOpen(battle) then return false end
    if battle.safari then return (battle.safari.balls or 0) > 0 end
    local hp = shared.battle.fighterHp(battle)
    if not hp or hp <= 0 then return false end
    return true
  end

  local function moveReady(battle)
    return shared.battle.moveSelectOpen(battle)
      and type(shared.battle.moves(battle)) == "table"
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
    Sound.play(shared.battle.data(battle), "Press_AB")
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
    local moves = battle and shared.battle.moves(battle)
    if not command or not moveReady(battle) or not moves[command.index] then
      return false
    end
    battle.moveIndex = command.index
    Sound.play(shared.battle.data(battle), "Press_AB")
    battle:chooseMove(command.index)
    return true
  end

  local function runFromMenu(game)
    local battle = battleState(game)
    if not commandReady(battle) then return false end
    battle.menuIndex = 4
    Sound.play(shared.battle.data(battle), "Press_AB")
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

  -- `textWaiting` is the gate the Battle Text module drives auto-advance from:
  -- true only while the battle itself is the top state and is parked on a
  -- message waiting for input.  Choice prompts (yes/no, nickname, learn-move)
  -- push their own screen on top, so they stay under manual control.
  local function textWaiting(game, battle)
    if not battle then return false end
    if shared.battle.scripted(battle) then return false end
    local stack = game and game.stack
    if not stack or type(stack.top) ~= "function" then return false end
    if stack:top() ~= battle then return false end
    if battle.phase == "menu" or shared.battle.moveSelectOpen(battle) then
      return false
    end
    -- Gold's forget prompt is a phase on the battle screen rather than a
    -- pushed choice box, so it has to be excluded here to stay under manual
    -- control the way Red's pushed prompts already are.
    if shared.battle.learnChoiceOpen(battle) then return false end
    return shared.battle.textWaiting(battle)
  end

  -- A sword drawn from rectangles rather than a charmap glyph: the Gen 1
  -- font has no such tile, and anything traced from the ROM's own art would
  -- be ROM-derived content this mod must not ship.
  local function drawSword(x, y)
    local g = love.graphics
    g.rectangle("fill", x + 3, y, 2, 5)
    g.rectangle("fill", x + 1, y + 5, 6, 1)
    g.rectangle("fill", x + 3, y + 6, 2, 1)
    g.rectangle("fill", x + 2, y + 7, 4, 1)
  end

  -- The Gen 1 charmap has no '%' tile (263 glyphs, none of them a percent
  -- sign), so Font.draw would silently swallow it and leave the accuracy a
  -- bare number with no unit.  Drawn from rectangles for the same reason the
  -- sword is: two dots and a slash, no ROM art.
  local PERCENT_ADVANCE = 7
  local function drawPercent(x, y)
    local g = love.graphics
    g.rectangle("fill", x, y + 1, 2, 2)
    g.rectangle("fill", x + 4, y + 5, 2, 2)
    g.rectangle("fill", x + 4, y + 1, 1, 1)
    g.rectangle("fill", x + 3, y + 2, 1, 1)
    g.rectangle("fill", x + 2, y + 3, 1, 1)
    g.rectangle("fill", x + 1, y + 4, 1, 1)
    g.rectangle("fill", x, y + 5, 1, 1)
  end

  -- Mod-added types keep their own name, so fall back to its first three
  -- characters instead of showing a raw id that would not fit the column.
  local function typeAbbrev(battle, typeId)
    if not typeId then return "---" end
    local name = typeId
    local ok, display = pcall(TypeChart.displayName, typeId,
      shared.battle.data(battle))
    if ok and type(display) == "string" and display ~= "" then
      name = display
    end
    name = tostring(name):upper()
    local abbr = TYPE_ABBR[name]
    if abbr then return abbr end
    local letters = name:gsub("[^%w?]", "")
    if letters == "" then return "---" end
    return letters:sub(1, 3)
  end

  -- `def.accuracy` is already a percentage: Damage.accuracyThreshold scales
  -- it by 255/100 to reach the roll's byte range.
  local function moveStats(battle, move)
    local data = shared.battle.data(battle)
    local def = move and data and data.moves and data.moves[move.id]
    if not def then return nil end
    local power = tonumber(def.power) or 0
    local acc = tonumber(def.accuracy)
    return {
      power = power > 0 and tostring(math.floor(power)) or "--",
      type = typeAbbrev(battle, def.type),
      acc = acc and tostring(math.floor(acc + 0.5)) or "--",
      -- The sign is drawn, not printed, so the caller needs to know whether
      -- this row has a number to put one after.
      accPercent = acc ~= nil,
    }
  end

  local function legendEntries(battle, withInfo)
    if commandReady(battle) then
      return {
        { label = "FIGHT" }, { label = "PKMN" },
        { label = "ITEM" }, { label = "RUN" },
      }, false
    end
    if moveReady(battle) then
      local entries = {}
      local anyInfo = false
      local moves = shared.battle.moves(battle) or {}
      local data = shared.battle.data(battle)
      for index = 1, 4 do
        local move = moves[index]
        local def = move and data and data.moves and data.moves[move.id]
        local entry = {
          label = move and tostring(def and def.name or move.id) or "-",
        }
        if withInfo and move then
          entry.stats = moveStats(battle, move)
          if entry.stats then anyInfo = true end
        end
        entries[index] = entry
      end
      return entries, anyInfo
    end
  end

  -- Anchored to the PLAYFIELD rect, not the OS window.  On a portrait phone
  -- the window is far taller than the 10:9 frame, so window-relative
  -- placement pushed the legend down into the letterbox and off the visible
  -- game area; clamping to gameX/gameY/gameWidth/gameHeight keeps it over the
  -- frame on every aspect ratio.
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
    -- Never let either edge leave the frame, even when the legend is wider
    -- or taller than the margins allow for.
    x = math.max(0, math.min(x, nativeWidth - width))
    y = math.max(0, math.min(y, nativeHeight - height))
    return math.floor(x + 0.5), math.floor(y + 0.5)
  end

  -- The playfield rectangle in native (160x144) units, plus the pixel scale
  -- that maps it back to window units.
  local function playfieldRect(viewport)
    local scale = tonumber(viewport.scale) or 1
    if not (scale > 0) then scale = 1 end
    local w = (tonumber(viewport.gameWidth) or 160 * scale) / scale
    local h = (tonumber(viewport.gameHeight) or 144 * scale) / scale
    if not (w > 0) then w = 160 end
    if not (h > 0) then h = 144 end
    return tonumber(viewport.gameX) or 0, tonumber(viewport.gameY) or 0,
      w, h, scale
  end

  -- Cell geometry for one layout, before any fitting is applied.
  local function legendMetrics(entries, showInfo, columns)
    local maxLabel = 0
    for _, entry in ipairs(entries) do
      maxLabel = math.max(maxLabel, Font.width(entry.label or ""))
    end
    local cellW = math.max(72, maxLabel + 24)
    local cellH = 16
    if showInfo then
      cellW = math.max(cellW, INFO_INDENT + INFO_WIDTH + 4)
      cellH = 26
    end
    local rows = math.ceil(4 / columns)
    return cellW, cellH, cellW * columns, cellH * rows
  end

  -- Chooses the layout and the scale that keeps the legend inside `nativeW` x
  -- `nativeH`.  Pure geometry so the no-overflow guarantee can be asserted
  -- directly instead of inferred from a draw call.
  local function legendLayout(entries, cfg, showInfo, nativeW, nativeH)
    local function fitFor(columns)
      local cellW, cellH, fullW, fullH =
        legendMetrics(entries, showInfo, columns)
      local room = math.min((nativeW - 8) / fullW, (nativeH - 8) / fullH)
      return {
        columns = columns, cellW = cellW, cellH = cellH,
        fullW = fullW, fullH = fullH,
        scale = math.min(cfg.legendScale, room),
      }
    end

    local pick = fitFor(cfg.legendLayout == "list" and 1 or 2)
    if cfg.legendLayout == "auto" then
      -- One column is far narrower, so prefer it whenever the 2x2 grid would
      -- have to shrink below the size the player asked for -- which is what a
      -- tall portrait screen forces.
      local list = fitFor(1)
      if list.scale > pick.scale then pick = list end
    end
    pick.scale = math.max(0.25, pick.scale)
    pick.width = pick.fullW * pick.scale
    pick.height = pick.fullH * pick.scale
    return pick
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
    if not ((active.keyboard or active.gamepad) and customBattleUI(battle)
        and viewport) then
      return
    end
    local cfg = config()
    local entries, hasInfo = legendEntries(battle, cfg.moveInfo)
    if not entries then return end
    local showInfo = cfg.moveInfo and hasInfo or false

    local originX, originY, nativeWidth, nativeHeight, scale =
      playfieldRect(viewport)
    local layout = legendLayout(entries, cfg, showInfo,
      nativeWidth, nativeHeight)
    local columns, cellW, cellH = layout.columns, layout.cellW, layout.cellH
    local legendScale = layout.scale
    local startX, startY = legendOrigin(cfg.legendPosition,
      layout.width, layout.height, nativeWidth, nativeHeight)
    local g = love.graphics
    g.push("all")
    g.origin()
    g.translate(originX + startX * scale, originY + startY * scale)
    g.scale(scale * legendScale, scale * legendScale)
    for index, direction in ipairs(DIRECTION_FOR_INDEX) do
      local col = (index - 1) % columns
      local row = math.floor((index - 1) / columns)
      local x = col * cellW
      local y = row * cellH
      local entry = entries[index] or {}
      g.setColor(1, 1, 1, 0.88)
      g.rectangle("fill", x, y, cellW, cellH)
      g.setColor(0, 0, 0, 1)
      g.rectangle("line", x, y, cellW, cellH)
      drawArrow(x + 4, y + 4, direction)
      Font.draw(entry.label or "", x + 16, y + 4)
      local stats = showInfo and entry.stats
      if stats then
        local infoY = y + 14
        drawSword(x + INFO_POWER_ICON, infoY)
        Font.draw(stats.power, x + INFO_POWER_TEXT, infoY)
        Font.draw(stats.type, x + INFO_TYPE, infoY)
        Font.draw(stats.acc, x + INFO_ACC, infoY)
        if stats.accPercent then
          drawPercent(x + INFO_ACC + Font.width(stats.acc), infoY)
        end
      end
    end
    g.pop()
    local labels = {}
    for index, entry in ipairs(entries) do labels[index] = entry.label end
    customLegend = {
      battle = battle, labels = labels, entries = entries,
      position = cfg.legendPosition, scale = legendScale,
      columns = columns, showInfo = showInfo,
    }
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
          end
        end),
      {
        id = "battle.commands.binding",
        label = "CMD MODE",
        value = function() return shared.comboLabel(config().bindings[inputId]) end,
        help = "Hold this in battle to steer the command menu and the move "
          .. "list with the D-pad. The vanilla cursor is replaced by arrows "
          .. "matching each entry.",
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
        help = "Runs from battle in one press. Only works from the main "
          .. "battle menu.",
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
        help = "Where the floating command legend appears when a custom "
          .. "battle UI mod hides the vanilla bottom panel.",
        step = function(_, dir)
          local cfg = config()
          cfg.legendPosition = shared.cycle(
            LEGEND_POSITIONS, cfg.legendPosition, dir)
          save(cfg)
          return true
        end,
      },
      {
        id = "battle.legend.layout",
        label = "UI LAYOUT",
        value = function()
          return LEGEND_LAYOUT_LABELS[config().legendLayout]
        end,
        help = "How the floating legend is arranged. AUTO uses a single "
          .. "column whenever a 2x2 grid would have to shrink to fit, which "
          .. "is what a tall phone screen needs.",
        step = function(_, dir)
          local cfg = config()
          cfg.legendLayout = shared.cycle(
            LEGEND_LAYOUTS, cfg.legendLayout, dir)
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
        help = "Largest size the floating legend may use. It is shrunk below "
          .. "this whenever it would not otherwise fit on screen.",
        step = function(_, dir)
          local cfg = config()
          cfg.legendScale = shared.cycle(
            LEGEND_SCALES, cfg.legendScale, dir)
          save(cfg)
          return true
        end,
      },
      {
        id = "battle.legend.moveInfo",
        label = "MOVE INFO",
        value = function() return config().moveInfo and "ON" or "OFF" end,
        help = "Adds a second line to each move showing its power beside a "
          .. "sword, its type shortened to three letters, and its accuracy "
          .. "as a percentage.",
        step = function()
          local cfg = config()
          cfg.moveInfo = not cfg.moveInfo
          save(cfg)
          return true
        end,
        unassign = function()
          local cfg = config()
          cfg.moveInfo = false
          save(cfg)
          return true
        end,
      },
    }
  end

  suite.register("keyboard", {
    id = "command_menu", label = "BATTLE CMD MENU", context = "battle",
    rows = rows,
  })
  suite.register("gamepad", {
    id = "command_menu", label = "BATTLE CMD MENU", context = "battle",
    rows = rows,
  })

  shared.registerReset(function()
    local cfg = config()
    cfg.enabled = false
    cfg.moveInfo = false
    save(cfg)
    active.keyboard, active.gamepad = false, false
  end)

  shared.commandMenu = {
    active = active,
    battleState = battleState,
    choose = choose,
    chooseMove = chooseMove,
    config = config,
    customBattleUI = customBattleUI,
    customLegend = function() return customLegend end,
    commands = COMMANDS,
    infoColumns = function()
      return {
        indent = INFO_INDENT, powerIcon = INFO_POWER_ICON,
        powerText = INFO_POWER_TEXT, type = INFO_TYPE, acc = INFO_ACC,
        width = INFO_WIDTH, percentAdvance = PERCENT_ADVANCE,
      }
    end,
    legendEntries = legendEntries,
    legendLayout = legendLayout,
    legendMetrics = legendMetrics,
    legendOrigin = legendOrigin,
    playfieldRect = playfieldRect,
    runFromMenu = runFromMenu,
    specs = specs,
    textWaiting = textWaiting,
    typeAbbrev = typeAbbrev,
    scales = LEGEND_SCALES,
  }
  shared.battleHotkeys = shared.commandMenu
end
