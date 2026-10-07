-- Weighted A* over (tile, heading) states inside a region. Pure: the map is
-- read only through cell(x, y), which returns a cells bit mask or nil when
-- the chunk is not read yet. All state is plain data so it can sit in storage.
local cells = require("scripts.cells")
local heap = require("scripts.heap")
local band = bit32.band
local DX, DY = cells.DX, cells.DY
local BLOCKED, WALL, CROWDED = cells.BLOCKED, cells.WALL, cells.CROWDED

local refine = {TILE = 10, TURN = 40, NO_HUG = 3, CROWDED = 8}
local H_SCALE = 4194304 -- f is the major key; h breaks ties toward the goal


local function surcharge(mask, d)
  local cost = 0
  if band(mask, cells.hug_bit(d)) == 0 then cost = cost + refine.NO_HUG end
  if band(mask, CROWDED) ~= 0 then cost = cost + refine.CROWDED end
  return cost
end

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

function refine.in_region(region, x, y)
  if region.chunks then
    return region.chunks[cells.chunk_key(math.floor(x / 32), math.floor(y / 32))] == true
  end
  return x >= region.x1 and x <= region.x2 and y >= region.y1 and y <= region.y2
end

-- Lower bound on the cost to the goal from (x, y) heading d. The turn term
-- depends on the heading, which keeps the bound consistent: a forward move
-- toward the goal never drops it by more than that move costs.
local function heuristic(s, x, y, d)
  local ddx, ddy = s.goal.x - x, s.goal.y - y
  local need, cnt = {}, 0
  if ddx > 0 then need[1] = true; cnt = cnt + 1 elseif ddx < 0 then need[3] = true; cnt = cnt + 1 end
  if ddy > 0 then need[2] = true; cnt = cnt + 1 elseif ddy < 0 then need[0] = true; cnt = cnt + 1 end
  local t = 0
  if cnt == 1 then
    if need[d] then t = 0
    elseif need[(d + 2) % 4] then t = 2
    else t = 1 end
  elseif cnt == 2 then
    t = need[d] and 1 or 2
  end
  return math.floor((math.abs(ddx) + math.abs(ddy)) * s.hmin) + t * refine.TURN
end

local function is_goal(s, x, y, d)
  return x == s.goal.x and y == s.goal.y and s.goal.headings[d] == true
end

local function relax(s, x, y, d, g, parent)
  local id = cells.state_id(x, y, d)
  local old = s.g[id]
  if (old and old <= g) or s.closed[id] then return end
  s.g[id] = g
  s.parent[id] = parent
  local h = heuristic(s, x, y, d)
  heap.push(s.open, (g + math.floor(h * s.weight10 / 10)) * H_SCALE + h, id)
end

local function reconstruct(s, id)
  local back = {}
  while id ~= -1 do
    local x, y, d = cells.decode(id)
    back[#back + 1] = {x = x, y = y, d = d}
    id = s.parent[id]
  end
  local out = {}
  for i = #back, 1, -1 do out[#out + 1] = back[i] end
  return out
end

function refine.new(p)
  local s = {
    goal = p.goal, region = p.region, mode = p.mode or "belts", maxd = p.max_distance or 0,
    weight10 = p.weight10 or 12,
    open = heap.new(), g = {}, parent = {}, closed = {},
    status = "running", expansions = 0,
  }
  s.hmin = min_tile_cost(s.mode, s.maxd)
  for _, st in ipairs(p.starts) do
    if is_goal(s, st.x, st.y, st.d) then
      s.status, s.result = "found", {{x = st.x, y = st.y, d = st.d}}
      return s
    end
    relax(s, st.x, st.y, st.d, 0, -1)
  end
  return s
end

function refine.step(s, budget, cell)
  if s.status ~= "running" then return s.status, 0 end
  local used = 0
  local cand, n = {}, 0
  local function add(x, y, d, g) n = n + 1; cand[n] = {x, y, d, g} end
  while used < budget do
    local _, id = heap.peek(s.open)
    if not id then s.status = "failed"; return "failed", used end
    if s.closed[id] then
      heap.pop(s.open)
    else
      local x, y, d = cells.decode(id)
      if is_goal(s, x, y, d) then
        s.status, s.result = "found", reconstruct(s, id)
        return "found", used
      end
      local mask = cell(x, y)
      if mask == nil then s.need = {x = x, y = y}; return "need", used end
      local g = s.g[id]
      n = 0
      for turn = 0, 2 do
        local nd = turn == 0 and d or (turn == 1 and cells.left(d) or cells.right(d))
        local nx, ny = x + DX[nd], y + DY[nd]
        local cost = g + refine.TILE + surcharge(mask, nd) + (nd ~= d and refine.TURN or 0)
        if is_goal(s, nx, ny, nd) then
          add(nx, ny, nd, cost)
        elseif refine.in_region(s.region, nx, ny) then
          local m = cell(nx, ny)
          if m == nil then s.need = {x = nx, y = ny}; return "need", used end
          if band(m, BLOCKED) == 0 then add(nx, ny, nd, cost) end
        end
      end
      if s.maxd >= 2 then
        local ug = cells.ug_bit(d)
        if band(mask, ug) == 0 then
          local free_gaps, span_gaps = 0, 0
          for k = 1, s.maxd do
            local tx, ty = x + k * DX[d], y + k * DY[d]
            if not refine.in_region(s.region, tx, ty) then break end
            local m = cell(tx, ty)
            if m == nil then s.need = {x = tx, y = ty}; return "need", used end
            if band(m, WALL) ~= 0 or band(m, ug) ~= 0 then break end
            if k >= 2 and band(m, BLOCKED) == 0 then
              local lx, ly = tx + DX[d], ty + DY[d]
              local cost = g + refine.jump_cost(s.mode, k, free_gaps, span_gaps) + surcharge(mask, d) + surcharge(m, d)
              if is_goal(s, lx, ly, d) then
                add(lx, ly, d, cost)
              elseif refine.in_region(s.region, lx, ly) then
                local ml = cell(lx, ly)
                if ml == nil then s.need = {x = lx, y = ly}; return "need", used end
                if band(ml, BLOCKED) == 0 then add(lx, ly, d, cost) end
              end
            end
            if band(m, BLOCKED) ~= 0 then span_gaps = span_gaps + 1 else free_gaps = free_gaps + 1 end
          end
        end
      end
      heap.pop(s.open)
      s.closed[id] = true
      s.expansions = s.expansions + 1
      used = used + 1
      local h = heuristic(s, x, y, d)
      if not s.closest or h < s.closest.h then s.closest = {x = x, y = y, h = h} end
      for i = 1, n do local c = cand[i]; relax(s, c[1], c[2], c[3], c[4], id) end
    end
  end
  return "running", used
end

return refine
