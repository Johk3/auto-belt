local cells = require("scripts.cells")

test("cells: state ids round-trip, including negative tiles", function()
  for _, s in ipairs{{0, 0, 0}, {5, -7, 1}, {-40, -40, 2}, {123456, -654321, 3}, {-1, 0, 3}} do
    local x, y, d = cells.decode(cells.state_id(s[1], s[2], s[3]))
    equal(x, s[1], "x"); equal(y, s[2], "y"); equal(d, s[3], "d")
  end
end)

test("cells: chunk_of floors negative tiles", function()
  local cx, cy = cells.chunk_of(-1, -33)
  equal(cx, -1); equal(cy, -2)
  cx, cy = cells.chunk_of(31, 32)
  equal(cx, 0); equal(cy, 1)
end)

test("cells: turns and axis bits", function()
  equal(cells.left(0), 3); equal(cells.right(3), 0); equal(cells.reverse(1), 3)
  equal(cells.hug_bit(1), cells.HUG_H); equal(cells.hug_bit(2), cells.HUG_V)
  equal(cells.ug_bit(3), cells.UG_H); equal(cells.ug_bit(0), cells.UG_V)
  check(cells.has(cells.BLOCKED + cells.THIN, cells.THIN))
  check(not cells.has(cells.BLOCKED, cells.WALL))
end)

test("cells: distinct keys for neighbouring tiles and chunks", function()
  check(cells.tile_key(0, 1) ~= cells.tile_key(1, 0))
  check(cells.chunk_key(-1, 0) ~= cells.chunk_key(0, -1))
end)
