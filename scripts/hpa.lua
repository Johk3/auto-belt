-- A* over the region graph: nodes are (chunk, region label), edges join
-- regions that touch across a chunk border. Pure: chunk records come through
-- region_of(cx, cy), which returns nil while the chunk is not read yet. All
-- state is plain data so it can sit in storage.
local cells = require("scripts.cells")
local regions = require("scripts.regions")
local heap = require("scripts.heap")

local hpa = {TILE = 10, MIN_EDGE = 10}
local H_SCALE = 4194304 -- f is the major key; h breaks ties toward the goal
local SIDE = {{0, -1}, {1, 0}, {0, 1}, {-1, 0}}

-- Node ids are local to the search and stay below 2^31: the game hashes a
-- number key by its top 31 mantissa bits, so larger keys that differ only in
-- low bits share a hash chain. Chunks are numbered relative to the start
-- chunk; a chunk more than hpa.RANGE chunks away on either axis is outside
-- the search.
hpa.RANGE = 1023
local SPAN = 2 * hpa.RANGE + 1

-- Local index of a chunk, or nil when it lies outside the search range.
local function chunk_index(s, cx, cy)
  local lx, ly = cx - s.ocx + hpa.RANGE, cy - s.ocy + hpa.RANGE
  if lx < 0 or ly < 0 or lx >= SPAN or ly >= SPAN then return nil end
  return lx * SPAN + ly
end

local function node_id(s, cx, cy, label)
  local index = chunk_index(s, cx, cy)
  return index and index * 256 + label
end

local function split(s, id)
  local label = id % 256
  local index = (id - label) / 256
  local ly = index % SPAN
  return (index - ly) / SPAN - hpa.RANGE + s.ocx, ly - hpa.RANGE + s.ocy, label
end

local function centre(rec, cx, cy, label)
  local c = rec.centroids[label] or {x = 16, y = 16}
  return cx * 32 + c.x, cy * 32 + c.y
end

local function heuristic(s, id, rec)
  local cx, cy, label = split(s, id)
  local x, y = centre(rec, cx, cy, label)
  return (math.abs(x - s.goal_point.x) + math.abs(y - s.goal_point.y)) * hpa.TILE
end

function hpa.new(p)
  local ocx, ocy = cells.chunk_of(p.start.x, p.start.y)
  return {
    start = p.start, goals = p.goals, goal_point = p.goal_point, ocx = ocx, ocy = ocy,
    status = "running", expansions = 0, ready = false,
    open = heap.new(), g = {}, parent = {}, closed = {}, goal_set = {},
  }
end

-- Resolves the start and goal tiles to nodes. Returns true when done, or
-- sets s.need and returns false.
local function init(s, region_of)
  local goal_set, any = {}, false
  local function node(t)
    local cx, cy = cells.chunk_of(t.x, t.y)
    if not chunk_index(s, cx, cy) then s.limit = true; return nil end
    local rec = region_of(cx, cy)
    if not rec then s.need = {cx = cx, cy = cy}; return nil, true end
    local label = regions.label(rec, t.x - cx * 32, t.y - cy * 32)
    if label == 0 then return nil end
    return node_id(s, cx, cy, label), false, rec
  end
  local sid, missing, srec = node(s.start)
  if missing then return false end
  for _, t in ipairs(s.goals) do
    local gid, miss = node(t)
    if miss then return false end
    if gid then goal_set[gid] = true; any = true end
  end
  s.need = nil
  s.ready = true
  if not sid or not any then s.status = "failed"; return true end
  s.limit = nil
  s.goal_set = goal_set
  s.g[sid] = 0
  s.parent[sid] = -1
  local h = heuristic(s, sid, srec)
  heap.push(s.open, h * H_SCALE + h, sid)
  return true
end

local function reconstruct(s, id)
  local back = {}
  while id ~= -1 do
    local cx, cy = split(s, id)
    local last = back[#back]
    if not last or last.cx ~= cx or last.cy ~= cy then back[#back + 1] = {cx = cx, cy = cy} end
    id = s.parent[id]
  end
  local out = {}
  for i = #back, 1, -1 do out[#out + 1] = back[i] end
  return out
end

-- Neighbour nodes of (cx, cy, label): {id, cx, cy, label, rec}, or nil and a
-- missing chunk when a neighbour chunk is not read yet. Chunks outside the
-- search range are left out.
local function neighbours(s, cx, cy, label, rec, region_of)
  local out = {}
  for d = 1, 4 do
    local nx, ny = cx + SIDE[d][1], cy + SIDE[d][2]
    if chunk_index(s, nx, ny) then
      local nrec = region_of(nx, ny)
      if not nrec then return nil, {cx = nx, cy = ny} end
      local seen = {}
      for i = 0, 31 do
        local ax, ay, bx, by
        if d == 1 then ax, ay, bx, by = i, 0, i, 31
        elseif d == 2 then ax, ay, bx, by = 31, i, 0, i
        elseif d == 3 then ax, ay, bx, by = i, 31, i, 0
        else ax, ay, bx, by = 0, i, 31, i end
        if regions.label(rec, ax, ay) == label then
          local other = regions.label(nrec, bx, by)
          if other > 0 and not seen[other] then
            seen[other] = true
            out[#out + 1] = {id = node_id(s, nx, ny, other), cx = nx, cy = ny, label = other, rec = nrec}
          end
        end
      end
    end
  end
  return out
end

function hpa.step(s, budget, region_of)
  s.need = nil
  if s.status ~= "running" then return s.status, 0 end
  if not s.ready then
    if not init(s, region_of) then return "need", 0 end
    if s.status ~= "running" then return s.status, 0 end
  end
  local used = 0
  while used < budget do
    local _, id = heap.peek(s.open)
    if not id then s.status = "failed"; return "failed", used end
    if s.closed[id] then
      heap.pop(s.open)
    else
      if s.goal_set[id] then
        s.status, s.chunks = "found", reconstruct(s, id)
        return "found", used
      end
      local cx, cy, label = split(s, id)
      local rec = region_of(cx, cy)
      if not rec then s.need = {cx = cx, cy = cy}; return "need", used end
      local list, missing = neighbours(s, cx, cy, label, rec, region_of)
      if not list then s.need = missing; return "need", used end
      heap.pop(s.open)
      s.closed[id] = true
      s.expansions = s.expansions + 1
      used = used + 1
      local x, y = centre(rec, cx, cy, label)
      local g = s.g[id]
      for _, nb in ipairs(list) do
        if not s.closed[nb.id] then
          local nx, ny = centre(nb.rec, nb.cx, nb.cy, nb.label)
          local edge = math.max(hpa.MIN_EDGE, (math.abs(nx - x) + math.abs(ny - y)) * hpa.TILE)
          local ng = g + edge
          local old = s.g[nb.id]
          if not old or ng < old then
            s.g[nb.id] = ng
            s.parent[nb.id] = id
            local h = heuristic(s, nb.id, nb.rec)
            heap.push(s.open, (ng + h) * H_SCALE + h, nb.id)
          end
        end
      end
    end
  end
  return "running", used
end

-- Every chunk within ring chunks (Chebyshev) of a path chunk.
function hpa.corridor(chunks, ring)
  local set = {}
  for _, c in ipairs(chunks) do
    for dx = -ring, ring do for dy = -ring, ring do
      set[cells.chunk_key(c.cx + dx, c.cy + dy)] = true
    end end
  end
  return set
end

return hpa
