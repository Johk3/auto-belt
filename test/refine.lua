local fake = require("test.fake_grid")
local cells = require("scripts.cells")
local ALL = {[0] = true, [1] = true, [2] = true, [3] = true}

local function params(rows, starts, goal, extra)
  local p = {starts = starts, goal = goal, region = fake.box(rows), mode = "belts", max_distance = 0}
  for k, v in pairs(extra or {}) do p[k] = v end
  return p
end

test("refine: straight line east", function()
  local rows = {"......"}
  local s = fake.solve(fake.grid(rows), params(rows, {{x = 0, y = 0, d = 1}}, {x = 5, y = 0, headings = ALL, place = true}))
  equal(s.status, "found")
  equal(#s.result, 6)
  equal(fake.turns(s.result), 0)
end)

test("refine: L shape uses one turn", function()
  local rows = {".....", ".....", "....."}
  local s = fake.solve(fake.grid(rows), params(rows, {{x = 0, y = 0, d = 1}}, {x = 4, y = 2, headings = ALL, place = true}))
  equal(s.status, "found"); equal(fake.turns(s.result), 1)
end)

test("refine: diagonal goal never staircases", function()
  local rows = {"........", "........", "........", "........", "........", "........"}
  local s = fake.solve(fake.grid(rows), params(rows, {{x = 0, y = 0, d = 1}}, {x = 6, y = 5, headings = ALL, place = true}))
  equal(fake.turns(s.result), 1)
end)

test("refine: maze of walls", function()
  local rows = {
    ".X......",
    ".X.XXXX.",
    ".X.X....",
    "...X.XXX",
    "XXXX....",
  }
  local cell = fake.grid(rows)
  local s = fake.solve(cell, params(rows, {{x = 0, y = 0, d = 2}}, {x = 7, y = 4, headings = ALL, place = true}))
  equal(s.status, "found")
  for _, st in ipairs(s.result) do check(cell(st.x, st.y) == 0, "route on blocked tile " .. st.x .. "," .. st.y) end
end)

test("refine: straight input into an end belt", function()
  local rows = {"......-"}
  local s = fake.solve(fake.grid(rows), params(rows, {{x = 0, y = 0, d = 1}}, {x = 6, y = 0, headings = {[1] = true}, place = false}))
  equal(s.status, "found")
  local last = s.result[#s.result]
  equal(last.x, 6); equal(last.d, 1)
  equal(s.result[#s.result - 1].x, 5)
end)

test("refine: sideload when the tile behind the end belt is a wall", function()
  local rows = {"........", "......X-", "........"}
  local goal = {x = 7, y = 1, headings = {[1] = true, [0] = true, [2] = true}, place = false}
  local s = fake.solve(fake.grid(rows), params(rows, {{x = 0, y = 0, d = 1}}, goal))
  equal(s.status, "found")
  local last = s.result[#s.result]
  check(last.d == 0 or last.d == 2, "arrived from the side")
end)

test("refine: unreachable goal fails and reports the closest tile", function()
  local rows = {"....XXX", "....X.X", "....XXX"}
  local s = fake.solve(fake.grid(rows), params(rows, {{x = 0, y = 1, d = 1}}, {x = 5, y = 1, headings = ALL, place = true}))
  equal(s.status, "failed")
  equal(s.closest.x, 3); equal(s.closest.y, 1)
end)

test("refine: negative coordinates route like positive ones", function()
  local rows = {".....", ".....", "....."}
  local cell = fake.grid(rows, -40, -33)
  local p = {starts = {{x = -40, y = -33, d = 1}}, goal = {x = -36, y = -31, headings = ALL, place = true},
    region = fake.box(rows, -40, -33), mode = "belts", max_distance = 0}
  local s = fake.solve(cell, p)
  equal(s.status, "found"); equal(fake.turns(s.result), 1)
  local last = s.result[#s.result]
  equal(last.x, -36); equal(last.y, -31)
end)

test("refine: a tile start may leave in any heading", function()
  local rows = {".....", ".....", "....."}
  local starts = {}
  for d = 0, 3 do starts[#starts + 1] = {x = 2, y = 2, d = d} end
  local s = fake.solve(fake.grid(rows), params(rows, starts, {x = 2, y = 0, headings = ALL, place = true}))
  equal(#s.result, 3); equal(fake.turns(s.result), 0)
end)

local function jumps(states)
  local n = 0
  for i = 1, #states - 1 do
    local a, b = states[i], states[i + 1]
    if math.abs(a.x - b.x) + math.abs(a.y - b.y) > 1 then n = n + 1 end
  end
  return n
end

local LINE = {
  "XXXXX|XXXXX",
  ".....|.....",
  ".....|.....",
  ".....|.....",
  "XXXXX|XXXXX",
}

test("refine: belts mode crosses a belt line with one underground", function()
  local s = fake.solve(fake.grid(LINE), params(LINE, {{x = 0, y = 2, d = 1}},
    {x = 10, y = 2, headings = ALL, place = true}, {max_distance = 5}))
  equal(s.status, "found"); equal(jumps(s.result), 1); equal(fake.turns(s.result), 0)
end)

test("refine: belts mode avoids undergrounds in open ground", function()
  local rows = {string.rep(".", 30)}
  local s = fake.solve(fake.grid(rows), params(rows, {{x = 0, y = 0, d = 1}},
    {x = 29, y = 0, headings = ALL, place = true}, {max_distance = 5}))
  equal(jumps(s.result), 0)
end)

test("refine: undergrounds mode chains maximum-length pairs", function()
  local rows = {string.rep(".", 40)}
  local s = fake.solve(fake.grid(rows), params(rows, {{x = 0, y = 0, d = 1}},
    {x = 39, y = 0, headings = ALL, place = true}, {max_distance = 5, mode = "undergrounds"}))
  equal(s.status, "found")
  check(jumps(s.result) >= 6, "expected a chain of pairs, got " .. jumps(s.result))
  local single = 0
  for i = 1, #s.result - 1 do
    local a, b = s.result[i], s.result[i + 1]
    local dist = math.abs(a.x - b.x) + math.abs(a.y - b.y)
    check(dist <= 6, "pair longer than max distance")
    if dist == 1 then single = single + 1 end
  end
  check(single <= 2, "too many surface belts: " .. single)
end)

test("refine: an existing same-axis underground blocks the jump", function()
  local rows = {
    "XXXXXhXXXXX",
    ".....h.....",
    ".....h.....",
    "XXXXXhXXXXX",
  }
  local s = fake.solve(fake.grid(rows), params(rows, {{x = 0, y = 1, d = 1}},
    {x = 10, y = 1, headings = ALL, place = true}, {max_distance = 5}))
  equal(s.status, "failed")
end)

test("refine: a perpendicular underground does not block the jump", function()
  local rows = {
    "XXXXXvXXXXX",
    ".....v.....",
    "XXXXXvXXXXX",
  }
  local s = fake.solve(fake.grid(rows), params(rows, {{x = 0, y = 1, d = 1}},
    {x = 10, y = 1, headings = ALL, place = true}, {max_distance = 5}))
  equal(s.status, "found"); equal(jumps(s.result), 1)
end)

test("refine: no underground tier means no jumps", function()
  local s = fake.solve(fake.grid(LINE), params(LINE, {{x = 0, y = 2, d = 1}},
    {x = 10, y = 2, headings = ALL, place = true}, {max_distance = 0}))
  equal(s.status, "failed")
end)

test("refine: an obstacle wider than the tier's reach cannot be tunnelled", function()
  local rows = {"..########.."}
  local s = fake.solve(fake.grid(rows), params(rows, {{x = 0, y = 0, d = 1}},
    {x = 11, y = 0, headings = ALL, place = true}, {max_distance = 5}))
  equal(s.status, "failed")
end)

test("refine: underground lands straight into an end belt", function()
  local rows = {"..#.-"}
  local s = fake.solve(fake.grid(rows), params(rows, {{x = 0, y = 0, d = 1}},
    {x = 4, y = 0, headings = {[1] = true}, place = false}, {max_distance = 5}))
  equal(s.status, "found")
  local last = s.result[#s.result]
  equal(last.x, 4)
end)

test("refine: a jump never passes under a tile outside the region", function()
  local rows = {"..#.."}
  local p = params(rows, {{x = 0, y = 0, d = 1}}, {x = 4, y = 0, headings = ALL, place = true}, {max_distance = 5})
  p.region = {x1 = 0, y1 = 0, x2 = 1, y2 = 0}
  local inner = fake.grid(rows)
  local s = fake.solve(function(x, y)
    if x < 0 or x > 1 or y ~= 0 then error("cell read outside the region: " .. x .. "," .. y) end
    return inner(x, y)
  end, p)
  equal(s.status, "failed")
end)
