local fake = require("test.fake_grid")
local jobs = require("scripts.jobs")
local refine = require("scripts.refine")
local scheduler = require("scripts.scheduler")
local grid = require("scripts.grid")
local ALL = {[0] = true, [1] = true, [2] = true, [3] = true}
local TIER = {belt = "transport-belt", underground = "underground-belt", max_distance = 5}

local function fresh(rows)
  storage = {jobs = {}, builds = {}, players = {}, next_id = 1}
  settings = {global = {["auto-belt-max-effort"] = {value = 5000000}}}
  game = {tick = 1}
  fake.records(rows, 1)
end

local function run(job)
  for _ = 1, 1000 do
    jobs.step(job, 100)
    if job.stage ~= "refine" then return job end
  end
  error("job did not finish")
end

local function plain(value, path)
  local kind = type(value)
  if kind == "function" or kind == "userdata" or kind == "thread" then error("non-data value at " .. path) end
  if kind == "table" then for k, v in pairs(value) do plain(v, path .. "." .. tostring(k)) end end
end

test("jobs: a short route becomes an entity list", function()
  local rows = {"..........", "....|.....", ".........."}
  fresh(rows)
  local job = run(jobs.create{surface_index = 1, force = "player", starts = {{x = 0, y = 1, d = 1}},
    goal = {x = 9, y = 1, headings = ALL, place = true}, tier = TIER, layout = "belts", placement = "ghost"})
  equal(job.stage, "ready")
  equal(job.entities[#job.entities].x, 9)
  equal(job.search, nil)
end)

test("jobs: job state is plain data at every stage", function()
  local rows = {"..........", "....|.....", ".........."}
  fresh(rows)
  local job = jobs.create{surface_index = 1, force = "player", starts = {{x = 0, y = 1, d = 1}},
    goal = {x = 9, y = 1, headings = ALL, place = true}, tier = TIER, layout = "belts", placement = "ghost"}
  plain(job, "job")
  jobs.step(job, 3)
  plain(job, "job")
  run(job)
  plain(job, "job")
end)

test("jobs: create expands nothing and stores the job", function()
  local rows = {"..........", ".........."}
  fresh(rows)
  local job = jobs.create{surface_index = 1, force = {name = "player"}, starts = {{x = 0, y = 1, d = 1}},
    goal = {x = 9, y = 1, headings = ALL, place = true}, tier = TIER, layout = "belts", placement = "ghost"}
  equal(job.search.expansions, 0)
  equal(job.force, "player")
  equal(storage.jobs[job.id], job)
  jobs.remove(job)
  equal(storage.jobs[job.id], nil)
end)

test("jobs: effort limit fails the job", function()
  local rows = {"....XXX", "....X.X", "....XXX"}
  fresh(rows)
  settings.global["auto-belt-max-effort"].value = 5
  local job = run(jobs.create{surface_index = 1, force = "player", starts = {{x = 0, y = 1, d = 1}},
    goal = {x = 5, y = 1, headings = ALL, place = true}, tier = TIER, layout = "belts", placement = "ghost"})
  equal(job.stage, "failed"); equal(job.error, "auto-belt.search-limit")
end)

test("jobs: an unreachable goal fails with no-route and a closest tile", function()
  local rows = {"....XXX", "....X.X", "....XXX"}
  fresh(rows)
  local job = run(jobs.create{surface_index = 1, force = "player", starts = {{x = 0, y = 1, d = 1}},
    goal = {x = 5, y = 1, headings = ALL, place = true}, tier = TIER, layout = "belts", placement = "ghost"})
  equal(job.error, "auto-belt.no-route"); equal(job.closest.x, 3)
end)

test("jobs: remove updates the on_tick registration", function()
  local rows = {"..........", ".........."}
  fresh(rows)
  local saved = AUTO_BELT
  local calls = 0
  AUTO_BELT = {update_tick = function() calls = calls + 1 end}
  local ok, err = pcall(function()
    local job = jobs.create{surface_index = 1, force = "player", starts = {{x = 0, y = 1, d = 1}},
      goal = {x = 9, y = 1, headings = ALL, place = true}, tier = TIER, layout = "belts", placement = "ghost"}
    calls = 0
    jobs.remove(job)
    equal(calls, 1)
  end)
  AUTO_BELT = saved
  check(ok, err)
end)

local function wide(w, h, wall_x, gap_y)
  local rows = {}
  for y = 0, h - 1 do
    local r = {}
    for x = 0, w - 1 do r[#r + 1] = (x == wall_x and y ~= gap_y) and "X" or "." end
    rows[#rows + 1] = table.concat(r)
  end
  return rows
end

local function searching(job) return job.stage == "abstract" or job.stage == "refine" end

local function finish(job)
  for _ = 1, 100000 do
    if not searching(job) then return job end
    jobs.step(job, 500)
  end
  error("job did not finish")
end

local function long_job(y, goal_y, extra)
  local p = {surface_index = 1, force = "player", starts = {{x = 1, y = y, d = 1}},
    goal = {x = 198, y = goal_y, headings = ALL, place = true}, tier = TIER, layout = "belts", placement = "ghost"}
  for k, v in pairs(extra or {}) do p[k] = v end
  return jobs.create(p)
end

test("jobs: a long route goes through the abstract stage and the gap", function()
  fresh(wide(200, 96, 100, 80))
  local job = long_job(5, 5)
  equal(job.stage, "abstract")
  equal(job.ring, 1)
  finish(job)
  equal(job.stage, "ready")
  equal(job.abstract, nil)
  local through_gap = false
  for _, e in ipairs(job.entities) do if e.x == 100 then through_gap = e.y == 80 or through_gap end end
  check(through_gap, "route crosses the wall at the gap")
end)

test("jobs: a short route skips the abstract stage", function()
  fresh({"..........", ".........."})
  local job = jobs.create{surface_index = 1, force = "player", starts = {{x = 0, y = 1, d = 1}},
    goal = {x = 9, y = 1, headings = ALL, place = true}, tier = TIER, layout = "belts", placement = "ghost"}
  equal(job.stage, "refine")
  equal(job.search.weight10, 10)
end)

test("jobs: long job state is plain data in the abstract stage", function()
  fresh(wide(200, 32))
  local job = long_job(5, 5)
  plain(job, "job")
  jobs.step(job, 20)
  plain(job, "job")
  finish(job)
  plain(job, "job")
end)

test("jobs: long routes refine with weight 12", function()
  fresh(wide(200, 32))
  local job = long_job(5, 5)
  for _ = 1, 10000 do
    if job.stage ~= "abstract" then break end
    jobs.step(job, 5)
  end
  equal(job.stage, "refine")
  equal(job.search.weight10, 12)
  check(job.search.region.chunks ~= nil, "refine is limited to a corridor")
end)

test("jobs: refine failure in ring 1 retries once in ring 2", function()
  fresh(wide(200, 32))
  local real_step = refine.step
  local calls = 0
  refine.step = function(search, budget, cell)
    calls = calls + 1
    if calls == 1 then search.status = "failed"; search.closest = {x = 1, y = 5, h = 0}; return "failed", 1 end
    return real_step(search, budget, cell)
  end
  local job = long_job(5, 5)
  local ok, err = pcall(finish, job)
  refine.step = real_step
  if not ok then error(err) end
  equal(job.ring, 2); equal(job.stage, "ready")
end)

test("jobs: refine failure in ring 2 is no-route with the closest tile", function()
  fresh(wide(200, 32))
  local real_step = refine.step
  refine.step = function(search) search.status = "failed"; search.closest = {x = 7, y = 5, h = 0}; return "failed", 1 end
  local job = long_job(5, 5)
  local ok, err = pcall(finish, job)
  refine.step = real_step
  if not ok then error(err) end
  equal(job.ring, 2); equal(job.stage, "failed"); equal(job.error, "auto-belt.no-route")
  equal(job.closest.x, 7)
end)

test("jobs: an end belt entered from the side on a long route", function()
  local rows = wide(200, 32)
  local r = rows[6]
  rows[6] = r:sub(1, 197) .. "X-" .. r:sub(200)
  fresh(rows)
  local job = finish(jobs.create{surface_index = 1, force = "player", starts = {{x = 1, y = 5, d = 1}},
    goal = {x = 198, y = 5, headings = {[1] = true, [0] = true, [2] = true}, place = false}, tier = TIER,
    layout = "belts", placement = "ghost"})
  equal(job.stage, "ready")
end)

test("jobs: a start in an overflow region fails with no-route", function()
  local rows = wide(200, 32)
  for y = 0, 31 do
    local r = {}
    for x = 0, 31 do r[#r + 1] = (x % 2 == 0 and y % 2 == 0) and "." or "X" end
    rows[y + 1] = table.concat(r) .. rows[y + 1]:sub(33)
  end
  fresh(rows)
  local job = jobs.create{surface_index = 1, force = "player", starts = {{x = 30, y = 30, d = 1}},
    goal = {x = 198, y = 5, headings = ALL, place = true}, tier = TIER, layout = "belts", placement = "ghost"}
  finish(job)
  equal(job.stage, "failed"); equal(job.error, "auto-belt.no-route")
  equal(job.closest.x, 30)
end)

local function with_reads(read, body)
  local real_surface, real_read = game.get_surface, grid.read_chunk
  game.get_surface = function() return {index = 1} end
  grid.read_chunk = read
  local ok, err = pcall(body)
  game.get_surface, grid.read_chunk = real_surface, real_read
  if not ok then error(err, 0) end
end

test("jobs: an uncached chunk is read, charged and counted", function()
  local rows = {"..........", "..........", ".........."}
  fresh(rows)
  grid.invalidate_box(1, 0, 0, 9, 2)
  local reads = 0
  with_reads(function() reads = reads + 1; fake.records(rows, 1) end, function()
    local job = jobs.create{surface_index = 1, force = "player", starts = {{x = 0, y = 1, d = 1}},
      goal = {x = 9, y = 1, headings = ALL, place = true}, tier = TIER, layout = "belts", placement = "ghost"}
    equal(job.chunk_reads, 0)
    jobs.step(job, 100000)
    equal(job.chunk_reads, 1)
    equal(reads, 1)
    check(job.effort >= grid.CHUNK_UNITS, "chunk read is charged")
    finish(job)
    equal(job.stage, "ready")
  end)
end)

test("jobs: too many chunk reads fail with search-limit", function()
  local rows = {"..........", "..........", ".........."}
  fresh(rows)
  grid.invalidate_box(1, 0, 0, 9, 2)
  local cap = grid.CAP
  grid.CAP = 2
  local ok, err = pcall(with_reads, function() end, function()
    local job = jobs.create{surface_index = 1, force = "player", starts = {{x = 0, y = 1, d = 1}},
      goal = {x = 9, y = 1, headings = ALL, place = true}, tier = TIER, layout = "belts", placement = "ghost"}
    jobs.step(job, 100000)
    equal(job.stage, "failed"); equal(job.error, "auto-belt.search-limit")
    equal(job.chunk_reads, 2)
  end)
  grid.CAP = cap
  if not ok then error(err, 0) end
end)

test("jobs: an abstract search stored in the older format starts over", function()
  fresh(wide(200, 96, 100, 80))
  local job = long_job(5, 5)
  jobs.step(job, 3)
  equal(job.stage, "abstract")
  -- The older format: no chunk origin, node ids from the packed chunk key.
  job.abstract.ocx, job.abstract.ocy = nil, nil
  job.abstract.g = {[2147516416 * 256 + 1] = 0}
  finish(job)
  equal(job.stage, "ready")
  local through_gap = false
  for _, e in ipairs(job.entities) do if e.x == 100 then through_gap = e.y == 80 or through_gap end end
  check(through_gap, "route crosses the wall at the gap")
end)

test("jobs: a refine search stored in the older format starts over with the same route", function()
  local rows = {"..........", "....|.....", ".........."}
  local function make()
    return jobs.create{surface_index = 1, force = "player", starts = {{x = 0, y = 1, d = 1}},
      goal = {x = 9, y = 1, headings = ALL, place = true}, tier = TIER, layout = "belts", placement = "ghost"}
  end
  fresh(rows)
  local whole = run(make())
  local job = make()
  jobs.step(job, 3)
  job.search.x0, job.search.y0, job.search.w, job.search.h = nil, nil, nil, nil
  run(job)
  equal(job.stage, "ready"); equal(#job.entities, #whole.entities)
  for i, e in ipairs(whole.entities) do
    equal(job.entities[i].x, e.x); equal(job.entities[i].y, e.y); equal(job.entities[i].d, e.d)
  end
  -- A long route in its refine stage keeps its corridor.
  fresh(wide(200, 32))
  local long = long_job(5, 5)
  for _ = 1, 10000 do
    if long.stage ~= "abstract" then break end
    jobs.step(long, 50)
  end
  equal(long.stage, "refine")
  long.search.x0 = nil
  finish(long)
  equal(long.stage, "ready")
end)

local function budgets(search, build)
  settings.global["auto-belt-search-budget"] = {value = search}
  settings.global["auto-belt-build-batch"] = {value = build}
end

test("scheduler: two long jobs share the budget and both finish", function()
  fresh(wide(200, 64))
  budgets(600, 150)
  local a, b = long_job(5, 5), long_job(50, 50)
  for _ = 1, 2000 do
    scheduler.tick()
    if a.stage == "ready" and b.stage == "ready" then break end
  end
  equal(a.stage, "ready"); equal(b.stage, "ready")
end)

test("scheduler: the job served first rotates across ticks", function()
  fresh(wide(200, 32))
  budgets(50, 150)
  local list = {long_job(5, 5), long_job(6, 6), long_job(7, 7)}
  local first = {}
  local real_step = jobs.step
  local order
  jobs.step = function(job) order[#order + 1] = job.id; return 50 end
  local ok, err = pcall(function()
    for _ = 1, 3 do
      order = {}
      scheduler.tick()
      first[order[1]] = (first[order[1]] or 0) + 1
    end
  end)
  jobs.step = real_step
  if not ok then error(err) end
  for _, job in ipairs(list) do equal(first[job.id], 1, "job " .. job.id .. " served first once") end
end)

test("scheduler: a tick without AUTO_BELT is safe", function()
  fresh(wide(200, 32))
  budgets(50, 150)
  local saved = AUTO_BELT
  AUTO_BELT = nil
  local ok, err = pcall(scheduler.tick)
  AUTO_BELT = saved
  check(ok, err)
end)
