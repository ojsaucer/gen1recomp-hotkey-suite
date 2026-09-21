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

  shared.battle = battle
end
