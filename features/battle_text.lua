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
    if cfg.skipLevelUpSfx == nil then cfg.skipLevelUpSfx = false end
    if cfg.learnPrompt == nil then cfg.learnPrompt = false end
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

  -- MoveLearnMenu (src/ui/MoveLearnMenu.lua) is a local class, so it is
  -- matched by the pair of fields nothing else on the stack carries: the id
  -- of the move being learned and the name of the fanfare to play once it
  -- is.  Both are set in its constructor and never cleared.
  local function isMoveLearnMenu(state)
    return type(state) == "table"
      and rawget(state, "newMoveId") ~= nil
      and rawget(state, "learnedSound") ~= nil
      and type(rawget(state, "mon")) == "table"
      and type(state.update) == "function"
      and type(state.draw) == "function"
  end

  -- True while the "trying to learn / delete an older move?" flow owns the
  -- screen.  Everything this module does to the learn flow is gated on it, so
  -- no other prompt in the game can be touched.
  local function learningMove(game)
    local states = game and game.stack and game.stack.states
    for i = #(states or {}), 1, -1 do
      if isMoveLearnMenu(states[i]) then return states[i] end
    end
  end

  -- A TextBox is identified by its pagination state: the page list plus the
  -- index/waiting/done trio that drives it.
  local function isTextBox(state)
    return type(state) == "table"
      and type(rawget(state, "pages")) == "table"
      and type(rawget(state, "pageIndex")) == "number"
      and rawget(state, "waiting") ~= nil
      and rawget(state, "done") ~= nil
  end

  -- True when a TextBox is parked on a button press.  A box does not report
  -- that itself, so the states are read back from its own fields in the order
  -- TextBox:update tests them:
  --   * before the last page, `waiting` is the mid-text arrow;
  --   * once `done`, `stay` only blocks when it asked for a prompt, `auto`
  --     drives itself except for promptFirst (and auto.wait clears `auto`
  --     before the box reaches the button), `choice` is the player's;
  --   * anything else past `done` is the plain A/B dismissal.
  local function textBoxBlocked(box)
    if not isTextBox(box) then return false end
    if box.done ~= true then return box.waiting == true end
    local stay = rawget(box, "stay")
    if stay ~= nil then
      return type(stay) == "table" and stay.prompt == true
        and box.stayShown ~= true
    end
    local auto = rawget(box, "auto")
    if auto ~= nil then
      return type(auto) == "table" and auto.promptFirst == true
        and box.autoPrompted ~= true
    end
    if rawget(box, "choice") ~= nil then return false end
    return true
  end

  -- Battle messages that are not the battle's own queue: the learned-move
  -- pages, "did not learn", "HM techniques can't be deleted!", the blackout.
  -- They are TextBoxes pushed over the battle, so the queue's msgWaiting flag
  -- never sees them and each one parks on a button.  Boxes carrying a
  -- `choice` are skipped whole -- walking a yes/no's pages is LEARN TEXT's
  -- job, and only for the learn prompt.
  local function battleBoxWaiting(game, battle)
    if not battle or battle.demo then return false end
    local stack = game and game.stack
    local top = stack and type(stack.top) == "function" and stack:top() or nil
    if not isTextBox(top) then return false end
    if rawget(top, "choice") ~= nil then return false end
    return textBoxBlocked(top)
  end

  -- The learn-a-move prompt is one TextBox holding several pages that ends in
  -- a YES/NO.  `waiting` is true only between pages; the frame the last page
  -- finishes the box sets `done` and pushes the ChoiceBox itself.  Advancing
  -- only while `waiting` therefore walks the preamble and stops dead at the
  -- decision -- it can never answer it.
  local function learnPromptWaiting(game)
    if not learningMove(game) then return false end
    local stack = game and game.stack
    local top = stack and type(stack.top) == "function" and stack:top() or nil
    if not isTextBox(top) then return false end
    if top.choice == nil then return false end
    return top.waiting == true and top.done ~= true
      and top.choicePushed ~= true
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
    if cfg.learnPrompt and learnPromptWaiting(game) then
      return "learnPrompt", cfg
    end
    if cfg.autoText then
      local commandMenu = shared.commandMenu
      local waiting = commandMenu
        and type(commandMenu.textWaiting) == "function"
        and commandMenu.textWaiting(game, battle)
      if waiting then return "text", cfg end
      if battleBoxWaiting(game, battle) then return "text", cfg end
    end
    return nil, cfg
  end

  -- The level-up fanfare is queued by BattleState:sayNextAutoWaitSfx, the only
  -- engine caller that sets BOTH `auto` and `waitForLearningSfx` -- every
  -- other blocking fanfare (caught mon, dex page, learned move) goes through
  -- sayNextWaitSfx and carries no `auto`.  That pairing is what identifies the
  -- "grew to level N!" row without naming anything private.
  local function isLevelUpSfxItem(item)
    return type(item) == "table" and item.auto == true
      and type(item.waitForLearningSfx) == "function"
  end

  -- A move learned into a free slot queues its fanfare through the *same*
  -- sayNextWaitSfx that the caught-mon and trainer-defeat jingles use, so the
  -- row cannot be told apart structurally.  BattleState:learnMove emits
  -- pokemon.move_learned immediately before queueing it, though, so that
  -- event is used as the anchor: it arms a short window during which a
  -- fanfare row is known to be the learned-move one.
  local LEARNED_SFX_WINDOW = 2.0
  local learnedSfxArmed = 0
  mod.events:on("pokemon.move_learned", function()
    if config().skipLevelUpSfx then learnedSfxArmed = LEARNED_SFX_WINDOW end
  end)

  local function isLearnedMoveSfxItem(item)
    return learnedSfxArmed > 0 and type(item) == "table"
      and type(item.waitForLearningSfx) == "function"
  end

  -- Claiming the row's sound before updateQueue reaches it means the fanfare
  -- is never started, so WaitForSoundToFinish never blocks: the page then
  -- falls through to the normal `auto` branch and the queue carries on.
  local function skipLevelUpSfx(game, dt)
    local cfg = config()
    if not (cfg.enabled and cfg.skipLevelUpSfx) then
      learnedSfxArmed = 0
      return
    end
    -- Replacing one of four moves never reaches the battle queue: the fanfare
    -- is a TextBox auto-sound owned by MoveLearnMenu:finish.  Dropping the
    -- sound before the box starts it leaves autoSrc nil, so the box skips the
    -- wait entirely and `auto.wait` hands it straight to the normal A/B path.
    if learningMove(game) then
      local states = game and game.stack and game.stack.states
      for i = #(states or {}), 1, -1 do
        local state = states[i]
        if isTextBox(state) and type(rawget(state, "auto")) == "table"
            and state.auto.sound and not state.autoStarted then
          state.auto.sound = nil
        end
      end
    end
    local battle = battleState(game)
    if not battle then return end
    local claimed = false
    local current = battle.current
    local function claim(item)
      if not item or item.soundStarted then return false end
      if isLevelUpSfxItem(item) or isLearnedMoveSfxItem(item) then
        item.soundStarted = true
        return true
      end
      return false
    end
    if claim(current) then claimed = true end
    for _, item in ipairs(battle.queue or {}) do
      if claim(item) then claimed = true end
    end
    -- Already sounding (the row became current and finished printing inside a
    -- single step): cut it short and release the queue's hold.
    if battle.waitingSound and current
        and (isLevelUpSfxItem(current) or isLearnedMoveSfxItem(current)) then
      local src = battle.waitingSound
      if type(src) == "table" or type(src) == "userdata" then
        pcall(function() if src.stop then src:stop() end end)
      end
      battle.waitingSound, battle.waitSoundLeft = nil, nil
    end
    if claimed then
      learnedSfxArmed = 0
    elseif learnedSfxArmed > 0 then
      learnedSfxArmed = learnedSfxArmed - (dt or 0)
      if learnedSfxArmed < 0 then learnedSfxArmed = 0 end
    end
  end

  mod.hooks:wrap("input.step", function(next, game, dt)
    next(game, dt)
    skipLevelUpSfx(game, dt)
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
        help = "Advances battle messages for you, including the ones that "
          .. "follow learning a move. Menus, move select and yes/no prompts "
          .. "stay under your control.",
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
        id = "battleText.skipLevelUpSfx",
        label = "SKIP LV SFX",
        value = function()
          return config().skipLevelUpSfx and "ON" or "OFF"
        end,
        help = "Silences the level-up jingle and the one for learning a new "
          .. "move. The battle waits for those fanfares to finish before it "
          .. "carries on, so skipping them removes the pause as well.",
        step = function()
          local cfg = config()
          cfg.skipLevelUpSfx = not cfg.skipLevelUpSfx
          save(cfg)
          return true
        end,
        unassign = function()
          local cfg = config()
          cfg.skipLevelUpSfx = false
          save(cfg)
          return true
        end,
      },
      {
        id = "battleText.learnPrompt",
        label = "LEARN TEXT",
        value = function() return config().learnPrompt and "ON" or "OFF" end,
        help = "When a move is learned with all four slots full, advances "
          .. "the pages in front of the YES/NO and stops there. The choice "
          .. "to delete an older move is always left to you.",
        step = function()
          local cfg = config()
          cfg.learnPrompt = not cfg.learnPrompt
          save(cfg)
          return true
        end,
        unassign = function()
          local cfg = config()
          cfg.learnPrompt = false
          save(cfg)
          return true
        end,
      },
      {
        id = "battleText.speed",
        label = "SPEED",
        value = function() return SPEEDS[config().speed].label end,
        help = "How long each message is held before it is advanced. Used by "
          .. "AUTO TEXT, LEVEL UP and LEARN TEXT.",
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
    cfg.skipLevelUpSfx = false
    cfg.learnPrompt = false
    save(cfg)
  end)

  shared.battleText = {
    battleBoxWaiting = battleBoxWaiting,
    config = config,
    isLevelUpStatBox = isLevelUpStatBox,
    isLevelUpSfxItem = isLevelUpSfxItem,
    isMoveLearnMenu = isMoveLearnMenu,
    isTextBox = isTextBox,
    learnPromptWaiting = learnPromptWaiting,
    learningMove = learningMove,
    pending = pending,
    skipLevelUpSfx = skipLevelUpSfx,
    speeds = SPEEDS,
    textBoxBlocked = textBoxBlocked,
  }
end
