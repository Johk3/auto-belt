local hpa = require("scripts.hpa")
local cells = require("scripts.cells")
local fake = require("test.fake_grid")

local function map(w, h, wall_x, gap_y)
  local rows = {}
  for y = 0, h - 1 do
    local r = {}
    for x = 0, w - 1 do r[#r + 1] = (x == wall_x and y ~= gap_y) and "X" or "." end
    rows[#rows + 1] = table.concat(r)
  end
  return rows
end

local function solve(rows, start, goals, goal_point)
  local s = hpa.new{start = start, goals = goals, goal_point = goal_point or goals[1]}
  local region_of = fake.region_reader(rows)
  for _ = 1, 10000 do
    local status = hpa.step(s, 50, region_of)
    if status == "need" then error("fake reader never needs chunks") end
    if status ~= "running" then return s end
  end
  error("hpa did not finish")
end

local function has_chunk(chunks, cx, cy)
  for _, c in ipairs(chunks) do if c.cx == cx and c.cy == cy then return true end end
  return false
end

test("hpa: straight across open chunks", function()
  local s = solve(map(128, 32), {x = 1, y = 5}, {{x = 126, y = 5}})
  equal(s.status, "found"); equal(#s.chunks, 4)
end)

test("hpa: detours through the only gap in a wall", function()
  local s = solve(map(128, 96, 64, 80), {x = 1, y = 5}, {{x = 126, y = 5}})
  equal(s.status, "found")
  check(has_chunk(s.chunks, 2, 2), "path passes the gap chunk")
end)

test("hpa: a sealed wall fails", function()
  local s = solve(map(128, 64, 64, -1), {x = 1, y = 5}, {{x = 126, y = 5}})
  equal(s.status, "failed")
end)

test("hpa: a goal reachable only from its side approach tile", function()
  local s = solve(map(96, 32), {x = 1, y = 5}, {{x = 90, y = 4}}, {x = 90, y = 5})
  equal(s.status, "found")
end)

test("hpa: corridor rings", function()
  local set = hpa.corridor({{cx = 0, cy = 0}, {cx = 1, cy = 0}}, 1)
  local n = 0
  for _ in pairs(set) do n = n + 1 end
  equal(n, 12)
  check(set[cells.chunk_key(-1, -1)] and set[cells.chunk_key(2, 1)], "ring corners included")
end)

test("hpa: chunk keys round-trip", function()
  local cx, cy = cells.chunk_xy(cells.chunk_key(-3, 7))
  equal(cx, -3); equal(cy, 7)
end)

test("hpa: a start already in a goal region yields only its chunk", function()
  local s = solve(map(64, 32), {x = 1, y = 5}, {{x = 20, y = 5}})
  equal(s.status, "found"); equal(#s.chunks, 1)
  check(has_chunk(s.chunks, 0, 0), "start chunk")
end)

test("hpa: a start on a wall fails", function()
  local s = solve(map(64, 32, 5), {x = 5, y = 5}, {{x = 40, y = 5}})
  equal(s.status, "failed")
end)

test("hpa: a start in an overflow region fails cleanly", function()
  local rows = {}
  for y = 0, 31 do
    local r = {}
    for x = 0, 31 do r[#r + 1] = (x % 2 == 0 and y % 2 == 0) and "." or "X" end
    rows[#rows + 1] = table.concat(r)
  end
  local s = solve(rows, {x = 30, y = 30}, {{x = 0, y = 0}})
  equal(s.status, "failed")
end)

test("hpa: a missing chunk asks for a read and the search resumes", function()
  local rows = map(96, 32)
  local real = fake.region_reader(rows)
  local hidden = true
  local function region_of(cx, cy)
    if hidden and cx == 1 and cy == 0 then return nil end
    return real(cx, cy)
  end
  local s = hpa.new{start = {x = 1, y = 5}, goals = {{x = 90, y = 5}}, goal_point = {x = 90, y = 5}}
  local status
  repeat status = hpa.step(s, 50, region_of) until status ~= "running"
  equal(status, "need"); equal(s.need.cx, 1); equal(s.need.cy, 0)
  hidden = false
  repeat status = hpa.step(s, 50, region_of) until status ~= "running"
  equal(status, "found"); equal(#s.chunks, 3)
end)

test("hpa: search state holds no functions", function()
  local s = solve(map(64, 32), {x = 1, y = 5}, {{x = 60, y = 5}})
  local function plain(t)
    for _, v in pairs(t) do
      check(type(v) ~= "function", "function in search state")
      if type(v) == "table" then plain(v) end
    end
  end
  plain(s)
end)
