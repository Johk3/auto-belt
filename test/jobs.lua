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

local function count(set)
  local n = 0
  for _ in pairs(set) do n = n + 1 end
  return n
end

test("jobs: refine failure in ring 1 retries once in ring 2", function()
  fresh(wide(200, 32))
  local real_step = refine.step
  local calls = 0
  local corridors = {}
  refine.step = function(search, budget, cell)
    calls = calls + 1
    if search ~= corridors[#corridors] then corridors[#corridors + 1] = search end
    if calls == 1 then search.status = "failed"; search.closest = {x = 1, y = 5, h = 0}; return "failed", 1 end
    return real_step(search, budget, cell)
  end
  local job = long_job(5, 5)
  local ok, err = pcall(finish, job)
  refine.step = real_step
  if not ok then error(err) end
  equal(job.ring, 2); equal(job.stage, "ready")
  equal(#corridors, 2, "one refine per ring")
  local ring1, ring2 = count(corridors[1].region.chunks), count(corridors[2].region.chunks)
  check(ring2 > ring1, "ring 2 widens the corridor: " .. ring1 .. " then " .. ring2 .. " chunks")
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

test("jobs: a chunk read that does not fit waits for the next step", function()
  local rows = {"..........", "..........", ".........."}
  fresh(rows)
  grid.invalidate_box(1, 0, 0, 9, 2)
  local reads = 0
  with_reads(function() reads = reads + 1; fake.records(rows, 1) end, function()
    local job = jobs.create{surface_index = 1, force = "player", starts = {{x = 0, y = 1, d = 1}},
      goal = {x = 9, y = 1, headings = ALL, place = true}, tier = TIER, layout = "belts", placement = "ghost"}
    -- Not the first step of the tick: the read waits and nothing is used.
    equal(jobs.step(job, grid.CHUNK_UNITS - 1, false), 0)
    equal(reads, 0)
    -- The first step of a tick reads even when the read costs more than the budget.
    equal(jobs.step(job, 1), grid.CHUNK_UNITS)
    equal(reads, 1)
    equal(job.effort, grid.CHUNK_UNITS)
  end)
end)

test("scheduler: a tick reads at most one chunk, and only before any expansion, when a read costs more than the budget", function()
  local rows = {}
  for y = 1, 3 do rows[y] = string.rep(".", 100) end
  fresh(rows)
  settings.global["auto-belt-search-budget"] = {value = math.max(1, grid.CHUNK_UNITS - 1)}
  settings.global["auto-belt-build-batch"] = {value = 150}
  grid.invalidate_box(1, 0, 0, 99, 2)
  local reads = 0
  local cell = fake.grid(rows)
  with_reads(function(_, cx, cy)
    -- Stores only the chunk asked for, so every chunk the search enters is read.
    reads = reads + 1
    local out = {}
    for ly = 0, 31 do for lx = 0, 31 do out[#out + 1] = string.char(cell(cx * 32 + lx, cy * 32 + ly)) end end
    grid.put(1, cx, cy, table.concat(out))
  end, function()
    local job = jobs.create{surface_index = 1, force = "player", starts = {{x = 0, y = 1, d = 1}},
      goal = {x = 90, y = 1, headings = ALL, place = true}, tier = TIER, layout = "belts", placement = "ghost"}
    local ticks, budget = 0, settings.global["auto-belt-search-budget"].value
    while job.stage == "refine" and ticks < 10000 do
      local before, effort = reads, job.effort
      scheduler.tick()
      ticks = ticks + 1
      check(reads - before <= 1, "tick " .. ticks .. " read " .. (reads - before) .. " chunks")
      -- A read never follows expansions in the same tick.
      check(job.effort - effort <= math.max(budget, grid.CHUNK_UNITS), "tick " .. ticks .. " used " .. (job.effort - effort))
    end
    equal(job.stage, "ready")
    check(reads >= 3, "the route crossed several chunks: " .. reads)
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

test("jobs: region builds on a warm cache are charged to the budget", function()
  fresh(wide(200, 96, 100, 80))
  local job = long_job(5, 5)
  local used = jobs.step(job, 250)
  equal(job.chunk_reads, 0)
  local most = math.max(1, math.floor(250 / grid.REGION_UNITS))
  check(job.region_builds >= 1 and job.region_builds <= most, "builds within the budget: " .. job.region_builds)
  equal(job.effort, used)
  check(job.effort >= job.region_builds * grid.REGION_UNITS, "each build is charged")
  finish(job)
  equal(job.stage, "ready")
  equal(job.chunk_reads, 0)
  check(job.region_builds >= 4, "every chunk on the way had its regions built")
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

test("jobs: an abstract search saved with a flat heap starts over", function()
  fresh(wide(200, 96, 100, 80))
  local job = long_job(5, 5)
  jobs.step(job, 3)
  equal(job.stage, "abstract")
  -- The previous heap layout: one flat array of keys and one of values.
  job.abstract.open = {keys = {}, vals = {}, n = 0}
  finish(job)
  equal(job.stage, "ready")
end)

test("jobs: a refine search saved with separate g, parent and closed tables starts over with the same route", function()
  local rows = {"..........", "....|.....", ".........."}
  local function make()
    return jobs.create{surface_index = 1, force = "player", starts = {{x = 0, y = 1, d = 1}},
      goal = {x = 9, y = 1, headings = ALL, place = true}, tier = TIER, layout = "belts", placement = "ghost"}
  end
  fresh(rows)
  local whole = run(make())
  local job = make()
  jobs.step(job, 3)
  equal(job.stage, "refine")
  -- The previous layout: box ids, but one table each for g, parent and closed.
  local s = job.search
  s.nodes, s.stale_pops, s.pack = nil, nil, nil
  s.g, s.parent, s.closed = {[refine.state_id(s, 0, 1, 1)] = 0}, {[refine.state_id(s, 0, 1, 1)] = -1}, {}
  s.open = {keys = {0}, vals = {refine.state_id(s, 0, 1, 1)}, n = 1}
  run(job)
  equal(job.stage, "ready"); equal(#job.entities, #whole.entities)
  for i, e in ipairs(whole.entities) do
    equal(job.entities[i].x, e.x); equal(job.entities[i].y, e.y); equal(job.entities[i].d, e.d)
  end
end)

test("jobs: stale pops are charged to the budget", function()
  local rows = {}
  for y = 1, 12 do rows[y] = string.rep(".", 40) end
  fresh(rows)
  local job = jobs.create{surface_index = 1, force = "player", starts = {{x = 0, y = 0, d = 1}},
    goal = {x = 39, y = 11, headings = ALL, place = true}, tier = TIER, layout = "belts", placement = "ghost"}
  local s = job.search
  local spent = 0
  for _ = 1, 10000 do
    spent = spent + jobs.step(job, 7)
    if job.stage ~= "refine" then break end
  end
  equal(job.stage, "ready")
  check(s.stale_pops > 0, "the search popped closed states")
  equal(spent, s.expansions + math.floor(s.stale_pops / refine.STALE_PER_UNIT))
  equal(job.effort, spent)
end)

local function budgets(search, build)
  settings.global["auto-belt-search-budget"] = {value = search}
  settings.global["auto-belt-build-batch"] = {value = build}
end

test("scheduler: a completed job cannot precede an oversized read in the same tick", function()
  local rows = {string.rep(".", 100), string.rep(".", 100), string.rep(".", 100)}
  fresh(rows)
  budgets(50, 150)
  local function route(x, goal)
    return jobs.create{surface_index = 1, force = "player", starts = {{x = x, y = 1, d = 1}},
      goal = {x = goal, y = 1, headings = ALL, place = true}, tier = TIER, layout = "belts", placement = "ghost"}
  end
  local a, b = route(0, 1), route(64, 73)
  grid.invalidate_box(1, 64, 0, 95, 31)
  local reads = 0
  with_reads(function() reads = reads + 1; fake.records(rows, 1) end, function()
    scheduler.tick()
    equal(a.stage, "ready")
    equal(reads, 0, "the pending read waits after another job expands")
    check(a.effort + b.effort <= 50, "shared tick budget")
    scheduler.tick()
    equal(reads, 1, "the deferred job reads on the next tick")
    for _ = 1, 100 do
      if b.stage == "ready" then break end
      scheduler.tick()
    end
    equal(b.stage, "ready")
  end)
end)

test("scheduler: spending a share consumes the global overrun allowance", function()
  fresh(wide(200, 64))
  budgets(100, 150)
  local a, b = long_job(5, 5), long_job(50, 50)
  local real_step, spent, reads = jobs.step, 0, 0
  jobs.step = function(job, budget, first)
    if job.id == a.id then spent = spent + budget; return budget end
    if budget >= grid.CHUNK_UNITS or first then
      reads = reads + 1
      spent = spent + grid.CHUNK_UNITS
      return grid.CHUNK_UNITS
    end
    return 0
  end
  local ok, err = pcall(function()
    scheduler.tick()
    check(spent <= 100, "shared tick spent " .. spent)
    equal(reads, 0)
    spent = 0
    scheduler.tick()
    equal(reads, 1, "rotation gives the waiting job the next first share")
    check(spent <= 100, "rotated tick spent " .. spent)
  end)
  jobs.step = real_step
  if not ok then error(err) end
end)

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
