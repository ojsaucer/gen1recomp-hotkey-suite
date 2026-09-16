return function(mod, suite)
  local shared = suite.shared
  local af = shared.autofire
  local travel = shared.travel
  local Font = require("src.render.Font")
  local runtime = { rects = {}, touches = {} }

  local function config()
    local cfg = mod.save:get("touch", {})
    if type(cfg) ~= "table" then cfg = {} end
    if cfg.shortcuts == nil then cfg.shortcuts = false end
    cfg.slots = type(cfg.slots) == "table" and cfg.slots or {}
    if cfg.autofire == nil then cfg.autofire = false end
    return cfg
  end
  local function save(cfg) mod.save:set("touch", cfg) end

  local function menuChoices(game)
    local ids, labels = { "off" }, { off = "OFF" }
    for _, item in ipairs(shared.startMenuItems(game)) do
      ids[#ids + 1], labels[item.id] = item.id, item.label
    end
    return ids, labels
  end

  local function inside(rect, x, y)
    return x >= rect.x and x <= rect.x + rect.w
      and y >= rect.y and y <= rect.y + rect.h
  end

  mod.hooks:wrap("render.hud", function(next, game, viewport)
    next(game, viewport)
    runtime.rects = {}
    local stack = game and game.stack
    if not viewport or not shared.canOpenMenu(game)
        or not stack or not stack.states or #stack.states ~= 1 then return end
    local cfg = config()
    local cells = {}
    if cfg.shortcuts then
      local _, labels = menuChoices(game)
      for i = 1, 3 do
        local id = cfg.slots[i] or "off"
        if id ~= "off" and labels[id] then
          cells[#cells + 1] = { kind = "menu", id = id, label = labels[id] }
        end
      end
    end
    if cfg.autofire then
      cells[#cells + 1] = { kind = "autofire", id = "autofire", label = "AF" }
    end
    for _, action in ipairs(travel.touchActions()) do
      cells[#cells + 1] = {
        kind = "travel", id = action.id, label = action.short,
      }
    end
    if #cells == 0 then return end

    local scale = viewport.scale or 1
    local cellW, cellH, gap, columns = 36, 24, 2, math.min(4, #cells)
    local total = columns * cellW + (columns - 1) * gap
    local startX = math.floor((160 - total) / 2)
    local g = love.graphics
    g.push("all")
    g.origin()
    g.translate(viewport.gameX or 0, viewport.gameY or 0)
    g.scale(scale, scale)
    for i, cell in ipairs(cells) do
      local column = (i - 1) % columns
      local row = math.floor((i - 1) / columns)
      local x = startX + column * (cellW + gap)
      local y = row * (cellH + gap)
      g.setColor(1, 1, 1, 0.88)
      g.rectangle("fill", x, y, cellW, cellH)
      g.setColor(0, 0, 0, 1)
      g.rectangle("line", x, y, cellW, cellH)
      local text = #cell.label > 4 and cell.label:sub(1, 4) or cell.label
      Font.draw(text, x + math.floor((cellW - Font.width(text)) / 2), y + 8)
      runtime.rects[#runtime.rects + 1] = {
        kind = cell.kind, id = cell.id,
        x = (viewport.gameX or 0) + x * scale,
        y = (viewport.gameY or 0) + y * scale,
        w = cellW * scale, h = cellH * scale,
      }
    end
    g.pop()
  end)

  -- Native touch controls have already declined this pointer. Let downstream
  -- pointer mods go first as well; the suite only claims its own visible cell.
  mod.hooks:wrap("input.pointer", function(next, game, ev)
    if next(game, ev) then return true end
    if ev.phase == "pressed" then
      for _, rect in ipairs(runtime.rects) do
        if inside(rect, ev.x, ev.y) then
          runtime.touches[ev.id] = rect
          if rect.kind == "menu" then
            shared.activateMenuItem(game, rect.id)
          elseif rect.kind == "autofire" then
            local cfg = af.config()
            af.start(game, cfg.target, "touch:" .. tostring(ev.id))
          else
            travel.run(game, rect.id)
          end
          return true
        end
      end
    elseif ev.phase == "released" then
      local rect = runtime.touches[ev.id]
      if rect then
        runtime.touches[ev.id] = nil
        if rect.kind == "autofire" and af.config().mode == "hold" then af.stop() end
        return true
      end
    end
    return false
  end)

  suite.register("touchscreen", {
    id = "autofire", label = "AUTOFIRE",
    rows = function()
      return {
        { id = "touchAfEnabled", label = "TOUCH BUTTON",
          value = function() return config().autofire and "ON" or "OFF" end,
          step = function()
            local cfg = config(); cfg.autofire = not cfg.autofire; save(cfg); return true
          end,
          unassign = function()
            local cfg = config(); cfg.autofire = false; save(cfg); af.stop(); return true
          end },
        { id = "touchAfMode", label = "MODE",
          value = function() return af.config().mode:upper() end,
          step = function(_, dir)
            local cfg = af.config()
            cfg.mode = shared.cycle({ "toggle", "hold" }, cfg.mode, dir)
            af.save(cfg); af.stop(); return true
          end },
        { id = "touchAfSpeed", label = "SPEED",
          value = function() return af.speeds[af.config().speed].label end,
          step = function(_, dir)
            local cfg = af.config()
            cfg.speed = ((cfg.speed - 1 + (dir or 1)) % #af.speeds) + 1
            af.save(cfg); return true
          end },
        { id = "touchAfTarget", label = "BUTTON",
          value = function() return af.labels[af.config().target] end,
          step = function(_, dir)
            local cfg = af.config()
            cfg.target = shared.cycle(af.targets, cfg.target, dir)
            af.save(cfg); af.stop(); return true
          end },
      }
    end,
  })

  suite.register("touchscreen", {
    id = "menu_shortcuts", label = "MENU SHORTCUTS",
    rows = function(game)
      shared.refreshStartMenuItems(game)
      local rows = {
        { id = "touchShortcuts", label = "SHORTCUT BAR",
          value = function() return config().shortcuts and "ON" or "OFF" end,
          step = function()
            local cfg = config(); cfg.shortcuts = not cfg.shortcuts; save(cfg); return true
          end,
          unassign = function()
            local cfg = config(); cfg.shortcuts = false; save(cfg); return true
          end },
      }
      local ids, labels = menuChoices(game)
      for i = 1, 3 do
        local slot = i
        rows[#rows + 1] = {
          id = "touchSlot" .. i, label = "SLOT " .. i,
          value = function() return labels[config().slots[slot] or "off"] or "OFF" end,
          step = function(_, dir)
            local cfg = config()
            local selected = shared.cycle(ids, cfg.slots[slot] or "off", dir)
            if selected ~= "off" then
              for other = 1, 3 do
                if other ~= slot and cfg.slots[other] == selected then
                  cfg.slots[other] = "off"
                end
              end
            end
            cfg.slots[slot] = selected
            save(cfg); return true
          end,
          unassign = function()
            local cfg = config()
            cfg.slots[slot] = "off"
            save(cfg)
            return true
          end,
        }
      end
      return rows
    end,
  })

  shared.registerStats(function()
    local cfg = config()
    local assigned, active = 0, 0
    for i = 1, 3 do
      if cfg.slots[i] and cfg.slots[i] ~= "off" then
        assigned = assigned + 1
        if cfg.shortcuts then active = active + 1 end
      end
    end
    if cfg.autofire then active, assigned = active + 1, assigned + 1 end
    return active, assigned
  end)

  shared.registerReset(function()
    local cfg = config()
    cfg.autofire = false
    cfg.shortcuts = false
    for i = 1, 3 do cfg.slots[i] = "off" end
    save(cfg)
    af.stop()
  end)

  shared.touch = { config = config }
end
