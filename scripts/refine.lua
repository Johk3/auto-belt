-- Weighted A* over (tile, heading) states inside a region. Pure: the map is
-- read only through cell(x, y), which returns a cells bit mask or nil when
-- the chunk is not read yet. All state is plain data so it can sit in storage.
local cells = require("scripts.cells")
local heap = require("scripts.heap")
local band = bit32.band
local floor, abs = math.floor, math.abs
local push, pop, peek = heap.push, heap.pop, heap.peek
local chunk_key = cells.chunk_key
local DX, DY = cells.DX, cells.DY
local BLOCKED, WALL, CROWDED = cells.BLOCKED, cells.WALL, cells.CROWDED
local HUG_H, HUG_V, UG_H, UG_V = cells.HUG_H, cells.HUG_V, cells.UG_H, cells.UG_V

local refine = {TILE = 10, TURN = 40, NO_HUG = 3, CROWDED = 8}
local TILE, TURN, NO_HUG, CROWDED_COST = refine.TILE, refine.TURN, refine.NO_HUG, refine.CROWDED
-- Pops of a state that is already closed, per unit of budget.
refine.STALE_PER_UNIT = 3
local H_SCALE = 4194304 -- f is the major key; h breaks ties toward the goal
-- State ids stay below ID_LIMIT (2^31). The game hashes a number key by its
-- top 31 mantissa bits, so larger keys that differ only in low bits share a
-- hash chain and every lookup slows down with the size of the search.
refine.ID_LIMIT = 2147483648

function refine.jump_cost(mode, k, free_gaps, span_gaps)
  if mode == "undergrounds" then return 25 + 4 * (k - 1) end
  return 30 + 10 * span_gaps + 60 * free_gaps
end

local function min_tile_cost(mode, maxd)
  local best = refine.TILE
  if mode == "undergrounds" then
    for k = 2, maxd do
      local per = refine.jump_cost(mode, k, 0, 0) / (k + 1)
      if per < best then best = per end
    end
  end
  return best
end

-- Search-local state ids: the tile's offset inside the search box, times four,
-- plus the heading. The box (origin s.x0, s.y0, s.w by s.h tiles) covers the
-- region, the starts and the goal, so every state the search can reach fits.
function refine.state_id(s, x, y, d)
  return ((x - s.x0) * s.h + (y - s.y0)) * 4 + d
end

function refine.decode(s, id)
  local d = id % 4
  local rest = (id - d) / 4
  local ly = rest % s.h
  return (rest - ly) / s.h + s.x0, ly + s.y0, d
end

-- Every state the search has reached sits in s.nodes, split into shards of
-- refine.SHARD ids (s.nodes[shard][low], low from 1), because a single table
-- that grows past about 2^19 entries stalls the game for a long time when it
-- resizes. One number per state holds its cost so far and the move it was
-- reached by: g * s.pack + move, where move = step * 4 + parent heading + 1 and
-- step is the tile distance from the parent (0 at a start). A closed state
-- stores the negated number.
refine.SHARD = 4096
local SHARD = refine.SHARD

local function move_code(step, pd) return step * 4 + pd + 1 end

-- The stored number of a state, or nil when the search has not reached it.
local function node(s, id)
  local low = id % SHARD
  local shard = s.nodes[(id - low) / SHARD]
  return shard and shard[low + 1]
end

-- Cost so far of the state at (x, y) heading d, or nil when not reached.
function refine.cost(s, x, y, d)
  local v = node(s, refine.state_id(s, x, y, d))
  if not v then return nil end
  if v < 0 then v = -v end
  return (v - v % s.pack) / s.pack
end

-- Calls fn(id) for every state the search has reached.
function refine.each_state(s, fn)
  for key, shard in pairs(s.nodes) do
    for low in pairs(shard) do fn(key * SHARD + low - 1) end
  end
end

-- Bounding box of the region, the starts and the goal.
local function bounds(p)
  local x1, y1, x2, y2 = p.goal.x, p.goal.y, p.goal.x, p.goal.y
  local function add(ax, ay, bx, by)
    if ax < x1 then x1 = ax end
    if ay < y1 then y1 = ay end
    if bx > x2 then x2 = bx end
    if by > y2 then y2 = by end
  end
  for _, st in ipairs(p.starts) do add(st.x, st.y, st.x, st.y) end
  local region = p.region
  if region.chunks then
    for key in pairs(region.chunks) do
      local cx, cy = cells.chunk_xy(key)
      add(cx * 32, cy * 32, cx * 32 + 31, cy * 32 + 31)
    end
  else
    add(region.x1, region.y1, region.x2, region.y2)
  end
  return x1, y1, x2, y2
