-- The suite's configuration screens, drawn with Gen 3 chrome.
--
-- Gen 1 and Gen 2 reach the suite through `ui.options.rows`, which pushes a
-- screen onto `game.stack`.  Neither exists on Gen 3: `src/ui/game3` keeps its
-- own layer stack and its option list (`option_rows.lua`) raises no mod hook
-- at all, so there is nothing to insert a row into and nothing to push.
--
-- What Gen 3 does offer is `ui.start_menu.items` -- whose returned table
-- replaces `StartMenu.ENTRIES` outright -- and `StartMenu.confirm`, which
-- honours an entry's `onSelect` before any of its built-in cases.  That pair
-- is the entry point: START > HOTKEY SUITE.
--
-- The screen itself is a layer on `src.ui.game3.stack`, which hands a module
-- with draw/update/handleInput complete ownership of input while it is on
-- top.  Geometry, the dimming used for selection, the scroll arrows and the
-- help bar are copied from `src/ui/game3/option_menu.lua` so this looks like
-- a screen the game shipped rather than something bolted on.
--
-- The page *model* is the Gen 1 one, though, because behaviour is where
-- parity matters: the same INPUTS > CONTEXTS > CATEGORIES > SETTINGS tree,
-- read from the same tables in main.lua, with the same buttons doing the same
-- things on each kind of page.  Only the pixels are FireRed's.

