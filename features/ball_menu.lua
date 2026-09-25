return function(mod, suite)
  local shared = suite.shared
  local Font = require("src.render.Font")
  local Screens = require("src.ui.Screens")
  local Strings = require("src.core.Strings")
  local Sound = require("src.core.Sound")
  local Bag = require("src.inventory.Bag")
  local ItemEffects = require("src.inventory.ItemEffects")

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
  local MODES = { "menu", "quick" }
  local MODE_LABELS = { menu = "BALL MENU", quick = "QUICK THROW" }
  local QUICK_BALLS = { "FIRST", "POKE_BALL", "GREAT_BALL", "ULTRA_BALL", "MASTER_BALL" }
  local QUICK_BALL_LABELS = {
    FIRST = "FIRST IN BAG",
    POKE_BALL = "POKE BALL",
    GREAT_BALL = "GREAT BALL",
    ULTRA_BALL = "ULTRA BALL",
    MASTER_BALL = "MASTER BALL",
  }

  local function config()
    local cfg = shared.store.get("ballMenu", nil)
    if type(cfg) ~= "table" then cfg = {} end
    if cfg.enabled == nil then cfg.enabled = false end
    cfg.bindings = type(cfg.bindings) == "table" and cfg.bindings or {}
    if cfg.mode ~= "menu" and cfg.mode ~= "quick" then cfg.mode = "menu" end
    if not POSITION_LABELS[cfg.position] then cfg.position = "top_right" end
    if not QUICK_BALL_LABELS[cfg.quickBall] then cfg.quickBall = "FIRST" end
    return cfg
  end
  local function save(cfg) shared.store.set("ballMenu", cfg) end

  local G3 = shared.battle.gen3

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

  local function isBall(id, battle)
    if not id then return false end
    -- Gold tags every ball with the BALL pocket, which is exact where a name
    -- list is only as good as its last update.
    if battle and shared.battle.pocketIsBall(battle, id) then return true end
    if ItemEffects and type(ItemEffects.isBall) == "function" then
      local ok, res = pcall(ItemEffects.isBall, id)
      if ok and res then return true end
    end
    return id == "POKE_BALL" or id == "GREAT_BALL" or id == "ULTRA_BALL"
      or id == "MASTER_BALL" or id == "SAFARI_BALL"
  end

  local function getBallName(data, id)
    local def = data and data.items and data.items[id]
    local name = def and def.name or id
    return Strings(name)
  end

  local function getAvailableBalls(battle)
    local balls = {}
    if not battle then return balls end
    local contest = shared.battle.contestBalls(battle)
    if contest then
      if contest.count > 0 then
        balls[#balls + 1] = {
          id = contest.id,
          name = getBallName(shared.battle.data(battle), contest.id),
          count = contest.count,
        }
      end
      return balls
    end
    if battle.safari then
      local count = battle.safari.balls or 0
      if count > 0 then
        balls[#balls + 1] = {
          id = "SAFARI_BALL",
          name = getBallName(shared.battle.data(battle), "SAFARI_BALL"),
          count = count,
        }
      end
      return balls
    end
    local saveObj = battle.game and battle.game.save
    if not saveObj or not saveObj.inventory then return balls end
    local order = Bag and Bag.order and Bag.order(saveObj) or saveObj.bagOrder or {}
    local seen = {}
    for _, id in ipairs(order) do
      if isBall(id, battle) and not seen[id] then
        seen[id] = true
        local count = saveObj.inventory[id] or 0
        if count > 0 then
          balls[#balls + 1] = {
            id = id,
            name = getBallName(shared.battle.data(battle), id),
            count = count,
          }
        end
      end
    end
    for id, count in pairs(saveObj.inventory) do
      if isBall(id, battle) and not seen[id] and count > 0 then
        seen[id] = true
        balls[#balls + 1] = {
          id = id,
          name = getBallName(shared.battle.data(battle), id),
          count = count,
        }
      end
    end
    return balls
  end

  local function executeThrow(battle, ballId)
    if not battle then return false end
    -- Gold has no throwBall.  BattleState:useItem is its single entry point
    -- and already owns the trainer-battle refusal, the full-box gate, the
    -- catch roll and spending the ball (or decrementing the contest counter),
    -- so none of Red's state-machine setup below applies here -- and spending
    -- the ball a second time would charge the player twice for one throw.
    if shared.battle.usesEngineItemPath(battle) then
      if not ballId then return false end
      return shared.battle.throwBall(battle, ballId)
    end
    if battle.safari then
      if (battle.safari.balls or 0) <= 0 then
        battle.phase = "messages"
        battle.afterQueue = "menu"
        battle:say(Strings("You're all out\nof SAFARI BALLs!"))
        return true
      end
      battle:safariAction("ball")
      return true
    end
    local saveObj = battle.game and battle.game.save
    if not saveObj then return false end
    battle.phase = "messages"
    battle.afterQueue = "menu"
    if not ballId or not saveObj.inventory or (saveObj.inventory[ballId] or 0) <= 0 then
      battle:say(Strings("You're all out\nof POKé BALLs!"))
      return true
    end
    if Bag and Bag.remove then
      Bag.remove(saveObj, ballId, 1)
    else
      saveObj.inventory[ballId] = saveObj.inventory[ballId] - 1
      if saveObj.inventory[ballId] <= 0 then saveObj.inventory[ballId] = nil end
    end
    battle:throwBall(ballId)
    return true
  end

  local Screen = {}
  Screen.__index = Screen
  Screen.isOpaque = false

  function Screen:sgbPalettes(game)
    return require("src.render.PaletteFX").wholeNamed(game.data, "MEWMON")
  end

  function Screen:update()
    local input = self.game.input
    local count = #self.items
    if count == 0 then
      if input:wasPressed("a") or input:wasPressed("b") or input:wasPressed("start")
          or input:wasPressed("select") then
        self.game.stack:pop()
      end
      return
    end

    local step = 0
    if input:wasPressed("left") or input:wasPressed("up") then step = -1
    elseif input:wasPressed("right") or input:wasPressed("down") then step = 1 end

    if step ~= 0 then
      self.index = ((self.index - 1 + step) % count) + 1
      if Sound and Sound.play then Sound.play(self.game.data, "Press_AB") end
    elseif input:wasPressed("a") then
      local selected = self.items[self.index]
      self.game.stack:pop()
      if selected then executeThrow(self.battle, selected.id) end
    elseif input:wasPressed("b") or input:wasPressed("start")
        or input:wasPressed("select") then
      self.game.stack:pop()
    end
  end

  local function drawArrow(x, y, flipped)
    love.graphics.push()
    love.graphics.translate(x + 4, y + 4)
    if flipped then love.graphics.rotate(math.pi) end
    Font.drawCode(0xED, -4, -4)
    love.graphics.pop()
  end

  -- Pixel-exact border, matching the radial menu's fix for the same class of
  -- bug: Font.drawBox snaps to the 8px tile grid, which can land a few
  -- pixels away from a position computed as a float (e.g. a centered box).
  -- Text was already drawn at the unsnapped pixel position, so the two
  -- disagreed. Drawing the border at the same float position keeps both in
  -- sync regardless of which of the 9 positions is selected.
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

  -- One row only. The selector expands horizontally instead of listing every
  -- ball vertically, so replacement battle UIs keep their own screen space.
  function Screen:draw()
    local g = love.graphics
    local cfg = config()
    local items = self.items
    local multiple = #items > 1

    local maxTextWidth = 0
    for _, item in ipairs(items) do
      local width = Font.width(item.name)
      if item.count then width = width + 8 + Font.width("x" .. item.count) end
      maxTextWidth = math.max(maxTextWidth, width)
    end
    if #items == 0 then
      maxTextWidth = math.max(maxTextWidth, Font.width("NO BALLS"))
    end

    -- 8px border each side, plus an 8px arrow gutter each side when cycling.
    local gutter = multiple and 16 or 0
    local tw = math.max(10, math.min(20,
      math.ceil((maxTextWidth + gutter + 16) / 8)))
    local th = 3
    local boxW, boxH = tw * 8, th * 8

    local pos = cfg.position or "top_right"
    local posX = pos:find("left", 1, true) and 0
      or (pos:find("right", 1, true) and (160 - boxW) or math.floor((160 - boxW) / 2))
    local posY = pos:find("top", 1, true) and 0
      or (pos:find("bottom", 1, true) and (144 - boxH) or math.floor((144 - boxH) / 2))
    posX = math.max(0, math.min(160 - boxW, posX))
    posY = math.max(0, math.min(144 - boxH, posY))

    g.push()
    g.setColor(1, 1, 1, 1)
    drawBox(posX, posY, boxW, boxH)
    g.setColor(0, 0, 0, 1)

    local textY = posY + 8
    if #items == 0 then
      Font.draw("NO BALLS", posX + 8, textY)
    else
      local item = items[self.index]
      local left = posX + 8 + (multiple and 8 or 0)
      Font.draw(item.name, left, textY)
      if item.count then
        local countStr = "x" .. item.count
        Font.draw(countStr,
          posX + boxW - 8 - (multiple and 8 or 0) - Font.width(countStr), textY)
      end
      if multiple then
        drawArrow(posX + 8, textY, true)
        drawArrow(posX + boxW - 16, textY, false)
      end
    end
    g.pop()
    g.setColor(1, 1, 1, 1)
  end

  mod.content.screens:register("HotkeySuiteBallMenu", {
    new = function(game, battle, items)
      return setmetatable({
        game = game, battle = battle, items = items, index = 1,
      }, Screen)
    end,
  })

  -- FireRed has no `game.stack` to push the custom picker screen above onto
  -- (see radial.lua's own comment on the same limitation), so "menu" mode
  -- reuses the real BAG screen instead of reinventing a second one: jumped
  -- straight to its BALLS pocket rather than the ITEMS pocket a plain ITEM
  -- press would land on. battle/init.lua's own command-phase dispatch
  -- already hands every press to that screen exclusively once it is open
  -- (BagMenu.isOpen()), so it needs no input handling of its own here, and
  -- the UI POSITION setting below has no effect on it -- there is nothing
  -- to move, it is FireRed's own native screen at its own native spot.
  local function triggerBallActionGen3()
    if not (G3 ~= nil and G3.commandMenuOpen()) then return false end
    local cfg = config()
    -- A Safari sub-battle's only "ball" is the BALL row itself
    -- (commands.lua's SAFARI_MENU); there is no BAG to open or second type
    -- to pick between, so both modes just throw it -- checked directly
    -- rather than inferred from ballBag()'s result, so a Safari battle that
    -- has just run out of balls refuses cleanly instead of falling through
    -- to openBallBag() and offering a BAG screen Safari does not have.
    if G3.isSafariBattle and G3.isSafariBattle() then
      local balls = G3.ballBag()
      if not balls[1] then return false end
      return G3.throwBall(balls[1].id)
    end
    local balls = G3.ballBag()
    if cfg.mode == "quick" then
      local ballId
      if cfg.quickBall ~= "FIRST" then
        local wanted = G3.itemIdForName and G3.itemIdForName(cfg.quickBall)
        for _, entry in ipairs(balls) do
          if wanted and entry.id == wanted then
            ballId = entry.id
            break
          end
        end
      end
      if not ballId and balls[1] then ballId = balls[1].id end
      if ballId then return G3.throwBall(ballId) end
      -- Configured/first ball is not actually in the bag: fall through to
      -- the BALLS pocket itself rather than doing nothing, the same as
      -- Gen 1/2 falling through to BattleState's own "out of balls" refusal
      -- instead of silently eating the press.
    end
    return G3.openBallBag and G3.openBallBag() or false
  end

  local function triggerBallAction(game)
    local cfg = config()
    if not cfg.enabled then return false end
    local battle = battleState(game)
    if not battle then return triggerBallActionGen3() end
    if not commandReady(battle) then return false end
    local available = getAvailableBalls(battle)
    if cfg.mode == "quick" then
      local ballToThrow = nil
      if battle.safari then
        ballToThrow = "SAFARI_BALL"
      elseif cfg.quickBall ~= "FIRST" then
        local saveObj = game and game.save
        if saveObj and saveObj.inventory and (saveObj.inventory[cfg.quickBall] or 0) > 0 then
          ballToThrow = cfg.quickBall
        end
      end
      if not ballToThrow and #available > 0 then
        ballToThrow = available[1].id
      end
      return executeThrow(battle, ballToThrow)
    end
    Screens.push(game, "HotkeySuiteBallMenu", battle, available)
    return true
  end

  local specs = {}
  for _, inputId in ipairs({ "keyboard", "gamepad" }) do
    local current = inputId
    specs[inputId] = shared.registerHotkey({
      id = "ball_menu." .. inputId,
      input = inputId,
      context = "battle",
      enabled = function() return config().enabled end,
      get = function() return config().bindings[current] end,
      set = function(value)
        local cfg = config()
        cfg.bindings[current] = value or false
        save(cfg)
      end,
      onFire = function(game) return triggerBallAction(game) end,
    })
  end

  local function rows(_, inputId)
    local spec = specs[inputId]
    return {
      shared.enabledRow("ballMenu.enabled",
        function() return config().enabled end,
        function(value)
          local cfg = config()
          cfg.enabled = value
          save(cfg)
        end),
      {
        id = "ballMenuBinding",
        label = "HOTKEY",
        value = function() return shared.comboLabel(spec:get()) end,
        help = "Pressed from the main battle menu to throw a ball. It does "
          .. "nothing anywhere else.",
        activate = function(game)
          shared.captureCombo(game, "BALL HOTKEY", spec)
        end,
        unassign = function()
          shared.setBinding(spec, nil)
          return true
        end,
      },
      {
        id = "ballMenuMode",
        label = "BEHAVIOR",
        value = function() return MODE_LABELS[config().mode] end,
        help = "BALL MENU opens a picker listing the balls you carry. QUICK "
          .. "THROW skips the picker and throws the ball chosen below.",
        step = function(_, dir)
          local cfg = config()
          cfg.mode = shared.cycle(MODES, cfg.mode, dir)
          save(cfg)
          return true
        end,
      },
      {
        id = "ballMenuPosition",
        label = "UI POSITION",
        value = function() return POSITION_LABELS[config().position] end,
        help = "Where the ball picker is drawn. Move it clear of any custom "
          .. "battle UI you have installed. Has no effect on FireRed, which "
          .. "shows its own BAG screen instead of this suite's picker.",
        step = function(_, dir)
          local cfg = config()
          cfg.position = shared.cycle(POSITIONS, cfg.position, dir)
          save(cfg)
          return true
        end,
      },
      {
        id = "ballMenuQuickBall",
        label = "QUICK BALL",
        value = function() return QUICK_BALL_LABELS[config().quickBall] end,
        help = "Which ball QUICK THROW uses. FIRST IN BAG picks the first "
          .. "ball you are carrying.",
        step = function(_, dir)
          local cfg = config()
          cfg.quickBall = shared.cycle(QUICK_BALLS, cfg.quickBall, dir)
          save(cfg)
          return true
        end,
      },
    }
  end

  suite.register("keyboard", {
    id = "ball_menu", label = "BALL MENU", context = "battle", rows = rows,
  })
  suite.register("gamepad", {
    id = "ball_menu", label = "BALL MENU", context = "battle", rows = rows,
  })

  shared.registerReset(function()
    local cfg = config()
    cfg.enabled = false
    save(cfg)
  end)

  shared.ballMenu = {
    config = config,
    executeThrow = executeThrow,
    getAvailableBalls = getAvailableBalls,
    specs = specs,
    trigger = triggerBallAction,
  }
end
