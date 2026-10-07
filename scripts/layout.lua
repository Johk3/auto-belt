-- Turns a refined route into an ordered list of belt and underground entities
-- and rejects routes that overlap themselves. Pure: no game API.
local cells = require("scripts.cells")
local DX, DY = cells.DX, cells.DY
local tile_key = cells.tile_key

local layout = {}

local function entity(name, kind, x, y, d)
  return {name = name, kind = kind, x = x, y = y, d = d}
end

local function add_step(out, a, b, tier)
  if math.abs(b.x - a.x) + math.abs(b.y - a.y) <= 1 then
    out[#out + 1] = entity(tier.belt, "belt", a.x, a.y, b.d)
  else
    out[#out + 1] = entity(tier.underground, "input", a.x, a.y, a.d)
    out[#out + 1] = entity(tier.underground, "output", b.x - DX[a.d], b.y - DY[a.d], a.d)
  end
end

-- nil when valid, "loop" when two entities share a tile or an underground end
-- lies strictly inside another pair's span on the same axis.
function layout.validate(entities)
  local seen = {}
  for _, e in ipairs(entities) do
    local key = tile_key(e.x, e.y)
    if seen[key] then return "loop" end
    seen[key] = true
  end
  local span = {[0] = {}, [1] = {}}
  local pair_of, pair_count, open = {}, 0, nil
  for i, e in ipairs(entities) do
    if e.kind == "input" then
      open = i
    elseif e.kind == "output" and open then
      pair_count = pair_count + 1
      local a = entities[open]
      pair_of[open], pair_of[i] = pair_count, pair_count
      local axis = a.d % 2
      local x, y = a.x + DX[a.d], a.y + DY[a.d]
      while x ~= e.x or y ~= e.y do
        span[axis][tile_key(x, y)] = pair_count
        x, y = x + DX[a.d], y + DY[a.d]
      end
      open = nil
    end
  end
  for i, e in ipairs(entities) do
    if e.kind ~= "belt" then
      local owner = span[e.d % 2][tile_key(e.x, e.y)]
      if owner and owner ~= pair_of[i] then return "loop" end
    end
  end
  return nil
end

function layout.build(states, goal, tier)
  local out = {}
  for i = 1, #states - 1 do add_step(out, states[i], states[i + 1], tier) end
  if goal.place and #states > 0 then
    local last = states[#states]
    out[#out + 1] = entity(tier.belt, "belt", last.x, last.y, last.d)
  end
  if layout.validate(out) then return nil, "loop" end
  return out
end

function layout.tiles(entities)
  local set = {}
  for _, e in ipairs(entities) do set[tile_key(e.x, e.y)] = true end
  return set
end

return layout
