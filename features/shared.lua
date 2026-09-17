return function(mod, suite)
  local shared = suite.shared
  local Font = require("src.render.Font")
  local Screens = require("src.ui.Screens")
  local menuCache = setmetatable({}, { __mode = "k" })
  local menuListeners = {}
  local hotkeys = { keyboard = {}, gamepad = {} }
  local heldInputs = { keyboard = {}, gamepad = {} }
  local rawListeners = { keyboard = {}, gamepad = {} }
  local statProviders = {}
  local resetProviders = {}
  local capture
  local processingInput
  local gamepadNext

  local PAD_ALIASES = {
    rt = "triggerright", righttrigger = "triggerright",
    triggerright = "triggerright",
    lt = "triggerleft", lefttrigger = "triggerleft",
    triggerleft = "triggerleft",
    rb = "rightshoulder", rightshoulder = "rightshoulder",
    lb = "leftshoulder", leftshoulder = "leftshoulder",
  }

  function shared.normalize(inputId, name)
    name = tostring(name or ""):lower()
    return inputId == "gamepad" and (PAD_ALIASES[name] or name) or name
  end

  function shared.describe(pieces)
    local labels = {
      triggerleft = "LT", triggerright = "RT",
      leftshoulder = "LB", rightshoulder = "RB",
      capslock = "CAPS", ["return"] = "ENTER",
    }
    local out = {}
    for _, piece in ipairs(pieces or {}) do
      local name = shared.normalize(piece.input, piece.name)
      out[#out + 1] = labels[name] or name:upper()
    end
    return #out > 0 and table.concat(out, "+") or "UNBOUND"
  end

  local function canonical(inputId, pieces)
    if type(pieces) == "string" then pieces = { pieces } end
    if type(pieces) ~= "table" then pieces = {} end
    local out, seen = {}, {}
    for _, piece in ipairs(pieces or {}) do
      local name = shared.normalize(inputId,
        type(piece) == "table" and piece.name or piece)
      if name ~= "" and not seen[name] then
        seen[name] = true
        out[#out + 1] = { input = inputId, name = name }
      end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
  end
  shared.canonicalCombo = canonical

  function shared.comboLabel(inputIdOrPieces, pieces)
    if pieces == nil then
      pieces = inputIdOrPieces
      local first = type(pieces) == "table" and pieces[1]
      local inputId = type(first) == "table" and first.input or "keyboard"
      return shared.describe(canonical(inputId, pieces))
    end
    return shared.describe(canonical(inputIdOrPieces, pieces))
  end

  local function signature(pieces)
    local names = {}
    for _, piece in ipairs(pieces or {}) do names[#names + 1] = piece.name end
    return table.concat(names, "\0")
  end

  local function bindingAllowed(inputId, pieces)
    return not (inputId == "gamepad" and #pieces == 1
      and (pieces[1].name == "a" or pieces[1].name == "b"))
  end
  shared.bindingAllowed = bindingAllowed

  local function bindingStore()
    local value = mod.save:get("bindings", {})
    return type(value) == "table" and value or {}
  end

  local function rebuild(spec)
    local pieces = canonical(spec.input, spec.get())
    spec.pieces, spec.signature = pieces, signature(pieces)
    spec.keys, spec.fired = {}, false
    for _, piece in ipairs(pieces) do spec.keys[piece.name] = true end
  end

  function shared.registerHotkey(spec)
    assert(hotkeys[spec.input], "unsupported hotkey input")
    assert(spec.id and spec.get and spec.set and spec.onFire, "invalid hotkey spec")
    hotkeys[spec.input][#hotkeys[spec.input] + 1] = spec
    rebuild(spec)
    if not bindingAllowed(spec.input, spec.pieces) then
      spec.set(nil)
      rebuild(spec)
    end
    if spec.signature ~= "" then
      for _, other in ipairs(hotkeys[spec.input]) do
        if other ~= spec and other.signature == spec.signature then
          other.set(nil)
          rebuild(other)
        end
      end
    end
    return spec
  end

  function shared.onRaw(inputId, listener)
    rawListeners[inputId][#rawListeners[inputId] + 1] = listener
  end

  function shared.refreshHotkeys()
    for _, list in pairs(hotkeys) do
      for _, spec in ipairs(list) do rebuild(spec) end
      table.sort(list, function(a, b) return #a.pieces > #b.pieces end)
    end
  end

  function shared.setBinding(spec, pieces)
    pieces = canonical(spec.input, pieces)
    if not bindingAllowed(spec.input, pieces) then return false end
    local sig = signature(pieces)
    if sig ~= "" then
      for _, other in ipairs(hotkeys[spec.input]) do
        rebuild(other)
        if other ~= spec and other.signature == sig then other.set(nil) end
      end
    end
    spec.set(#pieces > 0 and pieces or nil)
    shared.refreshHotkeys()
    return true
  end

  function shared.clearBinding(spec) shared.setBinding(spec, nil) end

  function shared.registerReset(provider)
    resetProviders[#resetProviders + 1] = provider
  end

  function shared.clearAllBindings()
    for _, list in pairs(hotkeys) do
      for _, spec in ipairs(list) do spec.set(nil) end
    end
    for _, provider in ipairs(resetProviders) do provider() end
    shared.refreshHotkeys()
  end

  function shared.registerStats(provider)
    statProviders[#statProviders + 1] = provider
  end

  function shared.hotkeySummary()
    local active, assigned = 0, 0
    for _, list in pairs(hotkeys) do
      for _, spec in ipairs(list) do
        if spec.signature ~= "" then
          assigned = assigned + 1
          if shared.specEnabled(spec) then active = active + 1 end
        end
      end
    end
    for _, provider in ipairs(statProviders) do
      local extraActive, extraAssigned = provider()
      active = active + (extraActive or 0)
      assigned = assigned + (extraAssigned or 0)
    end
    return active, assigned
  end

  function shared.context(game)
    if game and (game.battle or game.battleState) then return "battle" end
    local stack = game and game.stack
    for _, state in ipairs(stack and stack.states or {}) do
      local id = tostring(state.screenId or state.__name
        or (state.class and state.class.name) or "")
      if state.isBattle or id:find("Battle", 1, true) then return "battle" end
    end
    local base = stack and stack.states and stack.states[1]
    if base and (base.isOverworld or base == game.overworld or base.map ~= nil) then
      return "overworld"
    end
    return "other"
  end

  local function specEnabled(spec)
    if type(spec.enabled) ~= "function" then return true end
    local ok, value = pcall(spec.enabled)
    return not ok or value ~= false
  end
  shared.specEnabled = specEnabled

  local function contextAllows(spec, game)
    if not specEnabled(spec) then return false end
    if spec.context == "any" then return true end
    if type(spec.context) == "function" then return spec.context(game) end
    return shared.context(game) == spec.context
  end

  -- A module master switch. Every module ships disabled so a fresh install
  -- never reacts to input the player has not opted into.
  function shared.enabledRow(id, get, set)
    return {
      id = id,
      label = "ENABLED",
      value = function() return get() and "ON" or "OFF" end,
      step = function() set(not get()); return true end,
      unassign = function() set(false); return true end,
    }
  end

  local CaptureScreen = {}
  CaptureScreen.__index = CaptureScreen
  CaptureScreen.isOpaque = true
  CaptureScreen.MAX_PIECES = 4

  function CaptureScreen:sgbPalettes(game)
    return require("src.render.PaletteFX").wholeNamed(game.data, "MEWMON")
  end

  function CaptureScreen:update()
    if capture and self.game.stack:top() ~= self then capture = nil end
    if not capture and self.game.stack:top() == self then self.game.stack:pop() end
  end
  function CaptureScreen:draw()
    love.graphics.setColor(1, 1, 1, 1)
    Font.drawBox(0, 2, 20, 13)
    love.graphics.setColor(0, 0, 0, 1)
    Font.draw(self.title, math.max(8, math.floor((160 - Font.width(self.title)) / 2)), 24)
    Font.draw("HOLD A COMBINATION", 8, 48)
    Font.draw("RELEASE TO ASSIGN", 8, 64)
    Font.draw(shared.describe(capture and capture.pending or {}),
      8, 88)
    Font.draw(capture and capture.message or "ESC CANCELS", 8, 104)
    love.graphics.setColor(1, 1, 1, 1)
  end

  mod.content.screens:register("HotkeySuiteCapture", {
    new = function(game, title, spec)
      local ignore = processingInput and processingInput.input == spec.input
        and processingInput.pressed and processingInput.name or nil
      capture = {
        input = spec.input, spec = spec, pending = {}, down = {},
        ignoreUntilRelease = ignore,
      }
      return setmetatable({ game = game, title = title }, CaptureScreen)
    end,
  })

  function shared.captureCombo(game, title, spec)
    Screens.push(game, "HotkeySuiteCapture", title, spec)
  end

  local function captureInput(inputId, name, pressed, game)
    if not capture or capture.input ~= inputId then return false end
    if capture.ignoreUntilRelease then
      if name == capture.ignoreUntilRelease and not pressed then
        capture.ignoreUntilRelease = nil
        return false
      end
      return true
    end
    if inputId == "keyboard" and name == "escape" and pressed then
      capture = nil
      game.stack:pop()
      return true
    end
    if pressed and not capture.down[name]
        and #capture.pending < CaptureScreen.MAX_PIECES then
      capture.message = nil
      capture.down[name] = true
      capture.pending[#capture.pending + 1] = { input = inputId, name = name }
      return true
    elseif not pressed and capture.down[name] then
      capture.down[name] = nil
      if next(capture.down) == nil and #capture.pending > 0 then
        local spec, pieces = capture.spec, capture.pending
        if bindingAllowed(inputId, canonical(inputId, pieces)) then
          capture = nil
          game.stack:pop()
          shared.setBinding(spec, pieces)
        else
          capture.pending = {}
          capture.message = "A/B NEED A COMBO"
        end
      end
      return true
    end
    return false
  end

  local function dispatch(inputId, name, pressed, game, ev)
    name = shared.normalize(inputId, name)
    if captureInput(inputId, name, pressed, game) then return true end
    heldInputs[inputId][name] = pressed and true or nil
    for _, listener in ipairs(rawListeners[inputId]) do
      pcall(listener, name, pressed, game, ev)
    end
    local maxCompletedPieces = 0
    if pressed then
      for _, spec in ipairs(hotkeys[inputId]) do
        if spec.keys[name] and not spec.fired and contextAllows(spec, game) then
          local complete = #spec.pieces > 0
          for _, piece in ipairs(spec.pieces) do
            if not heldInputs[inputId][piece.name] then
              complete = false
              break
            end
          end
          if complete then
            maxCompletedPieces = math.max(maxCompletedPieces, #spec.pieces)
          end
        end
      end
    end
    for _, spec in ipairs(hotkeys[inputId]) do
      if spec.keys[name] then
        local allowed = contextAllows(spec, game)
        local complete = #spec.pieces > 0
        for _, piece in ipairs(spec.pieces) do
          if not heldInputs[inputId][piece.name] then
            complete = false
            break
          end
        end
        if complete and not spec.fired and allowed
            and #spec.pieces == maxCompletedPieces then
          spec.fired = true
          local ok, err = pcall(spec.onFire, game, ev)
          if not ok then
            spec.fired = false
            if mod.log and mod.log.warn then
              mod.log:warn("Hotkey error on " .. tostring(spec.id) .. ": " .. tostring(err))
            end
          end
        elseif not complete and spec.fired then
          spec.fired = false
          if spec.onBreak then
            pcall(spec.onBreak, game, ev)
          end
        end
      end
    end
    return false
  end
  shared.dispatchInput = dispatch

  mod.hooks:wrap("input.key", function(next, game, ev)
    if ev.phase ~= "pressed" and ev.phase ~= "released" then
      return next(game, ev)
    end
    if capture and capture.input == "keyboard" then
      if dispatch("keyboard", ev.key, ev.phase == "pressed", game, ev) then return end
      return next(game, ev)
    end
    processingInput = {
      input = "keyboard", name = shared.normalize("keyboard", ev.key),
      pressed = ev.phase == "pressed",
    }
    local result = next(game, ev)
    processingInput = nil
    if capture then return result end
    dispatch("keyboard", ev.key, ev.phase == "pressed", game, ev)
    return result
  end)

  local triggers = setmetatable({}, { __mode = "k" })
  function shared.triggerStep(wasPressed, value)
    if not wasPressed and (value or 0) >= 0.35 then return true end
    if wasPressed and (value or 0) <= 0.20 then return false end
  end
  mod.hooks:wrap("input.gamepad", function(next, game, ev)
    gamepadNext = next
    if capture and capture.input ~= "gamepad" then
      local result = next(game, ev)
      gamepadNext = nil
      return result
    end
    local axis = ev.phase == "axis" and shared.normalize("gamepad", ev.axis)
    if axis == "triggerleft" or axis == "triggerright" then
      if capture and capture.input == "gamepad" then
        local pad = ev.joystick or triggers
        triggers[pad] = triggers[pad] or {
          triggerleft = false, triggerright = false,
        }
        local state = triggers[pad]
        local pressed = shared.triggerStep(state[axis], ev.value)
        if pressed ~= nil then
          state[axis] = pressed
          if dispatch("gamepad", axis, pressed, game, ev) then
            gamepadNext = nil
            return
          end
        end
        local result = next(game, ev)
        gamepadNext = nil
        return result
      end
      local result = next(game, ev)
      local pad = ev.joystick or triggers
      triggers[pad] = triggers[pad] or { triggerleft = false, triggerright = false }
      local state = triggers[pad]
      local pressed = shared.triggerStep(state[axis], ev.value)
      if pressed ~= nil then
        state[axis] = pressed
        dispatch("gamepad", axis, pressed, game, ev)
      end
      gamepadNext = nil
      return result
    elseif ev.phase == "pressed" or ev.phase == "released" then
      if capture and capture.input == "gamepad" then
        if dispatch("gamepad", ev.button, ev.phase == "pressed", game, ev) then
          gamepadNext = nil
          return
        end
        local result = next(game, ev)
        gamepadNext = nil
        return result
      end
      processingInput = {
        input = "gamepad", name = shared.normalize("gamepad", ev.button),
        pressed = ev.phase == "pressed",
      }
      local result = next(game, ev)
      processingInput = nil
      dispatch("gamepad", ev.button, ev.phase == "pressed", game, ev)
      gamepadNext = nil
      return result
    end
    local result = next(game, ev)
    gamepadNext = nil
    return result
  end)

  mod.hooks:wrap("input.step", function(next, game, dt)
    next(game, dt)
    if love and love.keyboard and type(love.keyboard.isDown) == "function" then
      for key, isHeld in pairs(heldInputs.keyboard) do
        if isHeld then
          local ok, down = pcall(love.keyboard.isDown, key)
          if ok and not down then
            dispatch("keyboard", key, false, game)
          end
        end
      end
    end
    local joystickApi = love and love.joystick
    if not joystickApi or type(joystickApi.getJoysticks) ~= "function" then return end
    local joysticks = joystickApi.getJoysticks()
    for _, joystick in ipairs(joysticks) do
      if type(joystick.getGamepadAxis) == "function" then
        triggers[joystick] = triggers[joystick]
          or { triggerleft = false, triggerright = false }
        local state = triggers[joystick]
        for _, axis in ipairs({ "triggerleft", "triggerright" }) do
          local ok, value = pcall(joystick.getGamepadAxis, joystick, axis)
          if ok and type(value) == "number" then
            local pressed = shared.triggerStep(state[axis], value)
            if pressed ~= nil then
              state[axis] = pressed
              dispatch("gamepad", axis, pressed, game, {
                phase = "axis", axis = axis, value = value, joystick = joystick,
              })
            end
          end
        end
      end
    end
    if #joysticks > 0 then
      for btn, isHeld in pairs(heldInputs.gamepad) do
        if isHeld and btn ~= "triggerleft" and btn ~= "triggerright" then
          local downAny = false
          for _, joystick in ipairs(joysticks) do
            if type(joystick.isGamepadDown) == "function" then
              local ok, down = pcall(joystick.isGamepadDown, joystick, btn)
              if ok and down then
                downAny = true
                break
              end
            end
          end
          if not downAny then
            dispatch("gamepad", btn, false, game)
          end
        end
      end
    end
  end)

  function shared.neutralizeStick(game, joystick, stick)
    if not gamepadNext then return false end
    gamepadNext(game, {
      phase = "axis", joystick = joystick, axis = stick .. "x", value = 0,
    })
    gamepadNext(game, {
      phase = "axis", joystick = joystick, axis = stick .. "y", value = 0,
    })
    return true
  end

  function shared.cycle(values, current, dir)
    local index = 1
    for i, value in ipairs(values) do if value == current then index = i break end end
    return values[((index - 1 + (dir or 1)) % #values) + 1]
  end

  local function stableMenuId(game, item, index)
    if item.id then return tostring(item.id) end
    local label = tostring(item.label or item.name or "")
    local upper = label:upper()
    if upper:find("DEX", 1, true) then return "pokedex" end
    if upper:find("MON", 1, true) then return "pokemon" end
    if upper == "ITEM" or upper == "BAG" then return "item" end
    if upper == "SAVE" then return "save" end
    if upper == "OPTION" or upper == "OPTIONS" then return "options" end
    local player = game and game.save and game.save.player
    if player and upper == tostring(player.name or ""):upper() then return "trainer_card" end
    local normalized = label:lower():gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")
    return normalized ~= "" and normalized or ("item_" .. index)
  end
  shared.stableMenuId = stableMenuId

  local function extractMenuItems(game, source)
    local out, seen = {}, {}
    for index, item in ipairs(source or {}) do
      local activate = item.onSelect or item.activate or item.action or item.select
      if type(activate) == "function" then
        local label = tostring(item.label or item.name or item.id or ("ITEM " .. index))
        local base, id, suffix = stableMenuId(game, item, index), nil, 2
        id = base
        while seen[id] do id, suffix = base .. "_" .. suffix, suffix + 1 end
        seen[id] = true
        out[#out + 1] = { id = id, label = label, activate = activate }
      end
    end
    return out
  end

  function shared.onMenuItems(listener) menuListeners[#menuListeners + 1] = listener end
  mod.hooks:wrap("ui.start_menu.items", function(next, game, items)
    local out = next(game, items)
    if type(out) == "table" then
      menuCache[game] = extractMenuItems(game, out)
      for _, listener in ipairs(menuListeners) do listener(game, menuCache[game]) end
    end
    return out
  end, 1000000)

  function shared.refreshStartMenuItems(game)
    require("src.ui.StartMenu").new(game)
    return menuCache[game] or {}
  end
  function shared.startMenuItems(game)
    return menuCache[game] or shared.refreshStartMenuItems(game)
  end
  function shared.findMenuItem(game, id)
    for _, item in ipairs(shared.startMenuItems(game)) do
      if item.id == id then return item end
    end
  end
  function shared.closeMenus(game)
    local stack = game and game.stack
    if not stack or not stack.states then return end
    while #stack.states > 1 and stack:top() ~= stack.states[1] do stack:pop() end
  end
  -- Only the base overworld screen's own flags gate opening a menu here.
  -- Requiring an empty stack on top of it would also block *switching*
  -- between two already-open menus (closeMenus() is what pops the old one),
  -- so this only confirms the base screen itself is safe to act on.
  function shared.canOpenMenu(game)
    if not game or shared.context(game) ~= "overworld" then return false end
    local stack = game.stack
    local states = stack and stack.states
    local base = states and states[1]
    if not base then return false end
    local runner = base.runner or base.scriptRunner
    if runner and runner.isRunning and runner:isRunning() then return false end
    local moves = base.scriptMoves
    local hasMoves = type(moves) == "table" and #moves > 0
    return not (base.engaging or base.emote or base.teleportOut
      or base.transitioning or base.warping or hasMoves)
  end
  function shared.activateMenuItem(game, id)
    if not shared.canOpenMenu(game) then return false end
    shared.refreshStartMenuItems(game)
    local item = shared.findMenuItem(game, id)
    if not item then return false end
    shared.closeMenus(game)
    item.activate(game)
    return true
  end

  shared.bindingStore = bindingStore
end
