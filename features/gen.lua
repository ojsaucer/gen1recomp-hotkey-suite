-- Generation adapter.
--
-- Gold is a second engine beside Red rather than a skin over it: a Gen 2 boot
-- runs src/ui/gen2/BattleState.lua, which keeps its own phase vocabulary and
-- its own message plumbing.  FireRed is a third, further out still: it has no
-- state stack, no world on the game object, its own 240x160 chrome, and it
-- reaches mods through src/mods/Gen3Compat.lua.  Every read and write the
-- feature modules make goes through this file so each difference is stated
-- once.
--
-- Each helper probes for the capability it needs instead of asking which game
-- is running.  A version allow-list would drop the suite out of Gold by
-- construction -- the adapters would resolve, the patches would land, and the
-- features would still never appear -- which is the failure the engine's own
-- porting guide calls the most confusing possible outcome.  The one place a
-- generation is named is shared.chromeAvailable, and that is about which font
-- and frame size to draw, not about what the suite is allowed to do.
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

  -- Red wraps the party mon in .mon and reads hp off that; Gold's fighter
  -- carries its own hp (src/battle/gen2/Battle.lua:671 reads self.player.hp).
  -- This is the single read that let Gold's move menu work while the command
  -- menu and the ball menu stayed dead: they are the two that gate on HP.
  function battle.fighterHp(b)
    local fighter = battle.fighter(b)
    if not fighter then return nil end
    local mon = fighter.mon
    if type(mon) == "table" then return tonumber(mon.hp) end
    return tonumber(fighter.hp)
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

  -- -------------------------------------------------------- the legend anchors
  --
  -- The control legend is painted into the battle's own native tile grid, so
  -- it has to land on the engine's own cursor cells.  Both engines put the
  -- command cursor in a two-column, two-row grid one tile left of each label,
  -- and both step the rows by 16px -- which is why only the COLUMNS were ever
  -- wrong on Gold, and why the arrows sat on the right lines but the wrong
  -- letters.  Gold's cells are src/ui/gen2/BattleState.lua:199-206
  -- (MENU_BOX_X 8 / MENU_COL_SPACING 6, and 2 / 12 for a contest) with the
  -- cursor at boxX + 1 (:4516-4518), shifted right by the wide layout's
  -- src/ui/gen2/WideBattle.lua:11 EXTRA_TILES gutter.
  local GOLD_WIDE_TILES = 18

  -- Shape probe, not a game id -- the same one battle.fighter turns on.
  local function goldBattle(b)
    return type(b) == "table" and type(b.player) ~= "table"
      and type(b.battle) == "table" and type(b.battle.player) == "table"
  end

  function battle.wideLayout(b)
    if type(b) ~= "table" or type(b.wideLayout) ~= "function" then
      return false
    end
    local ok, wide = pcall(b.wideLayout, b)
    return (ok and wide) and true or false
  end

  function battle.commandArrowXs(b, wide)
    if goldBattle(b) then
      local box, step = 8, 6
      if b.contest then box, step = 2, 12 end
      local first = box + 1 + (wide and GOLD_WIDE_TILES or 0)
      return { first * 8, (first + step) * 8 }
    end
    if wide then
      return b.safari and { 8, 160 } or { 168, 232 }
    end
    return b.safari and { 8, 104 } or { 72, 120 }
  end

  -- Red reflows its move list into two columns for the wide layout.  Gold does
  -- not: the wide gutter only widens the list box (BattleState.lua:4504) while
  -- the names keep hlcoord 6 and the cursor hlcoord 5 on rows 13..16
  -- (:4534-4539) -- exactly where Red puts them when it is narrow.  nil means
  -- "a single column", which the caller draws down the gutter at x 40.
  function battle.moveArrowXs(b, wide)
    if not wide or goldBattle(b) then return nil end
    return { 8, 112 }
  end

  -- ------------------------------------------------------------- Gen 3 battle
  --
  -- FireRed's battle is not a pushed state a mod can find on `game.stack` --
  -- there is no `game.stack` at all -- it is a pair of engine singletons:
  -- `src/core/game3/battle` (Battle) owns whether one is running at all, and
  -- `src/core/game3/battle/ui` (Ui) owns the command/move cursor and reads
  -- input.  Ui's own cursor fields (`_mode`, `_menuIndex`, `_moveIndex`) are
  -- plain table fields with no accessor, same as every other Gen 3 reach this
  -- suite already makes (Field.locked, Player.moving); they are read and
  -- written directly rather than reinvented behind a facade, because the
  -- shapes above (a `.phase` string, `:chooseMenu(action)`) describe an
  -- object FireRed does not have, and forcing one into existence would be a
  -- second, drifting copy of Ui's own state machine.
  --
  -- `Ui.handleInput(input)` -- the same entry point a real d-pad/A press
  -- reaches -- already knows how to open the move list, refuse RUN, show the
  -- PP-empty error and so on, so a direct-select hotkey is built the same way
  -- Gen 1/2's `battle.menuIndex = command.index` line is: point the cursor at
  -- the wanted row first, then hand Ui one synthetic A press and let its own
  -- logic decide what that selection does.  Nothing about move/command
  -- resolution is reimplemented here.
  local gen3battle = {}
  battle.gen3 = gen3battle

  local function optionalG3(name)
    local ok, found = pcall(require, name)
    if ok and type(found) == "table" then return found end
    return nil
  end

  local G3Battle = optionalG3("src.core.game3.battle")
  local G3Ui = optionalG3("src.core.game3.battle.ui")
  gen3battle.available = G3Battle ~= nil and G3Ui ~= nil
    and type(G3Battle.isActive) == "function"
    and type(G3Ui.handleInput) == "function"

  -- Good for exactly one Ui.handleInput call: input:wasPressed(name) is the
  -- entire interface Ui ever calls on it.
  local function onePress(name)
    return { wasPressed = function(_, pressedName) return pressedName == name end }
  end

  function gen3battle.active()
    return gen3battle.available and G3Battle.isActive() == true
  end

  -- The Old Man's Viridian tutorial battle drives its own actions from a
  -- script, same reason Red's demo battle and Gold's DUDE catch tutorial are
  -- excluded in battle.scripted above; Ui.handleInput itself refuses input
  -- during it, but the check is repeated here so commandMenuOpen answers
  -- honestly rather than reporting a menu that no press could ever reach.
  local function gen3Scripted()
    return G3Ui._st and G3Ui._st.oldManTutorial == true
  end

  function gen3battle.commandMenuOpen()
    return gen3battle.active() and G3Ui._mode == "menu" and not gen3Scripted()
  end

  function gen3battle.moveSelectOpen()
    return gen3battle.active() and G3Ui._mode == "moves" and not gen3Scripted()
  end

  -- FIGHT/BAG/POKEMON/RUN in a normal battle, BALL/BAIT/ROCK/RUN in a Safari
  -- one -- both are four rows in the same physical grid, and RUN is always
  -- the fourth, which is all a direct-select hotkey needs to know.
  function gen3battle.submitCommand(index)
    if not gen3battle.commandMenuOpen() then return false end
    G3Ui._menuIndex = index
    G3Ui.handleInput(onePress("a"))
    return true
  end

  -- The live battler's move list, so callers can check a slot is actually
  -- there before spending a press on it -- exactly the
  -- `moves[command.index]` guard the Gen 1/2 path already makes.
  function gen3battle.moves()
    if not gen3battle.active() then return nil end
    local mon = G3Ui._st and G3Ui._st.player and G3Ui._st.player.mon
    return mon and mon.moves
  end

  function gen3battle.submitMove(index)
    if not gen3battle.moveSelectOpen() then return false end
    local moves = gen3battle.moves()
    local mv = moves and moves[index]
    if not mv or mv == 0 or mv == "" then return false end
    G3Ui._moveIndex = index
    G3Ui.handleInput(onePress("a"))
    return true
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
    -- FireRed puts nothing world-shaped on the game at all: Game3.new sets
    -- only self.input (src/core/Game3.lua:115), and the hooks hand mods the
    -- raw Game3 rather than the Gen3Compat facade, so there is neither a
    -- stack to read states[1] from nor a .world to ask busy() of.  The field
    -- is reached only through the mod API, whose :overworld() already answers
    -- nil unless Game3.phase is "field" (src/world/game3/WorldAPI.lua:57) --
    -- the same question the two arms above ask of their own engines.  The API
    -- object is returned as the handle because on FireRed the API *is* the
    -- world handle; the controller behind it is fetched per call.
    local api = mod.world
    if type(api) == "table" and type(api.overworld) == "function"
        and type(api.availableFieldActions) == "function"
        and api:overworld() then
      return api, "api"
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
    if kind == "api" then
      -- FireRed's own "may the player act" answer is Gen3Compat.worldBusy:
      -- the field lock, the script VM, an active battle, a mid-warp fade and
      -- a player mid-step.  It is not a mod-facing name, but every public
      -- entry point that respects it reports it the same way -- a second
      -- return of why -- so availableFieldActions is asked instead of
      -- reaching into src/mods.  It is the same gate useFieldAction applies
      -- a moment later (src/world/game3/WorldAPI.lua:214,242), so a hotkey
      -- that passes here is one the engine would have accepted anyway.
      if type(base.availableFieldActions) ~= "function" then return false end
      local ok, _, why = pcall(base.availableFieldActions, base)
      if not ok then return true end
      return why ~= nil
    end
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

  -- Whether the overworld itself owns the frame, which is what a travel hotkey
  -- needs before it may warp the player.  Red stacks the overworld as the one
  -- and only state; Gold runs it as a field and updates it only while the
  -- state stack is EMPTY (src/core/Game2.lua:2140).  Asking Red's question on
  -- Gold -- "is there exactly one state?" -- is never true there, which is
  -- what silently disabled every travel hotkey on Gold, FLY included.
  function world.ownsFrame(game)
    local base, kind = world.find(game)
    if not base then return false end
    -- FireRed's modal layers live on src/ui/game3/stack.lua, which the game
    -- object does not expose -- but it does not need to be read separately:
    -- Hud.busy() folds "a menu is open" in with the rest (hud.lua:45-52), and
    -- that is what worldBusy reports through uiBusy.  So on FireRed "the
    -- overworld owns the frame" and "the world is not busy" are the same
    -- answer, already computed above.
    if kind == "api" then return not world.busy(base, kind) end
    local stack = game and game.stack
    if type(stack) ~= "table" or type(stack.top) ~= "function" then
      return false
    end
    if kind == "field" then return stack:top() == nil end
    local states = stack.states
    return type(states) == "table" and #states == 1
      and stack:top() == states[1]
  end

  -- --------------------------------------------------------------------- FLY
  --
  -- Red puts FLY on the mod API itself: canFly reports eligibility and flyTo
  -- takes a destination, leaving the picker for the caller to push
  -- (docs/modding.md:377-380).  Gold exposes neither -- but that is an
  -- omission rather than a refusal.  Fly is simply absent from the
  -- FIELD_ACTIONS table Gold's own WorldAPI:useFieldAction walks, while the
  -- pipeline that table feeds, World:useFieldMove, handles "FLY" like any
  -- other field move.  Going in that way keeps every one of the engine's own
  -- gates: the STORM badge, the outdoors-only check that counts a POKEMON
  -- CENTER as indoors, the refusal lines, the native fly map and the bird
  -- animation.  Nothing about fly is reimplemented here, so nothing here can
  -- drift out of step with the cart.
  function world.flyMode(api, ow)
    -- FireRed carries both API names and refuses anyway: canFly answers
    -- honestly but flyTo warns and returns nil, "unsupported", because its
    -- destinations are the region map's town spawn points, which have no
    -- seam (src/world/game3/WorldAPI.lua:290-296).  The picker arm is really
    -- two capabilities -- the API opens the map, the overworld performs the
    -- warp -- so both halves are probed.  FireRed's overworld facade lists
    -- flyTo as absent, which is what separates it from Red here.
    if type(api) == "table" and type(api.canFly) == "function"
        and type(api.flyTo) == "function"
        and type(ow) == "table" and type(ow.flyTo) == "function" then
      return "picker"
    end
    if type(ow) == "table" and type(ow.useFieldMove) == "function"
        and type(ow.partyMoveUser) == "function" then
      return "fieldmove"
    end
    return nil
  end

  -- ------------------------------------------------------- RETURN CENTER
  --
  -- Red hands the whole trip to World:beginTeleportOut, gated by the
  -- save's lastHeal.  Gold has neither name.  It keeps the same two halves
  -- apart instead: healPoint resolves where the player would wake up --
  -- reading the blackout override ahead of the spawn table, so the Fast Ship
  -- and Mr. POKEMON's house resolve the way the cart does -- and warpToSpawn
  -- is the trip itself.  healPoint is therefore Gold's lastHeal: nil until
  -- somewhere has been healed at, which is exactly the question the hotkey
  -- needs to ask before it refuses.
  function world.centerMode(ow)
    if type(ow) ~= "table" then return nil end
    if type(ow.beginTeleportOut) == "function" then return "teleportOut" end
    if type(ow.healPoint) == "function"
        and type(ow.warpToSpawn) == "function" then
      return "spawn"
    end
    -- FireRed splits the trip the same way Gold does but names the second
    -- half after the first: healPoint resolves where the player would wake
    -- up and warpToHealPoint is the trip.  Both are backed on the Gen 3
    -- overworld facade, so RETURN CENTER needs nothing FireRed does not
    -- already do for a blackout.
    if type(ow.healPoint) == "function"
        and type(ow.warpToHealPoint) == "function" then
      return "healPoint"
    end
    return nil
  end

  shared.world = world

  -- ------------------------------------------------------------ the start menu
  --
  -- Gen 1's rows carry the function that opens them.  Gold's are pure data,
  -- and not the ITEMS entries either: visibleItems() builds a fresh row per
  -- visible item (src/ui/gen2/StartMenu.lua:197-230), so the id arrives as
  -- `value` and there is no `id` field at all.  Requiring a callable dropped
  -- every Gold row, which emptied the menu hotkeys and the radial built from
  -- the same list.  Dispatch goes through Game2:openStartMenuItem
  -- (src/core/Game2.lua:449), the same entry point Gold's own menu reaches
  -- through onChoose.
  local menu = {}

  -- QUIT and the Bug Contest's QUIT never reach onChoose: StartMenu:choose
  -- handles them itself by raising a confirmation first (StartMenu.lua:256-268).
  -- Dispatching them directly would skip that prompt, and for QUIT that means
  -- throwing away everything since the last save on a single keypress.
  local MENU_NOT_DISPATCHABLE = { quit = true, quitContest = true, exit = true }

  function menu.dispatchId(item)
    if type(item) ~= "table" then return nil end
    local id = item.value
    if id == nil then id = item.id end
    if id == nil then return nil end
    id = tostring(id)
    if MENU_NOT_DISPATCHABLE[id] then return nil end
    return id
  end

  function menu.activator(game, item)
    local direct = item.onSelect or item.activate or item.action or item.select
    if type(direct) == "function" then return direct end
    local id = menu.dispatchId(item)
    if id == nil then return nil end
    if type(game) == "table" and type(game.openStartMenuItem) == "function" then
      -- Dispatch with the row's own id.  The suite folds pack onto item (and
      -- option onto options) so one saved binding survives the same install
      -- launching either generation, but the engine only knows its own name.
      return function(g)
        local target = type(g) == "table" and g.openStartMenuItem and g or game
        target:openStartMenuItem(id)
      end
    end
    -- FireRed's rows are pure data like Gold's, but there is no
    -- openStartMenuItem to hand the id to: Game3 has no such method, and a
    -- FireRed row carries no onSelect to rewire either.  What it does have is
    -- StartMenu.confirm(), the engine's own dispatcher, and it reads nothing
    -- but StartMenu.cursor (src/ui/game3/start_menu.lua:212-215).  Pointing
    -- the cursor at the row and confirming is the same path the player's own
    -- A press takes, so the flag gates that built the list, the menu sound,
    -- and the follow-up prompts SAVE and RETIRE raise all still run.  The row
    -- is looked up by id at fire time rather than captured by index, because
    -- show() rebuilds ENTRIES on every open and a gated row may have appeared
    -- or gone since the list was cached.
    local ok, StartMenu = pcall(require, "src.ui.StartMenu")
    if ok and type(StartMenu) == "table"
        and type(StartMenu.confirm) == "function"
        and type(StartMenu.ENTRIES) == "table" then
      return function()
        local entries = StartMenu.ENTRIES
        if type(entries) ~= "table" then return end
        for index = 1, #entries do
          local entry = entries[index]
          if type(entry) == "table" and tostring(entry.id) == id then
            StartMenu.cursor = index
            StartMenu.confirm()
            return
          end
        end
      end
    end
    return nil
  end

  -- Gold has already substituted the player's name into the STATUS row and
  -- applied every `need` gate before the hook is raised, so a row that gets
  -- this far is one the player may use, labelled the way Gold labels it.
  function menu.label(game, item, index)
    local label = item.label or item.name
    if label ~= nil and tostring(label) ~= "" then return tostring(label) end
    return tostring(menu.dispatchId(item) or item.id or ("ITEM " .. index))
  end

  shared.menu = menu
end