end

-- Lower bound on the cost to the goal from (x, y) heading d. The turn term
-- depends on the heading, which keeps the bound consistent: a forward move
-- toward the goal never drops it by more than that move costs. hx and hy are
-- the headings that close the gap on each axis (nil when it is closed).
local function heuristic(s, x, y, d)
  local goal = s.goal
  local ddx, ddy = goal.x - x, goal.y - y
  local hx = ddx > 0 and 1 or (ddx < 0 and 3 or nil)
  local hy = ddy > 0 and 2 or (ddy < 0 and 0 or nil)
  local t = 0
  if hx and hy then
    t = (d == hx or d == hy) and 1 or 2
  elseif hx or hy then
    local want = hx or hy
    if d == want then t = 0 elseif d == (want + 2) % 4 then t = 2 else t = 1 end
  end
  return floor((abs(ddx) + abs(ddy)) * s.hmin) + t * TURN
end

local function is_goal(s, x, y, d)
  local goal = s.goal
  return x == goal.x and y == goal.y and goal.headings[d] == true
end

-- Records a cheaper way to (x, y, d) with cost g, reached by move code `move`.
local function relax(s, x, y, d, g, move)
  local id = ((x - s.x0) * s.h + (y - s.y0)) * 4 + d
  local low = id % SHARD
  local key = (id - low) / SHARD
  local nodes = s.nodes
  local shard = nodes[key]
  if not shard then
    shard = {}
    nodes[key] = shard
  else
    local old = shard[low + 1]
    if old then
      if old < 0 then return end
      local pack = s.pack
      if (old - old % pack) / pack <= g then return end
    end
  end
  shard[low + 1] = g * s.pack + move
  local h = heuristic(s, x, y, d)
  push(s.open, (g + floor(h * s.weight10 / 10)) * H_SCALE + h, id)
end

