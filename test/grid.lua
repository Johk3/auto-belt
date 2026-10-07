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
