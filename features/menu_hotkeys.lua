return function(mod, suite)
  local shared = suite.shared
  local specs = { keyboard = {}, gamepad = {} }

  local function bindings()
    local value = shared.store.get("menu_hotkeys", nil)
    if type(value) ~= "table" then value = {} end
    if value.enabled == nil then value.enabled = false end
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
        shared.activateMenuItem(game, actionId)
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
