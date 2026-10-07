-- Draws a planned route and places it as ghosts or real entities in batches.
-- The only module besides endpoints that converts to defines.direction values.
local builder = {}

local GHOST_COLOR = {r = 0.3, g = 0.6, b = 1}
local FREE_COLOR = {r = 0.3, g = 1, b = 0.4}
local DX = {[0] = 0, 1, 0, -1}
local DY = {[0] = -1, 0, 1, 0}

local function direction(d)
  return ({[0] = defines.direction.north, defines.direction.east,
    defines.direction.south, defines.direction.west})[d]
end

-- Route preview for job.player_index only; render objects go to job.renders.
function builder.preview(job)
  if not job.player_index or not job.entities or not game.get_player(job.player_index) then return end
  local surface = game.get_surface(job.surface_index)
  if not surface then return end
  local color = job.placement == "free" and FREE_COLOR or GHOST_COLOR
  local players = {job.player_index}
  local renders = job.renders or {}
  job.renders = renders
  local list = job.entities

  local function line(a, b, extra)
    local p = {color = color, width = 3, surface = surface, players = players,
      from = {a.x + 0.5 - (DX[a.d] * 0.5), a.y + 0.5 - (DY[a.d] * 0.5)},
      to = {b.x + 0.5 + (DX[b.d] * 0.5), b.y + 0.5 + (DY[b.d] * 0.5)}}
    for k, v in pairs(extra or {}) do p[k] = v end
    renders[#renders + 1] = rendering.draw_line(p)
  end
  local function sprite(name, e, scale, orientation)
    renders[#renders + 1] = rendering.draw_sprite{sprite = name, target = {e.x + 0.5, e.y + 0.5},
      x_scale = scale, y_scale = scale, orientation = orientation, surface = surface,
      players = players, tint = color}
  end

  local run_start
  local pending_input
  for i, e in ipairs(list) do
    local prev, nxt = list[i - 1], list[i + 1]
    if e.kind == "belt" then
      run_start = run_start or e
      if not (nxt and nxt.kind == "belt" and nxt.d == e.d) then
        line(run_start, e)
        run_start = nil
      end
    else
      run_start = nil
      sprite("item/" .. e.name, e, 0.5)
      if e.kind == "input" then
        pending_input = e
      elseif pending_input then
        local a, b = pending_input, e
        renders[#renders + 1] = rendering.draw_line{color = color, width = 3, surface = surface,
          players = players, dash_length = 0.3, gap_length = 0.3,
          from = {a.x + 0.5, a.y + 0.5}, to = {b.x + 0.5, b.y + 0.5}}
        pending_input = nil
      end
    end
    if i == #list or (prev and prev.d ~= e.d and e.kind == "belt") then
      sprite("utility/indication_arrow", e, 1, e.d / 4)
    end
  end
end

-- The one place render objects are destroyed.
function builder.clear(renders)
  for _, object in pairs(renders or {}) do
    if object.valid then object.destroy() end
  end
end

function builder.start(job)
  if job.placement == "free" and not settings.global["auto-belt-allow-free"].value then
    return nil, "auto-belt.free-disabled"
  end
  storage.builds = storage.builds or {}
  local starts = {}
  for i, s in ipairs(job.starts or {}) do starts[i] = {x = s.x, y = s.y, d = s.d} end
  local build = {
    id = job.id, surface_index = job.surface_index, force = job.force,
    player_index = job.player_index, placement = job.placement,
    entities = job.entities, next = 1, goal = job.goal, tier = job.tier,
    layout = job.layout, starts = starts,
  }
  storage.builds[build.id] = build
  if AUTO_BELT and AUTO_BELT.update_tick then AUTO_BELT.update_tick() end
  return build
end

-- Outputs are created with the flow direction like inputs; the engine pairs
-- an input and an output that share it. Ghost undergrounds take the same
-- `type` and keep it. Both raise the built event, so the cell cache drops the
-- chunks they land in.
function builder.place(surface, force, e, placement, player)
  local position = {e.x + 0.5, e.y + 0.5}
  local dir = direction(e.d)
  local kind = e.kind ~= "belt" and e.kind or nil
  local check = placement == "ghost" and defines.build_check_type.manual_ghost or defines.build_check_type.manual
  if not surface.can_place_entity{name = e.name, position = position, direction = dir, force = force, build_check_type = check} then
    return nil
  end
  if placement == "ghost" then
    return surface.create_entity{name = "entity-ghost", inner_name = e.name, position = position, direction = dir,
      force = force, player = player, type = kind, raise_built = true}
  end
  return surface.create_entity{name = e.name, position = position, direction = dir, force = force,
    player = player, type = kind, raise_built = true}
end

-- Places up to `count` entities; returns the status and how many were placed.
function builder.step(build, count)
  local surface = game.get_surface(build.surface_index)
  if not surface then
    build.blocked = {x = build.entities[build.next].x, y = build.entities[build.next].y}
    return "blocked", 0
  end
  local player = build.player_index and game.get_player(build.player_index) or nil
  local placed = 0
  while placed < count and build.next <= #build.entities do
    local e = build.entities[build.next]
    if not builder.place(surface, build.force, e, build.placement, player) then
      build.blocked = {x = e.x, y = e.y}
      return "blocked", placed
    end
    build.last = {x = e.x, y = e.y}
    build.next = build.next + 1
    placed = placed + 1
  end
  if build.next > #build.entities then return "done", placed end
  return "running", placed
end

return builder
