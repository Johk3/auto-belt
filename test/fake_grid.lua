-- Builds cell readers from ASCII maps for the routing tests.
local cells = require("scripts.cells")
local refine = require("scripts.refine")
local grid = require("scripts.grid")
local bor, band = bit32.bor, bit32.band
local fake = {}

local BASE = {
  ["."] = 0, ["#"] = cells.BLOCKED, X = cells.BLOCKED + cells.WALL,
  ["-"] = cells.BLOCKED, ["|"] = cells.BLOCKED, M = cells.BLOCKED,
  h = cells.BLOCKED + cells.UG_H, v = cells.BLOCKED + cells.UG_V, ["="] = cells.UG_H,
}

function fake.grid(rows, ox, oy)
  ox, oy = ox or 0, oy or 0
  local h, w = #rows, #rows[1]
  local m = {}
  local function at(x, y) return rows[y + 1] and rows[y + 1]:sub(x + 1, x + 1) or "" end
  local function add(x, y, bit)
    if x >= 0 and y >= 0 and x < w and y < h then m[y * w + x] = bor(m[y * w + x], bit) end
  end
  for y = 0, h - 1 do for x = 0, w - 1 do
    local c = at(x, y)
    m[y * w + x] = assert(BASE[c], "unknown map char " .. c)
  end end
  for y = 0, h - 1 do for x = 0, w - 1 do
    local c = at(x, y)
    if c == "-" or c == "h" then add(x, y - 1, cells.HUG_H); add(x, y + 1, cells.HUG_H) end
    if c == "|" or c == "v" then add(x - 1, y, cells.HUG_V); add(x + 1, y, cells.HUG_V) end
    if c == "M" then for dy = -1, 1 do for dx = -1, 1 do add(x + dx, y + dy, cells.CROWDED) end end end
  end end
  local function blocked_run(x, y, dx, dy)
    local n = 1
    for s = -1, 1, 2 do
      local tx, ty = x + s * dx, y + s * dy
      while tx >= 0 and ty >= 0 and tx < w and ty < h and band(m[ty * w + tx], cells.BLOCKED) ~= 0 do
        n = n + 1; tx, ty = tx + s * dx, ty + s * dy
      end
    end
    return n
  end
  for y = 0, h - 1 do for x = 0, w - 1 do
    local v = m[y * w + x]
    if band(v, cells.BLOCKED) ~= 0 and band(v, cells.WALL) == 0
      and (blocked_run(x, y, 1, 0) <= 9 or blocked_run(x, y, 0, 1) <= 9) then
      m[y * w + x] = bor(v, cells.THIN)
    end
  end end
  return function(x, y)
    local lx, ly = x - ox, y - oy
    if lx < 0 or ly < 0 or lx >= w or ly >= h then return cells.BLOCKED + cells.WALL end
    return m[ly * w + lx]
  end
end

function fake.solve(cell, params, budget)
  local search = refine.new(params)
  while true do
    local status = refine.step(search, budget or 1e9, cell)
    if status == "need" then error("fake grid reported a missing chunk") end
    if status ~= "running" then return search end
  end
end

function fake.turns(states)
  local n = 0
  for i = 1, #states - 1 do
    local a, b = states[i], states[i + 1]
    if math.abs(a.x - b.x) + math.abs(a.y - b.y) == 1 and a.d ~= b.d then n = n + 1 end
  end
  return n
end

function fake.box(rows, ox, oy)
  ox, oy = ox or 0, oy or 0
  return {x1 = ox, y1 = oy, x2 = ox + #rows[1] - 1, y2 = oy + #rows - 1}
end

function fake.lazy(cell)
  local loaded = {[cells.chunk_key(0, 0)] = true}
  local function lazy_cell(x, y)
    local cx, cy = cells.chunk_of(x, y)
    if not loaded[cells.chunk_key(cx, cy)] then return nil end
    return cell(x, y)
  end
  return lazy_cell, function(cx, cy) loaded[cells.chunk_key(cx, cy)] = true end
end

-- Stores chunk records for a map that starts at tile 0, 0, plus one ring of
-- chunks around it; tiles outside the rows are blocked walls.
function fake.records(rows, surface_index)
  local cell = fake.grid(rows)
  local last_cx, last_cy = math.floor((#rows[1] - 1) / 32), math.floor((#rows - 1) / 32)
  for cx = -1, last_cx + 1 do
    for cy = -1, last_cy + 1 do
      local out = {}
      for ly = 0, 31 do for lx = 0, 31 do
        out[#out + 1] = string.char(cell(cx * 32 + lx, cy * 32 + ly))
      end end
      grid.put(surface_index, cx, cy, table.concat(out))
    end
  end
end

return fake
