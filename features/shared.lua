return function(mod, suite)
  local shared = suite.shared
  local Font = require("src.render.Font")
  local Screens = require("src.ui.Screens")

  -- Settings persistence.
  --
  -- `mod.save` is backed by `save.modData` (src/core/Game.lua, Game:adoptSave),
  -- which makes it *save-slot* state: it only reaches disk when the player
  -- saves in-game, and adoptSave REPLACES the loader's bucket outright on NEW
  -- GAME and CONTINUE.  Every hotkey spec compiles its combination once at
  -- registration time, so swapping the backing table out from under it left
  -- the broker holding boot-time (empty) combinations while the settings
  -- screens still read the real values -- hotkeys looked assigned and fired
  -- nothing.  It also meant a crash, or quitting without saving, discarded
  -- whatever the player had just configured.
  --
  -- Hotkey configuration describes the installation, not a playthrough, so it
  -- belongs in `mod.cache`: installation-scoped, independent of save slots,
  -- and written straight through to disk (src/mods/ImportAccess.lua).
  local STORE_FILE = "settings.lua"
  local LEGACY_KEYS = {
    "bindings", "autofire", "menu_hotkeys", "radial", "travel",
    "battleHotkeys", "ballMenu", "battleText",
  }
  local storeData, storeLoaded, storeBroken

  local function encode(value, indent, out)
    local kind = type(value)
    if kind == "table" then
      local inner = indent .. "  "
      local count = #value
      out[#out + 1] = "{\n"
      for i = 1, count do
        out[#out + 1] = inner
        encode(value[i], inner, out)
        out[#out + 1] = ",\n"
      end
      local keys = {}
      for key in pairs(value) do
        local isArrayIndex = type(key) == "number" and key % 1 == 0
          and key >= 1 and key <= count
        local usable = type(key) == "string" or type(key) == "number"
          or type(key) == "boolean"
        if usable and not isArrayIndex then keys[#keys + 1] = key end
      end
      table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
      for _, key in ipairs(keys) do
        out[#out + 1] = inner .. "["
        encode(key, inner, out)
        out[#out + 1] = "] = "
        encode(value[key], inner, out)
        out[#out + 1] = ",\n"
      end
      out[#out + 1] = indent .. "}"
    elseif kind == "string" then
      out[#out + 1] = string.format("%q", value)
    elseif kind == "number" then
      out[#out + 1] = value % 1 == 0 and string.format("%d", value)
        or string.format("%.14g", value)
    elseif kind == "boolean" then
      out[#out + 1] = tostring(value)
    else
      out[#out + 1] = "nil"
    end
  end

  -- The file is data only and is parsed with an empty environment, so a
  -- corrupted or hand-edited settings file can never reach the engine.
  --
  -- storeFlush writes a body that already carries its own `return`, so the
  -- text is loaded as-is.  The bare-table form is still accepted so a file
  -- written by hand, or by any earlier build, still loads.
  local function decode(text)
    if type(text) ~= "string" or text == "" then return nil end
    local chunk = loadstring(text, "@hotkey_suite settings")
    if not chunk then
      chunk = loadstring("return " .. text, "@hotkey_suite settings")
    end
    if not chunk then return nil end
    if setfenv then setfenv(chunk, {}) end
    local ok, value = pcall(chunk)
    if ok and type(value) == "table" then return value end
    return nil
  end

  -- A settings file that exists but cannot be read is a real fault: it means
  -- the player's configuration is on disk and being ignored, which looks
  -- exactly like every hotkey silently switching itself off.  Saying so is
  -- the difference between a diagnosable bug and an invisible one.
  local function storeEnsure()
    if storeLoaded then return storeData end
    storeLoaded = true
    local ok, raw = pcall(function() return mod.cache:read(STORE_FILE) end)
    storeData = ok and decode(raw) or nil
    if not storeData and ok and type(raw) == "string" and raw ~= "" then
      if mod.log and mod.log.warn then
        mod.log:warn("settings file could not be parsed; falling back to "
          .. "defaults. The existing file is left untouched until a setting "
          .. "is changed.")
      end
    end
    storeData = storeData or {}
    return storeData
  end

  local function storeFlush()
    local out = {}
    encode(storeEnsure(), "", out)
    local body = "return " .. table.concat(out) .. "\n"
    -- mod.cache:write reports failure by returning `nil, reason` rather than
    -- raising, so both outcomes have to be checked.
    local ok, wrote, reason = pcall(function()
      return mod.cache:write(STORE_FILE, body)
    end)
    if (not ok or not wrote) and not storeBroken then
      storeBroken = true
      if mod.log and mod.log.warn then
        mod.log:warn("could not persist settings: " ..
          tostring(ok and (reason or "write failed") or wrote))
      end
    end
  end

  local store = {}
  function store.get(key, default)
    local value = storeEnsure()[key]
    if value == nil then return default end
    return value
  end
  function store.set(key, value)
    local data = storeEnsure()
    data[key] = value
    -- Once the player has written anything through the new store their
    -- configuration is authoritative, so no save file may import over it.
    data.__migrated = true
    storeFlush()
  end
  shared.store = store

  -- One-way import of pre-1.7 configuration out of the save slot.  It can only
  -- run while nothing has been written through the new store, and it latches
  -- the moment it finds anything, so loading an older save later can never
  -- clobber settings the player has since changed.
  local function storeMigrate()
    local data = storeEnsure()
    if data.__migrated then return false end
    local imported = false
    for _, key in ipairs(LEGACY_KEYS) do
      if data[key] == nil then
        local legacy = mod.save:get(key, nil)
        if type(legacy) == "table" and next(legacy) ~= nil then
          data[key] = legacy
          imported = true
        end
      end
    end
    if not imported then return false end
    data.__migrated = true
    storeFlush()
    if mod.log and mod.log.info then
      mod.log:info("imported legacy hotkey settings from the save slot")
    end
    return true
  end
  shared.migrateSettings = storeMigrate

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
    local value = store.get("bindings", nil)
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
    -- FireRed keeps no battle object on the game and stays in phase "field"
    -- while one runs, so neither check above sees it.  The engine's own
    -- answer is Game3:speedCategory(), which asks battle.isActive()
    -- (src/core/Game3.lua:571-577).
    if type(game.speedCategory) == "function" then
      local ok, category = pcall(game.speedCategory, game)
      if ok and category == "battle" then return "battle" end
    end
    -- Gold keeps the world off the stack entirely, so there is no states[1]
    -- to recognise it by.  FireRed keeps nothing world-shaped on the game at
    -- all and is reached through the mod API.
    if shared.world and shared.world.find(game) then return "overworld" end
    return "other"
  end

  local function specEnabled(spec)
    if type(spec.enabled) ~= "function" then return true end
    local ok, value = pcall(spec.enabled)
    return not ok or value ~= false
  end
  shared.specEnabled = specEnabled

  -- A bound key pressed while the player is editing bindings belongs to the
  -- settings screen, not to the hotkey it is assigned to.  This scans the
  -- whole stack rather than just the top, because the suite pushes its own
  -- help boxes OVER a settings screen: checking only the top would let
  -- synthesized input (autofire) through the moment help opened, which blew
  -- straight past the help text before it could be read.
  -- An alternate presentation (Gen 3) registers itself here.  Gen 3 has no
  -- `game.stack` for the Gen 1 chrome to push onto, so that build supplies
  -- its own screen layer and the logic below routes to it instead.
  local altUi = nil
  function shared.registerUi(ui) altUi = ui end

  local function suiteScreenOpen(game)
    if altUi and altUi.isOpen and altUi.isOpen() then return true end
    local stack = game and game.stack
    local states = stack and stack.states
    for index = #(states or {}), 1, -1 do
      local state = states[index]
      if type(state) == "table" and state.isHotkeySuiteScreen == true then
        return true
      end
    end
    return false
  end
  shared.suiteScreenOpen = suiteScreenOpen

  local function contextAllows(spec, game)
    if not specEnabled(spec) then return false end
    if suiteScreenOpen(game) then return false end
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

  -- ----------------------------------------------------------- suite chrome
  --
  -- Every pixel the suite draws for itself -- the settings screens, the
  -- capture prompt, the radial and the autofire notice -- is Gen 1 chrome:
  -- the src.render.Font atlas on a 160x144 frame, pushed onto game.stack.
  -- Gold shares all three, so both generations get the same screens for free.
  -- FireRed shares none of them.  It runs 240x160, draws with
  -- src/ui/game3/frlg_font.lua, and its Game object has no state stack at all
  -- (src/core/Game3.lua:115), so a push is an index of nil and a Font.draw is
  -- a frame of nothing.  Behaviour is at parity across all three generations;
  -- the chrome deliberately is not, and this is the one gate that says so.
  -- Bindings are stored per installation rather than per generation, so a
  -- hotkey assigned on Red or Gold is already live on FireRed.
  function shared.chromeAvailable(game)
    if game == nil then return tonumber(mod.generation) ~= 3 end
    return type(game.stack) == "table" and type(game.stack.push) == "function"
  end

  -- Arming the capture is independent of drawing it, so both presentations
  -- share one state machine and only differ in what they put on screen.
  local function beginCapture(spec)
    local ignore = processingInput and processingInput.input == spec.input
      and processingInput.pressed and processingInput.name or nil
    capture = {
      input = spec.input, spec = spec, pending = {}, down = {},
      ignoreUntilRelease = ignore,
    }
  end

  --- The live capture state, or nil.  Read-only; for alternate presentations
  --- that need to draw the pending combo themselves.
  function shared.captureState() return capture end

  shared.MAX_COMBO_PIECES = 4

  local CaptureScreen = {}
  CaptureScreen.__index = CaptureScreen
  CaptureScreen.isOpaque = true
  CaptureScreen.isHotkeySuiteScreen = true
  CaptureScreen.MAX_PIECES = shared.MAX_COMBO_PIECES

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
      beginCapture(spec)
      return setmetatable({ game = game, title = title }, CaptureScreen)
    end,
  })

  function shared.captureCombo(game, title, spec)
    if shared.chromeAvailable(game) then
      Screens.push(game, "HotkeySuiteCapture", title, spec)
      return
    end
    -- Gen 3: the suite's own layer draws the prompt.  `beginCapture` first so
    -- the layer can render the pending combo on the very frame it opens.
    if altUi and altUi.openCapture then
      beginCapture(spec)
      altUi.openCapture(game, title, spec)
    end
  end

  -- Tear down whichever presentation is showing the capture prompt.
  local function closeCapture(game)
    if altUi and altUi.captureOpen and altUi.captureOpen() then
      if altUi.closeCapture then altUi.closeCapture() end
      return
    end
    if game and type(game.stack) == "table" and game.stack.pop then
      game.stack:pop()
    end
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
      closeCapture(game)
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
          closeCapture(game)
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
    -- Cheap no-op once the flag latches; this is the first point in the frame
    -- where a CONTINUE has already pointed mod.save at the loaded slot.
    if storeMigrate() then shared.refreshHotkeys() end
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

  -- Gold's start-menu rows carry explicit ids where Gen 1's are derived from
  -- their labels, and three of them name the same menu differently.  Folding
  -- those onto the Gen 1 spelling keeps a saved binding working when the same
  -- installation launches the other generation, since settings are stored per
  -- installation rather than per save.
  local MENU_ID_ALIASES = {
    pack = "item", option = "options", status = "trainer_card",
    -- FireRed's own names for the same three rows.
    bag = "item", trainer = "trainer_card",
  }

  local function stableMenuId(game, item, index)
    -- Gen 1 rows identify themselves with `id`; Gold's carry it as `value`.
    local raw = item.id
    if raw == nil then raw = item.value end
    if raw ~= nil then
      local id = tostring(raw)
      return MENU_ID_ALIASES[id] or id
    end
    local label = tostring(item.label or item.name or "")
    local upper = label:upper()
    if upper:find("DEX", 1, true) then return "pokedex" end
    if upper:find("MON", 1, true) then return "pokemon" end
    if upper == "ITEM" or upper == "BAG" or upper == "PACK" then return "item" end
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
      -- Gen 1 rows carry the function that opens them; Gold's are data that
      -- dispatch by id.  The adapter answers both, so a row is kept whenever
      -- the engine gives us any way at all to open it.
      local activate = shared.menu.activator(game, item)
      if type(activate) == "function" then
        local label = shared.menu.label(game, item, index)
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
  -- The cache is keyed by game because Gen 1 raises the hook with the very
  -- object the input hooks hand out.  FireRed raises it with whatever
  -- Gen3Compat's live() resolved at the moment the menu opened, which is the
  -- same Game3 in practice but is not guaranteed to be, and a miss there
  -- would silently empty the menu hotkeys.  The last list is therefore kept
  -- alongside as a fallback; only one start menu can be open at a time in any
  -- of the three engines, so there is nothing for it to be confused with.
  local lastMenuItems
  mod.hooks:wrap("ui.start_menu.items", function(next, game, items)
    local out = next(game, items)
    if type(out) == "table" then
      menuCache[game] = extractMenuItems(game, out)
      lastMenuItems = menuCache[game]
      for _, listener in ipairs(menuListeners) do listener(game, menuCache[game]) end
    end
    return out
  end, 1000000)

  -- Refreshing the list is not free on every engine.  Gen 1 and Gold build a
  -- menu object here and leave it unshown, but FireRed has no such object:
  -- Gen3Compat backs `new` with Hud.openStartMenu, so asking what is on the
  -- start menu *opens* the start menu.  Callers that also gate on the world
  -- being idle must therefore gate first and refresh second, because an open
  -- menu is a busy world as far as Hud.busy() is concerned.
  function shared.refreshStartMenuItems(game)
    require("src.ui.StartMenu").new(game)
    return menuCache[game] or lastMenuItems or {}
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
    -- FireRed has no state stack at all: its menus are pushed onto
    -- src/ui/game3/stack.lua by the screens themselves, and the engine's own
    -- dispatcher layers the new one over the start menu rather than unwinding
    -- first.  Leaving it alone is what makes a menu hotkey there land exactly
    -- where pressing START and A would.
    if not stack or not stack.states then return end
    local _, kind = shared.world.find(game)
    if kind == "field" then
      -- Gold's world is not on the stack, so "back to the overworld" means
      -- emptying the stack rather than unwinding to states[1].  The guard
      -- keeps a pop that does not shrink from spinning forever.
      local guard = #stack.states
      while #stack.states > 0 and guard > 0 do
        stack:pop()
        guard = guard - 1
      end
      return
    end
    while #stack.states > 1 and stack:top() ~= stack.states[1] do stack:pop() end
  end
  -- Only the overworld's own state gates opening a menu here.  Requiring an
  -- empty stack on top of it would also block *switching* between two
  -- already-open menus (closeMenus() is what pops the old one), so this only
  -- confirms the world itself is safe to act on.
  --
  -- FireRed cannot draw that distinction: the single answer it exposes,
  -- Hud.busy(), already counts an open menu as busy (src/ui/game3/hud.lua:49).
  -- A menu hotkey there opens from the field as it does everywhere else, but
  -- pressing a second one while a menu is up does nothing rather than
  -- switching.  That is the engine's own gate, not a rule invented here.
  function shared.canOpenMenu(game)
    if not game or shared.context(game) ~= "overworld" then return false end
    local base, kind = shared.world.find(game)
    if not base then return false end
    return not shared.world.busy(base, kind)
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
