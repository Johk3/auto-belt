-- Chunk cell cache: one 1024-byte record of cell bits per cached 32x32 chunk,
-- kept in storage.grid.surfaces[surface_index][chunk_key].
local cells = require("scripts.cells")
local tiers = require("scripts.tiers")
local regions = require("scripts.regions")

local grid = {}

-- Budget units of one chunk read and one regions.build, measured against one
-- search unit (an expansion, or refine.STALE_PER_UNIT stale heap pops) with
-- test/bench.sh: a read of a chunk holding belt lines takes about 64 units, a
-- region build about 21.
grid.CHUNK_UNITS = 64
grid.REGION_UNITS = 21
grid.MARGIN = 11
grid.CAP = 2048

local floor, ceil, bor = math.floor, math.ceil, bit32.bor
local band = bit32.band
local char, unpack = string.char, table.unpack or unpack
local WALL, THIN = cells.WALL, cells.THIN

local IGNORE = {character = true, car = true, ["spider-vehicle"] = true, unit = true,
  ["item-entity"] = true, corpse = true, ["character-corpse"] = true}
local BELT = {["transport-belt"] = true, ["underground-belt"] = true, splitter = true,
  ["linked-belt"] = true, ["lane-splitter"] = true, loader = true, ["loader-1x1"] = true}
local CROWD = {["assembling-machine"] = true, furnace = true, inserter = true, loader = true,
  ["loader-1x1"] = true, ["mining-drill"] = true, lab = true, beacon = true, ["electric-pole"] = true,
  ["rocket-silo"] = true, ["agricultural-tower"] = true}
local WALL_TILES = {"out-of-map", "empty-space"}

local function surfaces_of(create)
  local g = storage.grid
  if not g then
    if not create then return nil end
    g = {surfaces = {}}
    storage.grid = g
  end
  if not g.surfaces then
    if not create then return nil end
    g.surfaces = {}
  end
  return g.surfaces
end

function grid.put(surface_index, cx, cy, cells_string)
  local surfaces = surfaces_of(true)
  local chunks = surfaces[surface_index]
  if not chunks then
    chunks = {}
    surfaces[surface_index] = chunks
  end
  local record = {cells = cells_string, touched = game.tick}
  chunks[cells.chunk_key(cx, cy)] = record
  return record
end

-- Returns cell(x, y): the byte for that tile, or nil when its chunk is not cached.
-- The closure remembers the last chunk, so build a fresh one per work step.
function grid.reader(surface_index)
  local last_key, last_cells
  local tick = game.tick
  local chunk_key = cells.chunk_key
  return function(x, y)
    local cx, cy = floor(x / 32), floor(y / 32)
    local key = chunk_key(cx, cy)
    if key ~= last_key then
      -- Resolved per chunk change, so a table created or replaced after the
      -- reader was made (first read on a surface, drop_surface) is seen.
      local surfaces = surfaces_of(false)
      local chunks = surfaces and surfaces[surface_index]
      local record = chunks and chunks[key]
      if not record then return nil end
      record.touched = tick
      last_key, last_cells = key, record.cells
    end
    return string.byte(last_cells, (y - cy * 32) * 32 + (x - cx * 32) + 1)
  end
end

function grid.invalidate_box(surface_index, x1, y1, x2, y2)
  local surfaces = surfaces_of(false)
  local chunks = surfaces and surfaces[surface_index]
  if not chunks then return end
  local m = grid.MARGIN
  local cx1, cy1 = cells.chunk_of(x1 - m, y1 - m)
  local cx2, cy2 = cells.chunk_of(x2 + m, y2 + m)
  for cx = cx1, cx2 do
    for cy = cy1, cy2 do
      chunks[cells.chunk_key(cx, cy)] = nil
    end
  end
end

function grid.on_entity(entity)
  if not (entity and entity.valid) then return end
  local surfaces = surfaces_of(false)
  local chunks = surfaces and surfaces[entity.surface_index]
  if not chunks or next(chunks) == nil then return end
  local box = entity.bounding_box
  grid.invalidate_box(entity.surface_index,
    floor(box.left_top.x), floor(box.left_top.y),
    floor(box.right_bottom.x), floor(box.right_bottom.y))
end

