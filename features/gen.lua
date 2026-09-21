-- Generation adapter for the battle modules.
--
-- Gold is a second engine beside Red rather than a skin over it: a Gen 2 boot
-- runs src/ui/gen2/BattleState.lua, which keeps its own phase vocabulary and
-- its own message plumbing.  Every read and write the battle modules make goes
-- through this file so the difference is stated once.
--
-- Each helper probes for the capability it needs instead of asking which game
-- is running.  A version allow-list would drop the suite out of Gold by
-- construction -- the adapters would resolve, the patches would land, and the
-- features would still never appear -- which is the failure the engine's own
-- porting guide calls the most confusing possible outcome.
return function(mod, suite)
  local shared = suite.shared
  local battle = {}

  -- The battle is whichever stack state answers chooseMenu.  Both generations'
  -- screens do, and neither exposes a class marker a mod is allowed to read.
  function battle.find(game)
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

  -- Red's title-screen demo battle and Gold's DUDE catch tutorial both drive
  -- themselves from a canned input stream.  A hotkey that reached into either
  -- would hand its press to a battle the player is not holding.
  function battle.scripted(b)
    if not b then return false end
    return b.demo == true or b.tutorial == true
  end

  -- "menu" is the command menu in both engines.
  function battle.commandMenuOpen(b)
    return b ~= nil and b.phase == "menu" and not battle.scripted(b)
  end

  -- Red calls the move list moveSelect, and mimicSelect for the list Mimic
  -- borrows; Gold calls it moves.  The three names are disjoint, so matching
  -- all of them is exact on both generations without a branch.
  function battle.moveSelectOpen(b)
    if not b then return false end
    local phase = b.phase
    return phase == "moveSelect" or phase == "mimicSelect" or phase == "moves"
  end

  -- Red parks on a message by raising one of three booleans.  Gold stores
  -- MESSAGE_FRAMES in messageTimer and zeroes it when A or B is read; it is
  -- never counted down (engine/battle/core.asm's PromptButton pages on the
  -- button, with no frame countdown), so a positive value means "parked",
  -- not "still printing".
  function battle.textWaiting(b)
    if not b then return false end
    if b.msgWaiting == true or b.msgPrompt == true
        or b.waitingForInput == true then
      return true
    end
    return type(b.messageTimer) == "number" and b.messageTimer > 0
  end

  -- Red pushes the level-up stat box as its own state over the battle; Gold
  -- holds it as a phase on the battle screen itself.  Only the Gold half is
  -- answered here -- the Gen 1 half stays in battle_text.lua, where the
  -- pushed-state matcher already lives.
  function battle.statBoxPhase(b)
    return b ~= nil and b.phase == "stats-box"
  end

  -- Gold's whole learn-a-move flow is phases, where Red walks a chain of
  -- TextBoxes pushed over the battle.  learn-intro is the preamble, the other
  -- three are the forget prompt and its answer.
  local LEARN_PHASES = {
    ["learn-intro"] = true, ["ask-forget"] = true,
    ["choose-forget"] = true, ["stop-learning"] = true,
  }
  function battle.learningMove(b)
    return b ~= nil and LEARN_PHASES[b.phase] == true
  end

  -- The forget prompt is a decision, so it is never auto-advanced.
  function battle.learnChoiceOpen(b)
    if not b then return false end
    return b.phase == "ask-forget" or b.phase == "choose-forget"
      or b.phase == "stop-learning"
  end

  -- Throwing a ball.
  --
  -- Red exposes BattleState:throwBall and expects the caller to have spent the
  -- item and moved the state machine to its message phase first.  Gold has no
  -- throwBall at all: BattleState:useItem is the single entry point, and it
  -- owns the trainer-battle refusal, the full-box gate, the catch roll and
  -- spending the ball, so a caller that also spends it would charge twice.
  function battle.usesEngineItemPath(b)
    return b ~= nil and type(b.throwBall) ~= "function"
      and type(b.useItem) == "function"
  end

  function battle.throwBall(b, ballId)
    if not b then return false end
    if battle.usesEngineItemPath(b) then
      b:useItem(ballId)
      return true
    end
    if type(b.throwBall) ~= "function" then return false end
    b:throwBall(ballId)
    return true
  end

  -- Gold tags every ball with the BALL pocket, which is exact where a name
  -- list is not; Red has no pocket field, so the caller's own test stands.
  function battle.pocketIsBall(b, itemId)
    local data = b and b.game and b.game.data or (b and b.data)
    local def = data and data.items and data.items[itemId]
    return def ~= nil and def.pocket == "BALL"
  end

  -- Gold's Bug Contest runs off its own counter rather than the pack: a PARK
  -- BALL is never an inventory row, because PokeBallEffect's .used_park_ball
  -- decrements wParkBallsRemaining instead of tossing an item.  Listing the
  -- player's own balls there would offer throws the engine refuses, so the
  -- contest gets its counter read instead of the bag.
  --
  -- The require is reached only once b.contest is set, which no Gen 1 battle
  -- does, so a Gen 1 boot never asks for a Gen 2 module.
  function battle.contestBalls(b)
    if not b or not b.contest then return nil end
    local ok, BugContest = pcall(require, "src.core.gen2.BugContest")
    if not ok or type(BugContest) ~= "table" then return nil end
    local save = b.save or (b.game and b.game.save)
    local count = 0
    if type(BugContest.ballsLeft) == "function" then
      local got, left = pcall(BugContest.ballsLeft, save)
      if got and type(left) == "number" then count = left end
    end
    return { id = BugContest.BALL or "PARK_BALL", count = count }
  end

  -- Gold holds a line open while its own sound plays by parking the sfx name
  -- in waitSfx -- the `call WaitSFX` half of TextCommand_SOUND -- which is the
  -- same idea as Red's waitingSound under a different name.  Two of those are
  -- the level-up delay: the exp bar topping out and the "grew to level"
  -- fanfare.  The caught-mon jingle rides the same field and is deliberately
  -- left alone, because silencing a catch is not what this setting asks for.
  local GEN2_SKIPPABLE_SFX = {
    ["Sfx_HitEndOfExpBar"] = true, -- SFX_END_OF_EXP_BAR
    ["Sfx_DexFanfare5079"] = true, -- SFX_GREW_TO_LEVEL
  }
  function battle.clearLevelUpFanfare(b)
    if not b or type(b.waitSfx) ~= "string" then return false end
    if not GEN2_SKIPPABLE_SFX[b.waitSfx] then return false end
    local ok, Sound = pcall(require, "src.core.Sound")
    if ok and type(Sound) == "table" and type(Sound.stop) == "function" then
      pcall(Sound.stop, b.waitSfx)
    end
    b.waitSfx, b.waitSfxLeft = nil, nil
    return true
  end

  -- ---------------------------------------------------------- the battle roster
  --
  -- Red's battle screen *is* the battle: the fighter hangs off it directly and
  -- its move list is curMoves.  Gold's screen holds a battle model one level
  -- down (screen.battle.player), names the move list moves, and has no .data
  -- at all -- the ROM tables are reached through screen.game.data.  Every
  -- readiness check that reached for battle.player therefore returned false on
  -- Gold, which is why the command menu never opened.
  function battle.fighter(b)
    if type(b) ~= "table" then return nil end
    local direct = b.player
    if type(direct) == "table" then return direct end
    local model = b.battle
    if type(model) == "table" and type(model.player) == "table" then
      return model.player
    end
    return nil
  end

  function battle.moves(b)
    local fighter = battle.fighter(b)
    if not fighter then return nil end
    if type(fighter.curMoves) == "table" then return fighter.curMoves end
    if type(b.playerMoves) == "function" then
      local ok, moves = pcall(b.playerMoves, b)
      if ok and type(moves) == "table" then return moves end
    end
    if type(fighter.moves) == "table" then return fighter.moves end
    return nil
  end

  -- Sound.play wants the ROM data table, which Red hands off the battle and
  -- Gold off the game behind it.
  function battle.data(b)
    if type(b) ~= "table" then return nil end
    if b.data ~= nil then return b.data end
    return b.game and b.game.data
  end

  shared.battle = battle

  -- ----------------------------------------------------------------- the world
  --
  -- Gen 1 runs the overworld as the bottom stack state, so every context gate
  -- in the suite reads stack.states[1].  Gold runs it as a field on the game
  -- with an *empty* stack -- Game2:update steps the world only while
  -- stack:top() is nil (src/core/Game2.lua:2140).  Asking "where is the world"
  -- once, here, is what keeps those gates generation-blind; reading states[1]
  -- directly is why every overworld hotkey was silently dead on Gold.
  local world = {}

  -- Returns the world and which shape it was found in, so callers can keep
  -- Gen 1 on exactly the path it already had.
  function world.find(game)
    if type(game) ~= "table" then return nil end
    local states = game.stack and game.stack.states
    local base = states and states[1]
    if type(base) == "table"
        and (base.isOverworld or base == game.overworld or base.map ~= nil) then
      return base, "state"
    end
    -- Gold's World is recognised by the method the engine gates player action
    -- on.  Matching on a `map` field instead would also match the world object
    -- Red's Game holds during teardown, and quietly turn a shutting-down Gen 1
    -- boot into an "overworld" that hotkeys are allowed to fire in.
    local field = game.world
    if type(field) == "table" and type(field.busy) == "function" then
      return field, "field"
    end
    return nil
  end

  -- Gold's World:busy() (src/world/gen2/World.lua:1518-1530) is the engine's
  -- own "may the player act" answer: the script VM, the map-setup blocking
  -- call, text and choice boxes, field-move tails, fishing and headbutt.  It
  -- is both broader and more accurate than the flag list Red's base screen
  -- exposes, so on Gold we defer to it rather than re-deriving it.  The Gen 1
  -- arm is the original check, untouched, and is selected by shape rather
  -- than by game id.
  function world.busy(base, kind)
    if type(base) ~= "table" then return true end
    if kind == "field" then
      if type(base.busy) ~= "function" then return false end
      local ok, busy = pcall(base.busy, base)
      return (not ok) or (busy and true or false)
    end
    local runner = base.runner or base.scriptRunner
    if runner and runner.isRunning and runner:isRunning() then return true end
    local moves = base.scriptMoves
    local hasMoves = type(moves) == "table" and #moves > 0
    return (base.engaging or base.emote or base.teleportOut
      or base.transitioning or base.warping or hasMoves) and true or false
  end

  shared.world = world

  -- ------------------------------------------------------------ the start menu
  --
  -- Gen 1's rows carry the function that opens them.  Gold's are pure data --
  -- { id, label, need, desc } -- and it dispatches by id through
  -- Game2:openStartMenuItem (src/core/Game2.lua:449), which is the same entry
  -- point the compat layer synthesises a row's onChoose from.  Requiring a
  -- callable therefore dropped every Gold row on the floor, which emptied the
  -- menu hotkeys and the radial that is built from the same list.
  local menu = {}

  function menu.activator(game, item)
    local direct = item.onSelect or item.activate or item.action or item.select
    if type(direct) == "function" then return direct end
    local id = item.id
    if id == nil then return nil end
    if type(game) ~= "table" or type(game.openStartMenuItem) ~= "function" then
      return nil
    end
    -- Dispatch with the row's own id.  The suite folds pack onto item (and
    -- option onto options) so one saved binding survives the same install
    -- launching either generation, but the engine only knows its own name.
    return function(g)
      local target = type(g) == "table" and g.openStartMenuItem and g or game
      target:openStartMenuItem(id)
    end
  end

  -- Gold builds the player's name into the STATUS row when it lays the menu
  -- out, so the row itself carries label = nil.  Falling through to the id
  -- would label it "status" in the suite's own lists.
  function menu.label(game, item, index)
    local label = item.label or item.name
    if label ~= nil and tostring(label) ~= "" then return tostring(label) end
    if tostring(item.id or "") == "status" then
      local player = game and game.save and game.save.player
      local name = player and player.name
      if name ~= nil and tostring(name) ~= "" then return tostring(name) end
    end
    return tostring(item.id or ("ITEM " .. index))
  end

  shared.menu = menu
end
