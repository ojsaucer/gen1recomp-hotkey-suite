return function(mod, suite)
  local shared = suite.shared
  local specs = { keyboard = {}, gamepad = {} }
  local isGen3 = tonumber(mod.generation) == 3

  local function bindings()
    local value = shared.store.get("menu_hotkeys", nil)
    if type(value) ~= "table" then value = {} end
    if value.enabled == nil then value.enabled = false end
    -- Ships on so a fresh Gen 3 install matches Red and Gold's behaviour
    -- without a trip to the settings screen; see isQuickExit()'s comment.
    if value.quickExit == nil then value.quickExit = true end
    value.keyboard = type(value.keyboard) == "table" and value.keyboard or {}
    value.gamepad = type(value.gamepad) == "table" and value.gamepad or {}
    return value
  end

  local function isEnabled() return bindings().enabled == true end

  local function setEnabled(value)
    local all = bindings()
    all.enabled = value and true or false
    shared.store.set("menu_hotkeys", all)
  end

  local function isQuickExit() return bindings().quickExit == true end

  local function setQuickExit(value)
    local all = bindings()
    all.quickExit = value and true or false
    shared.store.set("menu_hotkeys", all)
  end

  -- ------------------------------------------------------------- quick exit
  --
  -- On Red and Gold, activateMenuItem's closeMenus() unwinds the whole stack
  -- before the chosen screen is pushed, so a menu hotkey never puts the START
  -- menu on screen at all -- CANCEL already lands back in the overworld in
  -- one press. FireRed cannot dispatch that way: src/ui/game3/start_menu
  -- .lua's confirm() is the only entry point in, whether reached directly or
  -- through a row's own onSelect, and both require the START menu to already
  -- be open (Gen3Compat backs it with Hud.openStartMenu). Canceling out of,
  -- say, BAG therefore returns to a START menu the player never opened, and
  -- needs a second CANCEL to reach the overworld -- the one behaviour gap
  -- Gen 3 still had. This closes it: once whatever the hotkey opened has been
  -- backed out of and the START menu is the only thing left on FireRed's own
  -- UI stack, it is closed automatically too.
  --
  -- The watch only starts once the opened screen has actually shown (its own
  -- id has been seen on top), so a dispatch that never manages to push
  -- anything can't mistake the START menu still sitting there for "backed
  -- all the way out" and close it before the player has seen anything.
  local pending, sawOpened = false, false

  local function armQuickExit()
    pending, sawOpened = true, false
  end

  if isGen3 then
    mod.hooks:wrap("input.step", function(next, game, dt)
      next(game, dt)
      if not pending then return end
      local ok, Stack = pcall(require, "src.ui.game3.stack")
      if not ok or type(Stack) ~= "table" or type(Stack.top) ~= "function" then
        pending = false
        return
      end
      local top = Stack.top()
      local topId = top and top.id
      if topId == nil then
        -- Nothing left on the stack at all: either the dispatch never
        -- pushed anything, or the player has already backed all the way out
        -- on their own. Either way there is nothing left to close.
        pending = false
        return
      end
      if topId ~= "start" then
        sawOpened = true
        return
      end
      if not sawOpened then return end
      pending = false
      local okSm, StartMenu = pcall(require, "src.ui.StartMenu")
      if okSm and type(StartMenu.close) == "function" then pcall(StartMenu.close) end
    end)
  end

  local function bindingFor(inputId, actionId)
    local value = bindings()[inputId][actionId]
    if value == false then return nil end
    return value
  end

  local function saveBinding(inputId, actionId, value)
    local all = bindings()
    all[inputId][actionId] = value or false
    shared.store.set("menu_hotkeys", all)
  end

  local function ensureSpec(inputId, actionId)
    if specs[inputId][actionId] then return specs[inputId][actionId] end
    local spec = shared.registerHotkey({
      id = "menu." .. inputId .. "." .. actionId,
      input = inputId,
      context = "overworld",
      enabled = isEnabled,
      get = function() return bindingFor(inputId, actionId) end,
      set = function(value) saveBinding(inputId, actionId, value) end,
      onFire = function(game)
        -- Deliberately *not* refreshed first.  activateMenuItem refreshes
        -- itself, after its gate, and the order matters on Gen 3: refreshing
        -- means StartMenu.new(), which on FireRed opens the start menu rather
        -- than just building it, and an open menu is one Hud.busy() reports
        -- as a busy world -- so a pre-refresh made canOpenMenu answer false
        -- about a situation it had itself created, and every menu hotkey
        -- stopped at the start menu it had just opened.
        --
        -- deferUntilIdle is what actually opens it: canOpenMenu answers no
        -- while the player is mid-step on every generation (see shared.lua's
        -- "deferred retry" section), so a press thrown while walking is
        -- retried each frame rather than dropped, landing the moment the
        -- step does -- same as pressing START for real would.
        shared.deferUntilIdle(game, function(g)
          local opened = shared.activateMenuItem(g, actionId)
          if opened and isGen3 and isQuickExit() then armQuickExit() end
          return opened
        end)
      end,
    })
    specs[inputId][actionId] = spec
    return spec
  end

  for _, inputId in ipairs({ "keyboard", "gamepad" }) do
    for actionId in pairs(bindings()[inputId]) do ensureSpec(inputId, actionId) end
  end

  local function rows(game, inputId)
    local rows = { shared.enabledRow("menuHotkey.enabled", isEnabled, setEnabled) }
    if isGen3 then
      rows[#rows + 1] = {
        id = "menuHotkey.quickExit",
        label = "QUICK EXIT",
        value = function() return isQuickExit() and "ON" or "OFF" end,
        step = function() setQuickExit(not isQuickExit()); return true end,
        unassign = function() setQuickExit(false); return true end,
        help = "ON backs CANCEL out of a hotkey-opened menu straight to the "
          .. "overworld. OFF leaves the START menu open behind it, the same "
          .. "as pressing START yourself would. Red and Gold already work "
          .. "this way and are not affected by this setting.",
      }
    end
    for _, item in ipairs(shared.refreshStartMenuItems(game)) do
      local current = item
      local spec = ensureSpec(inputId, current.id)
      rows[#rows + 1] = {
        id = "menuHotkey." .. current.id,
        label = current.label,
        value = function() return shared.comboLabel(spec:get()) end,
        help = "Opens " .. tostring(current.label) .. " straight from the "
          .. "overworld. Combinations win over single buttons, so RT+Y can "
          .. "sit alongside a plain Y.",
        activate = function(g) shared.captureCombo(g, current.label, spec) end,
        unassign = function() shared.setBinding(spec, nil); return true end,
      }
    end
    rows[#rows + 1] = {
      id = "menuHotkey.clear",
      label = "CLEAR BINDINGS",
      help = "Unassigns every menu hotkey for this controller type.",
      activate = function()
        for _, spec in pairs(specs[inputId]) do shared.setBinding(spec, nil) end
        return true
      end,
    }
    return rows
  end

  suite.register("keyboard", {
    id = "menu_hotkeys", label = "MENU HOTKEYS", context = "overworld",
    rows = rows,
  })
  suite.register("gamepad", {
    id = "menu_hotkeys", label = "MENU HOTKEYS", context = "overworld",
    rows = rows,
  })
  shared.registerReset(function() setEnabled(false) end)

  shared.menuHotkeys = {
    bindings = bindings, bindingFor = bindingFor, setBinding = saveBinding,
    ensureSpec = ensureSpec, isEnabled = isEnabled, setEnabled = setEnabled,
  }
end