function grid.on_tiles(surface_index, tiles)
  local surfaces = surfaces_of(false)
  local chunks = surfaces and surfaces[surface_index]
  if not chunks or next(chunks) == nil or not tiles then return end
  for _, tile in pairs(tiles) do
    local p = tile.position
    grid.invalidate_box(surface_index, p.x, p.y, p.x, p.y)
  end
end

function grid.drop_surface(surface_index)
  local surfaces = surfaces_of(false)
  if surfaces then surfaces[surface_index] = nil end
end

-- Drops the oldest records once the cache is over grid.CAP. `keep` (the record
-- just stored) is never dropped, even when many records share one tick.
function grid.evict(keep)
  local surfaces = surfaces_of(false)
  if not surfaces then return end
  local total = 0
  for _, chunks in pairs(surfaces) do
    for _ in pairs(chunks) do total = total + 1 end
  end
  local excess = total - grid.CAP
  if excess <= 0 then return end
  local list = {}
  for surface_index, chunks in pairs(surfaces) do
    for key, record in pairs(chunks) do
      if record ~= keep then list[#list + 1] = {surface_index, key, record.touched or 0} end
    end
  end
  local drop = math.max(excess, floor(grid.CAP / 8))
  table.sort(list, function(a, b) return a[3] < b[3] end)
  for i = 1, math.min(drop, #list) do
    surfaces[list[i][1]][list[i][2]] = nil
  end
end

local function record_of(surface_index, cx, cy)
  local surfaces = surfaces_of(false)
  local chunks = surfaces and surfaces[surface_index]
  return chunks and chunks[cells.chunk_key(cx, cy)]
end

-- Returns region_of(cx, cy): the chunk's region record, or nil when the chunk
-- is not cached or its regions are not built yet (see grid.build_regions).
function grid.regions_reader(surface_index)
  local tick = game.tick
  return function(cx, cy)
    local record = record_of(surface_index, cx, cy)
    if not record then return nil end
    record.touched = tick
    return record.regions
  end
end

-- True when the chunk is in the cache.
function grid.cached(surface_index, cx, cy)
  return record_of(surface_index, cx, cy) ~= nil
end

-- Builds the regions of a cached chunk and stamps them with a new generation,
-- so a search can tell a rebuilt record from the one it started with. Costs
-- grid.REGION_UNITS; the caller charges them. Returns false when the chunk is
-- not cached.
function grid.build_regions(surface_index, cx, cy)
  local record = record_of(surface_index, cx, cy)
  if not record then return false end
  local g = storage.grid
  local gen = (g.region_gen or 0) + 1
  g.region_gen = gen
  local rec = regions.build(record.cells)
  rec.gen = gen
  record.regions = rec
  return true
end

-- Chunk reading (engine only) -------------------------------------------

-- Cell bits of the chunk plus its margin, W * W entries from index 0.
local scratch = {}

local function layer_names()
  local proto = prototypes.entity["transport-belt"]
  local mask = proto and proto.collision_mask
  local names = {}
  if mask and mask.layers then
    for name in pairs(mask.layers) do names[#names + 1] = name end
  end
  if #names == 0 then
    local first = tiers.list()[1]
    local p = first and prototypes.entity[first.belt]
    if p and p.collision_mask then
      for name in pairs(p.collision_mask.layers) do names[#names + 1] = name end
    end
  end
  return names
end

local function box_of(entity)
  local b = entity.bounding_box
  return floor(b.left_top.x + 0.01), floor(b.left_top.y + 0.01),
    ceil(b.right_bottom.x - 0.01) - 1, ceil(b.right_bottom.y - 0.01) - 1
end

-- Underground pairing in 2.0: an input and an output created with the same
-- direction (the flow direction) are neighbours; entity.neighbours is the pair.
function grid.read_chunk(surface, cx, cy)
  if not surface.is_chunk_generated{cx, cy} then
    local record = grid.put(surface.index, cx, cy,
      string.rep(string.char(cells.BLOCKED + cells.WALL), 1024))
    grid.evict(record)
    return record
  end
  local M = grid.MARGIN
  local W = 32 + 2 * M
  local x0, y0 = cx * 32 - M, cy * 32 - M
  -- The scratch table is reset here and read only within this call; reusing
  -- it avoids growing a fresh table of W * W entries on every read.
  local m = scratch
  for i = 0, W * W - 1 do m[i] = 0 end
  local function mark(x, y, bit)
    local lx, ly = x - x0, y - y0
    if lx >= 0 and lx < W and ly >= 0 and ly < W then
      local i = ly * W + lx
      m[i] = bor(m[i], bit)
    end
  end
  local area = {{x0, y0}, {x0 + W, y0 + W}}
  local layers = layer_names()

  for _, tile in pairs(surface.find_tiles_filtered{area = area, collision_mask = layers}) do
    mark(tile.position.x, tile.position.y, cells.BLOCKED)
  end
  for _, tile in pairs(surface.find_tiles_filtered{area = area, name = WALL_TILES}) do
    mark(tile.position.x, tile.position.y, cells.BLOCKED + cells.WALL)
  end

  local found = surface.find_entities_filtered{area = area, collision_mask = layers}
  for _, e in pairs(surface.find_entities_filtered{area = area, type = "entity-ghost"}) do
    found[#found + 1] = e
  end
  for _, e in pairs(found) do
    local ghost = e.type == "entity-ghost"
    local etype = ghost and e.ghost_type or e.type
    if not IGNORE[etype] then
      local lx, ly, rx, ry = box_of(e)
      for x = lx, rx do
        for y = ly, ry do mark(x, y, cells.BLOCKED) end
      end
      if BELT[etype] then
        local d = e.direction
        if d == 4 or d == 12 then
          for x = lx, rx do
            mark(x, ly - 1, cells.HUG_H)
            mark(x, ry + 1, cells.HUG_H)
          end
        elseif d == 0 or d == 8 then
          for y = ly, ry do
            mark(lx - 1, y, cells.HUG_V)
            mark(rx + 1, y, cells.HUG_V)
          end
        end
      end
      if CROWD[etype] then
        for x = lx - 1, rx + 1 do
          for y = ly - 1, ry + 1 do mark(x, y, cells.CROWDED) end
        end
      end
      if etype == "underground-belt" then
        local d = e.direction
        local bit = (d == 4 or d == 12) and cells.UG_H or cells.UG_V
        mark(lx, ly, bit)
        local other = (not ghost) and e.neighbours or nil
        if other and other.valid and other.type == "underground-belt" then
          local ox, oy = box_of(other)
          for x = math.min(lx, ox), math.max(lx, ox) do
            for y = math.min(ly, oy), math.max(ly, oy) do mark(x, y, bit) end
          end
        end
      end
    end
  end

  -- THIN: a blocked tile whose blocked run along its row or its column is at
  -- most `gap` tiles. A run touching the scratch edge counts as long. Each row
  -- and column through the chunk is scanned once. BLOCKED is bit 0, so
  -- `v % 2 == 1` tests it without a bit32 call.
  local gap = tiers.longest_gap()
  local thin = {}
  local last = W - 1
  for line = M, M + 31 do
    for axis = 0, 1 do
      -- axis 0 scans row `line` (step 1), axis 1 scans column `line` (step W).
      local base, step = axis == 0 and line * W or line, axis == 0 and 1 or W
      local a = 0
      while a <= last do
        if m[base + a * step] % 2 == 1 then
          local b = a
          while b < last and m[base + (b + 1) * step] % 2 == 1 do b = b + 1 end
          if a > 0 and b < last and b - a + 1 <= gap then
            for k = a, b do thin[base + k * step] = true end
          end
          a = b + 1
        else
          a = a + 1
        end
      end
    end
  end

  local out, bytes = {}, {}
  for ly = 0, 31 do
    local row = (ly + M) * W + M
    for lx = 0, 31 do
      local i = row + lx
      local v = m[i]
      if thin[i] and band(v, WALL) == 0 then v = bor(v, THIN) end
      bytes[lx + 1] = v
    end
    out[ly + 1] = char(unpack(bytes, 1, 32))
  end
  local record = grid.put(surface.index, cx, cy, table.concat(out))
  grid.evict(record)
  return record
end

-- Mask for a tile, reading its chunk now when missing (endpoint clicks only).
function grid.ensure(surface, x, y)
  local cell = grid.reader(surface.index)
  local v = cell(x, y)
  if v then return v end
  local cx, cy = cells.chunk_of(x, y)
  grid.read_chunk(surface, cx, cy)
  return grid.reader(surface.index)(x, y)
end

return grid
