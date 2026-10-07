local grid = require("scripts.grid")
local cells = require("scripts.cells")

local function record(fill_byte, special)
  local t = {}
  for i = 1, 1024 do t[i] = string.char(fill_byte) end
  for index, byte in pairs(special or {}) do t[index] = string.char(byte) end
  return table.concat(t)
end

test("grid: reader indexes negative chunks", function()
  storage = {}
  grid.put(1, -1, -1, record(0, {[1024] = cells.CROWDED}))
  local cell = grid.reader(1)
  equal(cell(-1, -1), cells.CROWDED)
  equal(cell(-32, -32), 0)
  equal(cell(0, 0), nil)
end)

test("grid: invalidation drops chunks within the margin", function()
  storage = {}
  for cx = -1, 2 do grid.put(1, cx, 0, record(0)) end
  grid.invalidate_box(1, 33, 5, 33, 5)
  local cell = grid.reader(1)
  equal(cell(-1, 0), 0, "chunk -1 kept")
  equal(cell(0, 0), nil, "chunk 0 dropped (within 11 tiles)")
  equal(cell(40, 0), nil, "chunk 1 dropped")
  equal(cell(70, 0), 0, "chunk 2 kept")
end)

test("grid: eviction keeps the cache under the cap", function()
  storage = {}
  local cap = grid.CAP
  grid.CAP = 10
  for i = 1, 12 do game.tick = i; grid.put(1, i, 0, record(0)) end
  grid.evict()
  local n = 0
  for _ in pairs(storage.grid.surfaces[1]) do n = n + 1 end
  check(n <= 10, "cache over cap: " .. n)
  equal(grid.reader(1)(12 * 32, 0), 0, "newest kept")
  grid.CAP = cap
  game.tick = 0
end)

test("grid: reader sees a chunk stored after it was made", function()
  storage = {}
  local cell = grid.reader(1)
  equal(cell(0, 0), nil)
  grid.put(1, 0, 0, record(0))
  equal(cell(0, 0), 0)
end)

test("grid: reader sees a record put after drop_surface", function()
  storage = {}
  grid.put(1, 0, 0, record(0))
  local cell = grid.reader(1)
  grid.drop_surface(1)
  grid.put(1, 0, 0, record(cells.CROWDED))
  equal(cell(0, 0), cells.CROWDED)
end)

test("grid: regions are built once per chunk record and dropped with it", function()
  storage = {}
  grid.put(1, 0, 0, string.rep(string.char(0), 1024))
  local region_of = grid.regions_reader(1)
  local rec = region_of(0, 0)
  equal(rec.count, 1)
  check(region_of(0, 0) == rec, "cached")
  grid.invalidate_box(1, 5, 5, 5, 5)
  equal(grid.regions_reader(1)(0, 0), nil)
end)

local function count_records()
  local n = 0
  for _, chunks in pairs(storage.grid.surfaces) do
    for _ in pairs(chunks) do n = n + 1 end
  end
  return n
end

-- Runs fn with grid.CAP lowered, restoring it even when fn fails.
local function with_cap(cap, fn)
  local old = grid.CAP
  grid.CAP = cap
  local ok, err = pcall(fn)
  grid.CAP = old
  game.tick = 0
  if not ok then error(err, 0) end
end

test("grid: over-filling drops the batch of max(excess, CAP/8) oldest records", function()
  storage = {}
  with_cap(16, function()
    for i = 1, 17 do game.tick = i; grid.put(1, i, 0, record(0)) end
    grid.evict()
    -- excess 1, batch floor(16 / 8) = 2: records 1 and 2 go
    equal(count_records(), 15)
    equal(grid.reader(1)(1 * 32, 0), nil, "oldest dropped")
    equal(grid.reader(1)(2 * 32, 0), nil, "second oldest dropped")
    equal(grid.reader(1)(3 * 32, 0), 0, "third kept")
    for i = 18, 40 do game.tick = i; grid.put(1, i, 0, record(0)) end
    grid.evict()
    -- 38 records, excess 22 > batch 2: drops 22
    equal(count_records(), 16)
  end)
end)

test("grid: eviction under the cap changes nothing", function()
  storage = {}
  with_cap(16, function()
    for i = 1, 16 do game.tick = i; grid.put(1, i, 0, record(0)) end
    grid.evict()
    equal(count_records(), 16)
  end)
end)

test("grid: the record just stored survives eviction on a touched tie", function()
  storage = {}
  with_cap(8, function()
    game.tick = 5
    for i = 1, 8 do grid.put(1, i, 0, record(0)) end
    local fresh = grid.put(1, 99, 0, record(cells.CROWDED))
    grid.evict(fresh)
    check(grid.reader(1)(99 * 32, 0) == cells.CROWDED, "fresh record kept")
    check(count_records() <= 8, "cache within cap: " .. count_records())
  end)
end)
