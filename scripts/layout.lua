-- Turns a refined route into an ordered list of belt and underground entities
-- and rejects routes that overlap themselves. Pure: no game API.
local cells = require("scripts.cells")
local DX, DY = cells.DX, cells.DY

local layout = {}

-- Tile sets are two-level tables, set[x][y], so every number key stays small:
-- the game hashes a number key by its top 31 mantissa bits, and one packed
-- key per tile would put a whole column of tiles in one hash chain.
local function put(set, x, y, value)
  local col = set[x]
  if not col then col = {}; set[x] = col end
  col[y] = value
end

local function get(set, x, y)
  local col = set[x]
  return col and col[y]
end

-- True when a tile set from layout.tiles holds (x, y).
function layout.has(set, x, y)
  local col = set[x]
  return type(col) == "table" and col[y] == true
end

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
    if get(seen, e.x, e.y) then return "loop" end
    put(seen, e.x, e.y, true)
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
      local dx, dy = e.x - a.x, e.y - a.y
      local ahead = dx * DX[a.d] + dy * DY[a.d]
      if ahead < 1 or math.abs(dx * DY[a.d] + dy * DX[a.d]) ~= 0 then return "loop" end
      for step = 1, ahead - 1 do
        put(span[axis], a.x + DX[a.d] * step, a.y + DY[a.d] * step, pair_count)
      end
      open = nil
    end
  end
  for i, e in ipairs(entities) do
    if e.kind ~= "belt" then
      local owner = get(span[e.d % 2], e.x, e.y)
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

-- The set of tiles the entities stand on, for layout.has.
function layout.tiles(entities)
  local set = {}
  for _, e in ipairs(entities) do put(set, e.x, e.y, true) end
  return set
end

return layout
