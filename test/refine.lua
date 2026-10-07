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

local function tile_start(x, y)
  local starts = {}
  for d = 0, 3 do starts[#starts + 1] = {x = x, y = y, d = d} end
  return starts
end

local function visits(states, x, y)
  for _, st in ipairs(states) do if st.x == x and st.y == y then return true end end
  return false
end

test("refine: prefers running beside an existing parallel belt", function()
  local rows = {
    "...........",
    "...........",
    "...........",
    "...........",
    "...........",
    "-----------",
  }
  local s = fake.solve(fake.grid(rows), params(rows, tile_start(0, 0), {x = 10, y = 4, headings = ALL, place = true}, {weight10 = 10}))
  equal(fake.turns(s.result), 1)
  check(visits(s.result, 5, 4), "route should run along row 4, beside the belt")
end)

test("refine: keeps clear of machines when an equal route exists", function()
  local rows = {
    "...........",
    ".....M.....",
    "...........",
    "...........",
    "...........",
  }
  local s = fake.solve(fake.grid(rows), params(rows, tile_start(0, 0), {x = 10, y = 4, headings = ALL, place = true}, {weight10 = 10}))
  check(visits(s.result, 0, 2), "route should go down column 0, away from the machine")
end)

local MAZE = {
  "....X.........X.....",
  ".XX.X.XXXXXXX.X.XXX.",
  ".X..X.X.....X.X...X.",
  ".X.XX.X.XXX.X.XXX.X.",
  ".X....X...X.......X.",
  ".XXXXXXXX.XXXXXXXXX.",
  "....................",
}

test("refine: a search sliced into tiny budgets finds the same route", function()
  local cell = fake.grid(MAZE)
  local p = params(MAZE, {{x = 0, y = 0, d = 2}}, {x = 19, y = 0, headings = ALL, place = true}, {max_distance = 4})
  local whole = fake.solve(cell, p)
  local sliced = fake.solve(cell, params(MAZE, {{x = 0, y = 0, d = 2}}, {x = 19, y = 0, headings = ALL, place = true}, {max_distance = 4}), 1)
  equal(#sliced.result, #whole.result)
  for i, st in ipairs(whole.result) do
    equal(sliced.result[i].x, st.x); equal(sliced.result[i].y, st.y); equal(sliced.result[i].d, st.d)
  end
end)

test("refine: a missing chunk pauses the search and resumes cleanly", function()
  local rows = {}
  for y = 1, 3 do rows[y] = string.rep(".", 70) end
  rows[2] = string.rep(".", 40) .. "|" .. string.rep(".", 29)
  local cell = fake.grid(rows)
  local p = function() return params(rows, {{x = 0, y = 1, d = 1}}, {x = 69, y = 1, headings = ALL, place = true}, {max_distance = 5}) end
  local whole = fake.solve(cell, p())
  local lazy, load = fake.lazy(cell)
  local s = require("scripts.refine").new(p())
  local needs = 0
  while true do
    local status = require("scripts.refine").step(s, 1e9, lazy)
    if status == "need" then
      needs = needs + 1
      local cx, cy = cells.chunk_of(s.need.x, s.need.y)
      load(cx, cy)
    elseif status ~= "running" then break end
  end
  check(needs >= 2, "expected to wait for chunks 1 and 2")
  equal(s.status, "found"); equal(#s.result, #whole.result)
  for i, st in ipairs(whole.result) do
    equal(s.result[i].x, st.x); equal(s.result[i].y, st.y); equal(s.result[i].d, st.d)
  end
end)

test("refine: resume after a missing chunk inside an underground scan", function()
  -- One corridor with two 3-tile barriers (x 28-30 and x 61-63). Each is crossable only by one jump of span 4,
  -- from the tile left of it ("." at x=27 and x=60); every other tile is marked as an underground-only
  -- area ("=") so no other jump, and no duplicate queue entry, can stand in for a lost state.
  -- The first jump lands at x=32 (the landing read needs chunk 1), the second scans x=64 (needs chunk 2).
  local mid = string.rep("=", 27) .. ".|||." .. string.rep("=", 28) .. ".|||." .. string.rep("=", 5)
  local rows = {string.rep("X", 70), mid, string.rep("X", 70)}
  local cell = fake.grid(rows)
  local function p() return params(rows, {{x = 0, y = 1, d = 1}}, {x = 69, y = 1, headings = ALL, place = true}, {max_distance = 4}) end
  local whole = fake.solve(cell, p())
  equal(whole.status, "found"); equal(jumps(whole.result), 2)
  local lazy, load = fake.lazy(cell)
  local refine = require("scripts.refine")
  local s = refine.new(p())
  local seen = {}
  while true do
    local status = refine.step(s, 1, lazy)
    if status == "need" then
      seen[s.need.x] = true
      local cx, cy = cells.chunk_of(s.need.x, s.need.y)
      load(cx, cy)
    elseif status ~= "running" then break end
  end
  -- both tiles lie behind a barrier, so only a jump can ask for them
  check(seen[32], "expected the landing read to wait for chunk 1")
  check(seen[64], "expected the jump scan to wait for chunk 2")
  equal(s.status, "found"); equal(#s.result, #whole.result)
  for i, st in ipairs(whole.result) do
    equal(s.result[i].x, st.x); equal(s.result[i].y, st.y); equal(s.result[i].d, st.d)
  end
end)

test("refine: resume after a missing chunk on a plain belt step", function()
  -- no barriers and no jump possible: every wait comes from reading the next belt tile
  local rows = {string.rep("X", 70), string.rep("=", 70), string.rep("X", 70)}
  local cell = fake.grid(rows)
  local function p() return params(rows, {{x = 0, y = 1, d = 1}}, {x = 69, y = 1, headings = ALL, place = true}, {max_distance = 4}) end
  local whole = fake.solve(cell, p())
  equal(whole.status, "found"); equal(jumps(whole.result), 0)
  local lazy, load = fake.lazy(cell)
  local refine = require("scripts.refine")
  local s = refine.new(p())
  local seen = {}
  while true do
    local status = refine.step(s, 1, lazy)
    if status == "need" then
      seen[s.need.x] = true
      local cx, cy = cells.chunk_of(s.need.x, s.need.y)
      load(cx, cy)
    elseif status ~= "running" then break end
  end
  check(seen[32], "expected the step from x=31 to wait for chunk 1")
  equal(s.status, "found"); equal(#s.result, #whole.result)
  for i, st in ipairs(whole.result) do
    equal(s.result[i].x, st.x); equal(s.result[i].y, st.y); equal(s.result[i].d, st.d)
  end
end)

test("refine: weight 1.0 matches the exhaustive search when a turn is forced early", function()
  local rows = {
    ".....M",
    "..M...",
    ".-X.XM",
    "......",
    ".M-M.X",
  }
  local cell = fake.grid(rows)
  local function solve(w)
    local s = fake.solve(cell, params(rows, {{x = 3, y = 0, d = 0}}, {x = 4, y = 4, headings = ALL, place = true}, {weight10 = w}))
    equal(s.status, "found")
    local last = s.result[#s.result]
    return s, s.g[cells.state_id(last.x, last.y, last.d)]
  end
  local exact, exact_cost = solve(0)
  local fast, fast_cost = solve(10)
  equal(fast_cost, exact_cost)
  equal(fake.turns(fast.result), 4)
end)

test("refine: Z shape uses exactly two turns", function()
  local rows = {
    "......",
    "......",
    "......",
    "......",
  }
  local s = fake.solve(fake.grid(rows), params(rows, {{x = 0, y = 0, d = 1}}, {x = 5, y = 3, headings = {[1] = true}, place = true}))
  equal(s.status, "found")
  equal(fake.turns(s.result), 2)
end)