return function(mod, suite)
  -- Gen 1/Gen 2 have their own screens; loading this there would add a
  -- duplicate Start Menu entry pointing at chrome that cannot draw.
  if tonumber(mod.generation) ~= 3 then return end

  local Strings = require("src.core.Strings")
  local shared = suite.shared

  local function tryRequire(name)
    local ok, module = pcall(require, name)
    if ok and type(module) == "table" then return module end
    return nil
  end

  local Stack = tryRequire("src.ui.game3.stack")
  local Window = tryRequire("src.ui.game3.window")
  local Chrome = tryRequire("src.ui.game3.chrome")
  local FrlgFont = tryRequire("src.ui.game3.frlg_font")

  -- A Gen 3 build without these is one this screen cannot draw on.  The rest
  -- of the suite -- every hotkey, every module -- is driven from the input
  -- hooks and keeps working; only configuration becomes unreachable, so warn
  -- rather than fail the load.
  if not (Stack and Window and Chrome and FrlgFont) then
    if mod.log then
      mod.log:warn("gen 3 UI unavailable (missing src.ui.game3 chrome); " ..
        "hotkeys still work but cannot be reconfigured in game")
    end
    return
  end

  local TILE = 8

  -- src/ui/game3/option_menu.lua -- kept identical so the suite's list sits at
  -- the same place on screen as the game's own OPTION list.
  local VISIBLE = 7
  local WIN_X, WIN_Y, WIN_W, WIN_H = 16, 56, 208, 96
  local ROW_Y0 = WIN_Y + 2
  local ROW_STEP = 13
  local ROW_H = 14
  local LABEL_X = WIN_X + 8
  local HELP_BG = { 0 / 255, 123 / 255, 197 / 255, 1 }

  -- The game's own options put the value column at WIN_X + 0x82 because its
  -- values are single words (ON/OFF/FAST).  A binding reads "LSHIFT+RETURN",
  -- so the split is moved left to give the value room; the label side still
  -- holds a module name comfortably.
  local VALUE_X = WIN_X + 0x6E
  local LABEL_W = VALUE_X - LABEL_X - 4
  local VALUE_W = (WIN_X + WIN_W - 8) - VALUE_X

  local DLG_X = Chrome.DLG_LEFT * TILE
  local DLG_Y = Chrome.DLG_TOP * TILE + 1
  local DLG_W = Chrome.DLG_W * TILE

  local UI = {}
  UI.open = false
  UI._pages = nil
  UI._mode = "browse"
  UI._arrowK = 0

  ---------------------------------------------------------------------------
  -- chrome helpers
  ---------------------------------------------------------------------------

  -- The player's chosen text frame, so the suite's windows match every other
  -- window in their game.
  local function frameType()
    local game = UI._game
    local engine = (game and (game.options or (game.save and game.save.options)))
      or (UI._session and UI._session.options) or {}
    local Options = tryRequire("src.core.game3.options")
    if Options and Options.block then
      local ok, block = pcall(Options.block, engine)
      if ok and type(block) == "table" then return tonumber(block.frameType) or 0 end
    end
    return 0
  end

  local function valueColors()
    return { fg = FrlgFont.STDPAL[5], shadow = FrlgFont.STDPAL[4], bg = FrlgFont.STDPAL[0] }
  end

  -- src/menu_indicators.c:289 -- the one-pixel bob the scroll arrows ride on.
  local function bob(k, freq)
    local Trig = tryRequire("src.core.game3.trig")
    if not (Trig and Trig.sin) then return 0 end
    local v = Trig.sin(((k or 0) * freq) % 256) * 2 / 256
    return v < 0 and math.ceil(v) or math.floor(v)
  end

  local function scrollArrow(dir, x, y)
    local BagChrome = tryRequire("src.ui.game3.bag_chrome")
    if BagChrome and BagChrome.drawArrow then
      local ok, drew = pcall(BagChrome.drawArrow, dir, x, y)
      if ok and drew then return end
    end
    FrlgFont.drawGlyph(dir == "up" and FrlgFont.CHAR_UP_ARROW or FrlgFont.CHAR_DOWN_ARROW,
      x + 4, y + 1, { colors = FrlgFont.COLOR.RED })
  end

  local function drawHelpBar(text)
    love.graphics.setColor(HELP_BG)
    love.graphics.rectangle("fill", 0, 0, 240, 16)
    love.graphics.setColor(1, 1, 1, 1)
    local PokedexChrome = tryRequire("src.ui.game3.pokedex_chrome")
    if PokedexChrome and PokedexChrome.drawControlInfo then
      pcall(PokedexChrome.drawControlInfo, text, 0xE4, 0)
    end
  end

  local function drawTitle(text)
    Chrome.fixedStdFrame(2, 3, 26, 2)
    Window.printPx(text, LABEL_X, 25, { colors = FrlgFont.COLOR.NORMAL })
  end

  local function clearScreen()
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", 0, 0, 240, 160)
    love.graphics.setColor(1, 1, 1, 1)
  end

  ---------------------------------------------------------------------------
  -- page model
  ---------------------------------------------------------------------------

  -- A page carries `back = true` when its last row is the virtual BACK entry.
  -- That mirrors Gen 1 exactly: its navigation lists (ListScreen) end in a
  -- BACK row, while its settings lists (SettingsScreen) do not and spend the
  -- space on the controls legend instead.  B backs out of both either way.
  local function page()
    local pages = UI._pages
    return pages and pages[#pages]
  end

  local function rowCount(p)
    return #p.rows + (p.back and 1 or 0)
  end

  local function clampScroll(p)
    local total = rowCount(p)
    if total <= VISIBLE then
      p.scroll = 0
      return
    end
    if p.index - 1 < p.scroll then p.scroll = p.index - 1 end
    if p.index > p.scroll + VISIBLE then p.scroll = p.index - VISIBLE end
    if p.scroll < 0 then p.scroll = 0 end
    if p.scroll > total - VISIBLE then p.scroll = total - VISIBLE end
  end

  local NAV_LEGEND = Strings("{DPAD_UPDOWN}PICK {A_BUTTON}OK {B_BUTTON}BACK")
  local SET_LEGEND = Strings("{START_BUTTON}HELP {B_BUTTON}BACK")
  local BIND_LEGEND = Strings("{SELECT_BUTTON}CLEAR {START_BUTTON}HELP {B_BUTTON}BACK")

  local function pushPage(title, rows, opts)
    opts = opts or {}
    UI._pages[#UI._pages + 1] = {
      title = title, rows = rows, index = 1, scroll = 0,
      back = opts.back, legend = opts.legend or NAV_LEGEND,
    }
  end

  -- A row is a hotkey binding when it can both be captured and be cleared;
  -- that is what decides whether SELECT means anything on this page.  Same
  -- test as main.lua's `hasBindings`.
  local function hasBindings(rows)
    for _, row in ipairs(rows or {}) do
      if type(row.activate) == "function" and type(row.unassign) == "function" then
        return true
      end
    end
    return false
  end

  local function openSettings(game, inputId, feature)
    local ok, rows = pcall(feature.rows, game, inputId)
    if not ok then
      -- A module whose rows cannot be built on this engine gets an empty
      -- page rather than taking the whole screen down with it.
      if mod.log then
        mod.log:warn("could not build %s rows: %s", tostring(feature.id), tostring(rows))
      end
      rows = {}
    elseif type(rows) ~= "table" then
      rows = {}
    end
    pushPage(Strings(feature.label), rows, {
      back = false,
      legend = hasBindings(rows) and BIND_LEGEND or SET_LEGEND,
    })
  end

  local function openCategories(game, inputId, contextId, contextLabel)
    local rows = {}
    for _, feature in ipairs(suite.featuresFor(inputId, contextId)) do
      local current = feature
      rows[#rows + 1] = {
        id = "hotkeySuite." .. inputId .. "." .. current.id,
        label = Strings(current.label),
        activate = function(g) openSettings(g, inputId, current) end,
      }
    end
    pushPage(Strings(contextLabel), rows, { back = true })
  end

  -- OVERWORLD / BATTLE / GENERAL.  A context with no modules registered for
  -- this input type is left out rather than opening an empty list.
  local function openContexts(game, inputId, inputLabel)
    local rows = {}
    for _, context in ipairs(suite.contexts) do
      local current = context
      if #suite.featuresFor(inputId, current.id) > 0 then
        rows[#rows + 1] = {
          id = "hotkeySuite." .. inputId .. "." .. current.id,
          label = Strings(current.label),
          activate = function(g) openCategories(g, inputId, current.id, current.label) end,
        }
      end
    end
    pushPage(Strings(inputLabel), rows, { back = true })
  end

  local function buildTop()
    local rows = {}
    for _, input in ipairs(suite.inputs) do
      local current = input
      rows[#rows + 1] = {
        id = "hotkeySuite." .. current.id,
        label = Strings(current.label),
        activate = function(g) openContexts(g, current.id, current.label) end,
      }
    end
    rows[#rows + 1] = {
      id = "hotkeySuite.unassignAll",
      label = Strings("UNASSIGN ALL"),
      activate = function()
        UI._mode = "confirm"
        UI._confirmYes = false -- default NO, as Gen 1's prompt does
      end,
    }
    return rows
  end

  ---------------------------------------------------------------------------
  -- lifecycle
  ---------------------------------------------------------------------------

  function UI.isOpen()
    return UI.open == true
  end

  function UI.show(game, session)
    if UI.open then return end
    local Runtime = package.loaded["src.core.game3.runtime"]
    UI._game = game or (Runtime and Runtime._game)
    UI._session = session
    UI._pages = {}
    UI._mode = "browse"
    UI._arrowK = 0
    pushPage(Strings("HOTKEY SUITE"), buildTop(), { back = true })
    UI.open = true
    Stack.push("hotkey_suite", UI, { hideBelow = true, fullscreen = true })
  end

  function UI.close()
    if not UI.open then return end
    UI.open = false
    UI._pages = nil
    UI._mode = "browse"
    Stack.pop("hotkey_suite")
  end

  function UI.back()
    local pages = UI._pages
    if pages and #pages > 1 then
      pages[#pages] = nil
      return
    end
    UI.close()
  end

  ---------------------------------------------------------------------------
  -- combo capture
  ---------------------------------------------------------------------------
  --
  -- shared.lua owns the capture state machine; it reads the raw key/gamepad
  -- streams straight from the input hooks so that modifiers and buttons the
  -- engine does not map can still be bound.  All this layer does is switch to
  -- a prompt and stay out of the way: while `capture` is live the hooks
  -- swallow every event before the engine records it, so `wasPressed` never
  -- goes true here anyway.

  function UI.openCapture(_game, title, _spec)
    if not UI.open then return end
    UI._captureTitle = title
    UI._mode = "capture"
  end

  function UI.captureOpen()
    return UI._mode == "capture"
  end

  function UI.closeCapture()
    if UI._mode == "capture" then UI._mode = "browse" end
  end

  shared.registerUi(UI)

  ---------------------------------------------------------------------------
  -- help text
  ---------------------------------------------------------------------------

  -- The dialogue frame holds two lines, and a help string wraps to more than
  -- that, so it is regrouped into explicit two-line pages that each hold for
  -- A.  Gen 1 does the same thing for the same reason (main.lua's
  -- `paginateHelp`), just against its own box and its own paginator.
  local function helpPages(text)
    local ok, wrapped = pcall(FrlgFont.wrap, tostring(text or ""), DLG_W - 16, {})
    if not ok or type(wrapped) ~= "string" then wrapped = tostring(text or "") end
    local lines = {}
    for line in (wrapped .. "\n"):gmatch("(.-)\r?\n") do
      line = line:gsub("%s+$", "")
      if line ~= "" then lines[#lines + 1] = line end
    end
    local pages = {}
    for i = 1, #lines, 2 do
      pages[#pages + 1] = table.concat(lines, "\n", i, math.min(i + 1, #lines))
    end
    if #pages == 0 then pages[1] = tostring(text or "") end
    return pages
  end

  local function openHelp(text)
    UI._help = helpPages(text)
    UI._helpPage = 1
    UI._mode = "help"
  end

  ---------------------------------------------------------------------------
  -- input
  ---------------------------------------------------------------------------

  local function browseInput(input)
    local p = page()
    if not p then
      UI.close()
      return
    end
    local total = rowCount(p)
    local game = UI._game
    local row = (p.index <= #p.rows) and p.rows[p.index] or nil
    local onBack = p.back and p.index > #p.rows

    if total > 0 and input:wasPressed("up") then
      p.index = ((p.index - 2) % total) + 1
    elseif total > 0 and input:wasPressed("down") then
      p.index = (p.index % total) + 1
    elseif input:wasPressed("start") then
      -- Gen 1: START shows help on a settings screen and backs out of a
      -- navigation list.  Reproduced rather than simplified, because muscle
      -- memory is exactly the thing parity is for.
      if row and row.help then
        openHelp(row.help)
      elseif p.back then
        UI.back()
      end
    elseif input:wasPressed("select") then
      if row and row.unassign then pcall(row.unassign, game) end
    elseif input:wasPressed("a") then
      if onBack then
        UI.back()
      elseif row and row.activate then
        pcall(row.activate, game)
      elseif row and row.step then
        pcall(row.step, game, 1)
      end
    elseif input:wasPressed("left") or input:wasPressed("right") then
      local dir = input:wasPressed("left") and -1 or 1
      if row and row.step then pcall(row.step, game, dir) end
    elseif input:wasPressed("b") then
      UI.back()
    end
    clampScroll(p)
  end

  local function helpInput(input)
    if input:wasPressed("a") then
      local pages = UI._help or {}
      if UI._helpPage < #pages then
        UI._helpPage = UI._helpPage + 1
      else
        UI._mode = "browse"
      end
    elseif input:wasPressed("b") or input:wasPressed("start") then
      UI._mode = "browse"
    end
  end

  local function confirmInput(input)
    if input:wasPressed("up") or input:wasPressed("down") then
      UI._confirmYes = not UI._confirmYes
    elseif input:wasPressed("a") then
      if UI._confirmYes then shared.clearAllBindings() end
      UI._mode = "browse"
    elseif input:wasPressed("b") then
      UI._mode = "browse"
    end
  end

  function UI.handleInput(input)
    if not (UI.open and input) then return end
    -- shared.lua is consuming the raw stream; nothing reaches the engine's
    -- input state to react to, and reacting would steal the combo anyway.
    if UI._mode == "capture" then return end
    if UI._mode == "help" then return helpInput(input) end
    if UI._mode == "confirm" then return confirmInput(input) end
    return browseInput(input)
  end

  function UI.update()
    if not UI.open then return end
    UI._arrowK = (UI._arrowK or 0) + 1
    -- The capture can end from inside the input hooks (combo assigned, or
    -- ESC) without coming back through this layer.  If shared.lua has let go
    -- of the state, so does the prompt.
    if UI._mode == "capture" and shared.captureState() == nil then
      UI._mode = "browse"
    end
  end

  ---------------------------------------------------------------------------
  -- draw
  ---------------------------------------------------------------------------

  local function drawList(p)
    Window.userFrame(Window.template(2, 7, 26, 12), frameType())

    local total = rowCount(p)
    clampScroll(p)
    local vcol = valueColors()
    for slot = 1, VISIBLE do
      local idx = p.scroll + slot
      if idx <= total then
        local y = ROW_Y0 + (slot - 1) * ROW_STEP
        if idx > #p.rows then
          Window.printPx(Strings("BACK"), LABEL_X, y, { colors = FrlgFont.COLOR.NORMAL })
        else
          local row = p.rows[idx]
          Window.printPx(row.label or "?", LABEL_X, y,
            { colors = FrlgFont.COLOR.NORMAL, maxWidth = LABEL_W })
          if row.value then
            local ok, text = pcall(row.value, UI._game)
            Window.printPx(ok and tostring(text) or "----", VALUE_X, y,
              { colors = vcol, maxWidth = VALUE_W })
          end
        end
      end
    end

    -- Selection is the game's own: everything *except* the current row is
    -- dimmed, rather than a cursor being drawn beside it.  src/option_menu.c:572
    if total > 0 then
      local selTop = ROW_Y0 + (p.index - p.scroll - 1) * ROW_STEP
      local selBot = selTop + ROW_H
      love.graphics.setColor(0, 0, 0, 2 / 16)
      if selTop > WIN_Y then
        love.graphics.rectangle("fill", WIN_X, WIN_Y, WIN_W, selTop - WIN_Y)
      end
      if selBot < WIN_Y + WIN_H then
        love.graphics.rectangle("fill", WIN_X, selBot, WIN_W, WIN_Y + WIN_H - selBot)
      end
      love.graphics.setColor(1, 1, 1, 1)
    end

    if total > VISIBLE then
      local k = UI._arrowK or 0
      if p.scroll > 0 then
        scrollArrow("up", 208, WIN_Y + bob(k, 8))
      end
      if p.scroll + VISIBLE < total then
        scrollArrow("down", 208, WIN_Y + WIN_H - 16 + bob(k, -8))
      end
    end
  end

  local function drawCapture()
    local capture = shared.captureState()
    clearScreen()
    -- Deliberately not a button prompt: every gamepad button is bindable and
    -- gets swallowed into the combination, so B does *not* cancel here.  ESC
    -- is the escape hatch on both input types, as it is on Gen 1.
    drawHelpBar(Strings("ESC CANCELS"))
    drawTitle(UI._captureTitle or Strings("HOTKEY SUITE"))
    Window.userFrame(Window.template(2, 7, 26, 12), frameType())

    local y = ROW_Y0 + 4
    Window.printPx(Strings("HOLD A COMBINATION"), LABEL_X, y,
      { colors = FrlgFont.COLOR.NORMAL })
    Window.printPx(Strings("RELEASE TO ASSIGN"), LABEL_X, y + ROW_STEP,
      { colors = FrlgFont.COLOR.NORMAL })
    Window.printPx(shared.describe(capture and capture.pending or {}),
      LABEL_X, y + ROW_STEP * 3, { colors = valueColors(), maxWidth = WIN_W - 24 })
    Window.printPx((capture and capture.message) or Strings("ESC CANCELS"),
      LABEL_X, y + ROW_STEP * 5, { colors = FrlgFont.COLOR.RED })
  end

  local function drawHelp()
    local pages = UI._help or {}
    Chrome.dialogueFrame()
    FrlgFont.draw(pages[UI._helpPage or 1] or "", DLG_X, DLG_Y, {
      maxWidth = DLG_W,
      colors = FrlgFont.COLOR.NORMAL,
    })
  end

  local function drawConfirm()
    Chrome.dialogueFrame()
    FrlgFont.draw(Strings("Unassign all\nsuite hotkeys?"), DLG_X, DLG_Y, {
      maxWidth = DLG_W,
      colors = FrlgFont.COLOR.NORMAL,
    })
    Window.userFrame(Window.template(24, 8, 5, 5), frameType())
    local yesY, noY = 8 * TILE + 6, 8 * TILE + 6 + 15
    Window.printPx(Strings("YES"), 24 * TILE + 10, yesY, { colors = FrlgFont.COLOR.NORMAL })
    Window.printPx(Strings("NO"), 24 * TILE + 10, noY, { colors = FrlgFont.COLOR.NORMAL })
    Window.cursorPx(24 * TILE + 2, UI._confirmYes and yesY or noY)
  end

  function UI.draw()
    if not UI.open then return end
    if UI._mode == "capture" then return drawCapture() end

    local p = page()
    if not p then return end
    clearScreen()
    drawHelpBar(p.legend or NAV_LEGEND)
    drawTitle(p.title or Strings("HOTKEY SUITE"))
    drawList(p)

    if UI._mode == "help" then drawHelp() end
    if UI._mode == "confirm" then drawConfirm() end
  end

  ---------------------------------------------------------------------------
  -- entry point
  ---------------------------------------------------------------------------

  -- `mod.ui.insertBefore` anchors on a row's *label*, which on Gen 3 is
  -- already localised ROM text; matching it would break the moment the
  -- player's language changed.  The ids are stable, so anchor on those.
  local function insertBeforeId(items, anchorId, entry)
    for index, item in ipairs(items) do
      if type(item) == "table" and item.id == anchorId then
        table.insert(items, index, entry)
        return items
      end
    end
    items[#items + 1] = entry
    return items
  end

  mod.hooks:wrap("ui.start_menu.items", function(next, game, items)
    local out = next(game, items)
    if type(out) ~= "table" then return out end
    for _, item in ipairs(out) do
      if type(item) == "table" and item.id == "hotkeySuite" then return out end
    end
    return insertBeforeId(out, "exit", {
      id = "hotkeySuite",
      -- FireRed sizes the start menu's window to its widest stock label
      -- (POKEDEX / POKEMON), and "HOTKEY SUITE" runs past it. The screen
      -- behind the row still calls itself HOTKEY SUITE; only the row that
      -- has to fit inside that box is shortened.
      label = Strings("HOTKEYS"),
      -- StartMenu.confirm honours onSelect before any of its built-in cases,
      -- so this is all that is needed to own the entry.
      onSelect = function(g, session) UI.show(g, session) end,
    })
  end)

  suite.gen3Ui = UI
end
