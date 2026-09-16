return function(mod, suite)
  local shared = suite.shared
  local specs = { keyboard = {}, gamepad = {} }

  local function bindings()
    local value = mod.save:get("menu_hotkeys", {})
    if type(value) ~= "table" then value = {} end
    value.keyboard = type(value.keyboard) == "table" and value.keyboard or {}
    value.gamepad = type(value.gamepad) == "table" and value.gamepad or {}
    return value
  end

  local function bindingFor(inputId, actionId)
    local value = bindings()[inputId][actionId]
    if value == false then return nil end
    return value
  end

  local function saveBinding(inputId, actionId, value)
    local all = bindings()
    all[inputId][actionId] = value or false
    mod.save:set("menu_hotkeys", all)
  end

  local function ensureSpec(inputId, actionId)
    if specs[inputId][actionId] then return specs[inputId][actionId] end
    local spec = shared.registerHotkey({
      id = "menu." .. inputId .. "." .. actionId,
      input = inputId,
      context = "overworld",
      get = function() return bindingFor(inputId, actionId) end,
      set = function(value) saveBinding(inputId, actionId, value) end,
      onFire = function(game)
        shared.refreshStartMenuItems(game)
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
    local rows = {}
    for _, item in ipairs(shared.refreshStartMenuItems(game)) do
      local current = item
      local spec = ensureSpec(inputId, current.id)
      rows[#rows + 1] = {
        id = "menuHotkey." .. current.id,
        label = current.label,
        value = function() return shared.comboLabel(spec:get()) end,
        activate = function(g) shared.captureCombo(g, current.label, spec) end,
        unassign = function() shared.setBinding(spec, nil); return true end,
      }
    end
    rows[#rows + 1] = {
      id = "menuHotkey.clear",
      label = "CLEAR BINDINGS",
      activate = function()
        for _, spec in pairs(specs[inputId]) do shared.setBinding(spec, nil) end
        return true
      end,
    }
    return rows
  end

  suite.register("keyboard", {
    id = "menu_hotkeys", label = "MENU HOTKEYS", rows = rows,
  })
  suite.register("gamepad", {
    id = "menu_hotkeys", label = "MENU HOTKEYS", rows = rows,
  })
  shared.menuHotkeys = {
    bindings = bindings, bindingFor = bindingFor, setBinding = saveBinding,
    ensureSpec = ensureSpec,
  }
end