local function reconstruct(s, id)
  local back = {}
  local pack = s.pack
  while true do
    local x, y, d = refine.decode(s, id)
    back[#back + 1] = {x = x, y = y, d = d}
    local v = node(s, id)
    if v < 0 then v = -v end
    local code = v % pack - 1
    local pd = code % 4
    local step = (code - pd) / 4
    if step == 0 then break end
    id = refine.state_id(s, x - step * DX[d], y - step * DY[d], pd)
  end
  local out = {}
  for i = #back, 1, -1 do out[#out + 1] = back[i] end
  return out
end

function refine.new(p)
  local s = {
    goal = p.goal, region = p.region, mode = p.mode or "belts", maxd = p.max_distance or 0,
    weight10 = p.weight10 or 12,
    open = heap.new(), nodes = {},
    status = "running", expansions = 0, stale_pops = 0,
  }
  s.pack = move_code(s.maxd + 1, 3) + 1
  s.hmin = min_tile_cost(s.mode, s.maxd)
  local x1, y1, x2, y2 = bounds(p)
  s.x0, s.y0, s.w, s.h = x1, y1, x2 - x1 + 1, y2 - y1 + 1
  if s.w * s.h * 4 > refine.ID_LIMIT then
    -- Too large to number; the job reports a search limit.
    s.status, s.limit = "failed", true
    return s
  end
  for _, st in ipairs(p.starts) do
    if is_goal(s, st.x, st.y, st.d) then
      s.status, s.result = "found", {{x = st.x, y = st.y, d = st.d}}
      return s
    end
    relax(s, st.x, st.y, st.d, 0, move_code(0, 0))
  end
  return s
end

-- Candidate moves of the state being expanded. Filled and read within one
-- expansion, so nothing in them outlives a step.
local CX, CY, CD, CG, CM = {}, {}, {}, {}, {}

-- True when (x, y) lies in the search region.
local function inside(region, chunks, x, y)
  if chunks then return chunks[chunk_key(floor(x / 32), floor(y / 32))] == true end
  return x >= region.x1 and x <= region.x2 and y >= region.y1 and y <= region.y2
end

-- Surcharge of a belt tile with mask `mask` crossed heading d.
local function surcharge(mask, d)
  local cost = 0
  if band(mask, d % 2 == 1 and HUG_H or HUG_V) == 0 then cost = NO_HUG end
  if band(mask, CROWDED) ~= 0 then cost = cost + CROWDED_COST end
  return cost
end

-- Expands states until `budget` units are used. An expansion costs one unit;
-- every refine.STALE_PER_UNIT pops of an already closed state cost one more.
function refine.step(s, budget, cell)
  s.need = nil
  if s.status ~= "running" then return s.status, 0 end
  local used = 0
  local open, nodes, region = s.open, s.nodes, s.region
  local chunks = region.chunks
  local pack, maxd, goal = s.pack, s.maxd, s.goal
  local gx, gy, gh = goal.x, goal.y, goal.headings
  local x0, y0, sh = s.x0, s.y0, s.h
  local stale_cost = refine.STALE_PER_UNIT
  while used < budget do
    local _, id = peek(open)
    if not id then s.status = "failed"; return "failed", used end
    local low = id % SHARD
    local shard = nodes[(id - low) / SHARD]
    local v = shard[low + 1]
    if v < 0 then
      pop(open)
      local stale = (s.stale_pops or 0) + 1
      s.stale_pops = stale
      if stale % stale_cost == 0 then used = used + 1 end
    else
      local d = id % 4
      local rest = (id - d) / 4
      local ly = rest % sh
      local x, y = (rest - ly) / sh + x0, ly + y0
      if x == gx and y == gy and gh[d] == true then
        s.status, s.result = "found", reconstruct(s, id)
        return "found", used
      end
      local mask = cell(x, y)
      if mask == nil then s.need = {x = x, y = y}; return "need", used end
      local g = (v - v % pack) / pack
      local n = 0
      for turn = 0, 2 do
        local nd = turn == 0 and d or (turn == 1 and (d + 3) % 4 or (d + 1) % 4)
        local nx, ny = x + DX[nd], y + DY[nd]
        local add = false
        if nx == gx and ny == gy and gh[nd] == true then
          add = true
        elseif inside(region, chunks, nx, ny) then
          local m = cell(nx, ny)
          if m == nil then s.need = {x = nx, y = ny}; return "need", used end
          add = band(m, BLOCKED) == 0
        end
        if add then
          n = n + 1
          CX[n], CY[n], CD[n], CM[n] = nx, ny, nd, move_code(1, d)
          CG[n] = g + TILE + surcharge(mask, nd) + (nd ~= d and TURN or 0)
        end
      end
      if maxd >= 2 then
        local ug = d % 2 == 1 and UG_H or UG_V
        if band(mask, ug) == 0 then
          local free_gaps, span_gaps = 0, 0
          local ddx, ddy = DX[d], DY[d]
          for k = 1, maxd do
            local tx, ty = x + k * ddx, y + k * ddy
            if not inside(region, chunks, tx, ty) then break end
            local m = cell(tx, ty)
            if m == nil then s.need = {x = tx, y = ty}; return "need", used end
            if band(m, WALL) ~= 0 or band(m, ug) ~= 0 then break end
            if k >= 2 and band(m, BLOCKED) == 0 then
              local lx, ly2 = tx + ddx, ty + ddy
              local add = false
              if lx == gx and ly2 == gy and gh[d] == true then
                add = true
              elseif inside(region, chunks, lx, ly2) then
                local ml = cell(lx, ly2)
                if ml == nil then s.need = {x = lx, y = ly2}; return "need", used end
                add = band(ml, BLOCKED) == 0
              end
              if add then
                n = n + 1
                CX[n], CY[n], CD[n], CM[n] = lx, ly2, d, move_code(k + 1, d)
                CG[n] = g + refine.jump_cost(s.mode, k, free_gaps, span_gaps) + surcharge(mask, d) + surcharge(m, d)
              end
            end
            if band(m, BLOCKED) ~= 0 then span_gaps = span_gaps + 1 else free_gaps = free_gaps + 1 end
          end
        end
      end
      pop(open)
      shard[low + 1] = -v
      s.expansions = s.expansions + 1
      used = used + 1
      local h = heuristic(s, x, y, d)
      local closest = s.closest
      if not closest then
        s.closest = {x = x, y = y, h = h}
      elseif h < closest.h then
        closest.x, closest.y, closest.h = x, y, h
      end
      for i = 1, n do relax(s, CX[i], CY[i], CD[i], CG[i], CM[i]) end
    end
  end
  return "running", used
end

return refine
