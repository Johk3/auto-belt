local regions = require("scripts.regions")
local cells = require("scripts.cells")

local function chunk(fn)
  local t = {}
  for y = 0, 31 do for x = 0, 31 do t[y * 32 + x + 1] = string.char(fn(x, y)) end end
  return table.concat(t)
end

test("regions: an open chunk is one region with a central centroid", function()
  local rec = regions.build(chunk(function() return 0 end))
  equal(rec.count, 1)
  equal(rec.centroids[1].x, 16); equal(rec.centroids[1].y, 16)
end)

test("regions: a wall column splits the chunk", function()
  local rec = regions.build(chunk(function(x) return x == 10 and cells.BLOCKED + cells.WALL or 0 end))
  equal(rec.count, 2)
  check(regions.label(rec, 0, 0) ~= regions.label(rec, 31, 0), "two sides differ")
  equal(regions.label(rec, 10, 5), 0)
end)

test("regions: a thin blocked column does not split the chunk", function()
  local rec = regions.build(chunk(function(x) return x == 10 and cells.BLOCKED + cells.THIN or 0 end))
  equal(rec.count, 1)
end)

test("regions: a thick blocked band splits the chunk", function()
  local rec = regions.build(chunk(function(x) return (x >= 8 and x <= 20) and cells.BLOCKED or 0 end))
  equal(rec.count, 2)
end)

test("regions: more than 254 pockets do not crash; overflow reads as impassable", function()
  local rec = regions.build(chunk(function(x, y) return (x % 2 == 0 and y % 2 == 0) and 0 or cells.BLOCKED + cells.WALL end))
  equal(rec.count, 254)
  equal(regions.label(rec, 30, 30), 0)
end)
