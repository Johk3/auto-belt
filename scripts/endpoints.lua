-- Reads the clicked tiles of a route: where it may start and where it may end.
-- The only module besides builder that converts to defines.direction values.
local cells = require("scripts.cells")
local grid = require("scripts.grid")
local tiers = require("scripts.tiers")

local endpoints = {}

local DX, DY = cells.DX, cells.DY
local TYPES = {"transport-belt", "underground-belt", "splitter"}
local ALL = {[0] = true, [1] = true, [2] = true, [3] = true}
local floor = math.floor

local function tile_area(x, y)
  return {{x + 0.1, y + 0.1}, {x + 0.9, y + 0.9}}
end

-- Belt, underground or splitter (real or ghost) on a tile, or nil.
local function find(surface, x, y)
  local area = tile_area(x, y)
  local found = surface.find_entities_filtered{area = area, type = TYPES}[1]
  if found then return found, false end
  found = surface.find_entities_filtered{area = area, ghost_type = TYPES}[1]
  if found then return found, true end
end

local function is_free(surface, x, y)
  return bit32.band(grid.ensure(surface, x, y), cells.BLOCKED) == 0
end

local function info(entity, ghost)
  if ghost then
    return entity.ghost_type, entity.ghost_prototype
  end
  return entity.type, entity.prototype
end

local function direction_of(entity) return floor(entity.direction / 4) % 4 end

local function tier_of(prototype, fallback_name)
  return tiers.for_speed(prototype.belt_speed) or tiers.get(fallback_name)
end

-- Tile of the splitter half nearest the click.
local function half_tile(entity, position)
  local d = direction_of(entity)
  local p = entity.position
  if d % 2 == 0 then
    local hx = position.x < p.x and p.x - 0.5 or p.x + 0.5
    return floor(hx), floor(p.y)
  end
  local hy = position.y < p.y and p.y - 0.5 or p.y + 0.5
  return floor(p.x), floor(hy)
end

-- Start on the tile ahead of an output tile at (x, y) facing d.
local function start_ahead(surface, x, y, d, tier)
  local ax, ay = x + DX[d], y + DY[d]
  if find(surface, ax, ay) then return {error = "auto-belt.start-connected"} end
  if not is_free(surface, ax, ay) then return {error = "auto-belt.start-blocked"} end
  return {starts = {{x = ax, y = ay, d = d}}, tier = tier}
end

function endpoints.start(surface, position, fallback_tier_name)
  local x, y = floor(position.x), floor(position.y)
  local entity, ghost = find(surface, x, y)
  if not entity then
    if not is_free(surface, x, y) then return {error = "auto-belt.start-blocked"} end
    local starts = {}
    for d = 0, 3 do starts[#starts + 1] = {x = x, y = y, d = d} end
    return {starts = starts, tier = tiers.get(fallback_tier_name)}
  end
  local kind, prototype = info(entity, ghost)
  local d = direction_of(entity)
  local tier = tier_of(prototype, fallback_tier_name)
  if kind == "underground-belt" then
    if entity.belt_to_ground_type ~= "output" then return {error = "auto-belt.start-not-output"} end
  elseif kind == "splitter" then
    x, y = half_tile(entity, position)
  end
  return start_ahead(surface, x, y, d, tier)
end

function endpoints.goal(surface, position)
  local x, y = floor(position.x), floor(position.y)
  local entity, ghost = find(surface, x, y)
  if not entity then
    if not is_free(surface, x, y) then return {error = "auto-belt.end-blocked"} end
    return {goal = {x = x, y = y, headings = ALL, place = true}}
  end
  local kind = info(entity, ghost)
  local e = direction_of(entity)
  if kind == "underground-belt" then
    if entity.belt_to_ground_type ~= "input" then return {error = "auto-belt.end-not-input"} end
    return {goal = {x = x, y = y, headings = {[e] = true}, place = false}}
  elseif kind == "splitter" then
    x, y = half_tile(entity, position)
    return {goal = {x = x, y = y, headings = {[e] = true}, place = false}}
  end
  if not ghost and entity.belt_shape ~= "straight" then return {error = "auto-belt.end-no-input"} end
  local headings, any = {}, false
  for _, h in ipairs({e, cells.left(e), cells.right(e)}) do
    if is_free(surface, x - DX[h], y - DY[h]) then headings[h] = true; any = true end
  end
  if not any then return {error = "auto-belt.end-no-input"} end
  return {goal = {x = x, y = y, headings = headings, place = false}}
end

return endpoints
