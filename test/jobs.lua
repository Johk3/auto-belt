local fake = require("test.fake_grid")
local jobs = require("scripts.jobs")
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
