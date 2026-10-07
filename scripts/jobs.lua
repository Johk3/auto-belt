-- Route jobs: one per planned route. All state is plain data in storage.jobs.
-- The search only advances inside jobs.step, which the scheduler budgets.
local cells = require("scripts.cells")
local refine = require("scripts.refine")
local hpa = require("scripts.hpa")
local layout = require("scripts.layout")
local grid = require("scripts.grid")
local builder = require("scripts.builder")

local jobs = {}

local PAD = 32
local DX, DY = cells.DX, cells.DY

jobs.SHORT = 96
local LONG_WEIGHT10 = 12

-- True while the job still has a search to run.
function jobs.searching(job)
  return job.stage == "abstract" or job.stage == "refine"
end

function jobs.create(p)
  storage.jobs = storage.jobs or {}
  local id = storage.next_id or 1
  storage.next_id = id + 1
  local tier = {belt = p.tier.belt, underground = p.tier.underground,
    max_distance = p.tier.max_distance or 0, speed = p.tier.speed}
  local starts, goal = {}, p.goal
  local x1, y1, x2, y2 = goal.x, goal.y, goal.x, goal.y
  local near = math.huge
  for i, s in ipairs(p.starts) do
    starts[i] = {x = s.x, y = s.y, d = s.d}
    x1, x2 = math.min(x1, s.x), math.max(x2, s.x)
    y1, y2 = math.min(y1, s.y), math.max(y2, s.y)
    near = math.min(near, math.abs(s.x - goal.x) + math.abs(s.y - goal.y))
  end
  local headings = {}
  for d in pairs(goal.headings) do headings[d] = true end
  goal = {x = goal.x, y = goal.y, headings = headings, place = goal.place}
  local job = {
    id = id, surface_index = p.surface_index,
    force = type(p.force) == "string" and p.force or p.force.name,
    player_index = p.player_index, starts = starts, goal = goal, tier = tier,
    layout = p.layout, placement = p.placement, stage = "refine", effort = 0, chunk_reads = 0,
  }
  if near < jobs.SHORT then
    job.search = refine.new{
      starts = starts, goal = goal, mode = p.layout,
      region = {x1 = x1 - PAD, y1 = y1 - PAD, x2 = x2 + PAD, y2 = y2 + PAD},
      max_distance = tier.underground and tier.max_distance or 0,
      weight10 = 10,
    }
  else
    local approach = {}
    if goal.place then
      approach[1] = {x = goal.x, y = goal.y}
    else
      for h in pairs(goal.headings) do approach[#approach + 1] = {x = goal.x - DX[h], y = goal.y - DY[h]} end
      table.sort(approach, function(a, b) if a.x ~= b.x then return a.x < b.x end return a.y < b.y end)
    end
    job.stage, job.ring = "abstract", 1
    job.abstract = hpa.new{start = {x = starts[1].x, y = starts[1].y}, goals = approach,
      goal_point = {x = goal.x, y = goal.y}}
  end
  storage.jobs[id] = job
  if AUTO_BELT and AUTO_BELT.update_tick then AUTO_BELT.update_tick() end
  return job
end

local function fail(job, error_key)
  local closest = job.search and job.search.closest
  if closest then
    job.closest = {x = closest.x, y = closest.y}
  else
    job.closest = {x = job.starts[1].x, y = job.starts[1].y}
  end
  job.stage, job.error, job.search, job.abstract = "failed", error_key, nil, nil
end

local function finish(job)
  local entities = layout.build(job.search.result, job.goal, job.tier)
  if not entities then return fail(job, "auto-belt.no-route") end
  job.entities, job.tiles = entities, layout.tiles(entities)
  job.stage, job.search = "ready", nil
end

-- Starts the refinement of a long route inside the corridor around job.chunks.
local function start_refine(job)
  local tier = job.tier
  job.search = refine.new{
    starts = job.starts, goal = job.goal, mode = job.layout,
    region = {chunks = hpa.corridor(job.chunks, job.ring)},
    max_distance = tier.underground and tier.max_distance or 0,
    weight10 = LONG_WEIGHT10,
  }
end

local function refine_failed(job)
  if job.ring == 1 then
    job.ring = 2
    start_refine(job)
  else
    fail(job, "auto-belt.no-route")
  end
end

-- Reads one chunk the search asked for. Returns false when the job failed.
local function read(job, cx, cy)
  local surface = game.get_surface(job.surface_index)
  if not surface then fail(job, "auto-belt.no-route"); return false end
  grid.read_chunk(surface, cx, cy)
  job.effort = job.effort + grid.CHUNK_UNITS
  job.chunk_reads = (job.chunk_reads or 0) + 1
  if job.chunk_reads > grid.CAP / 2 then fail(job, "auto-belt.search-limit"); return false end
  return true
end

-- Advances the search by up to `budget` units; returns the units used.
function jobs.step(job, budget)
  if not jobs.searching(job) then return 0 end
  local max_effort = settings.global["auto-belt-max-effort"].value
  budget = math.min(budget, max_effort - job.effort)
  if budget <= 0 then fail(job, "auto-belt.search-limit"); return 0 end
  local remaining = budget
  while remaining > 0 and jobs.searching(job) do
    if job.stage == "abstract" then
      local status, used = hpa.step(job.abstract, remaining, grid.regions_reader(job.surface_index))
      remaining = remaining - used
      job.effort = job.effort + used
      if status == "found" then
        job.chunks, job.abstract, job.stage = job.abstract.chunks, nil, "refine"
        start_refine(job)
      elseif status == "failed" then
        fail(job, "auto-belt.no-route")
      elseif status == "need" then
        local need = job.abstract.need
        if read(job, need.cx, need.cy) then remaining = remaining - grid.CHUNK_UNITS end
      end
    else
      local status, used = refine.step(job.search, remaining, grid.reader(job.surface_index))
      remaining = remaining - used
      job.effort = job.effort + used
      if status == "found" then
        finish(job)
      elseif status == "failed" then
        refine_failed(job)
      elseif status == "need" then
        local cx, cy = cells.chunk_of(job.search.need.x, job.search.need.y)
        if read(job, cx, cy) then remaining = remaining - grid.CHUNK_UNITS end
      end
    end
  end
  if jobs.searching(job) and job.effort >= max_effort then fail(job, "auto-belt.search-limit") end
  return budget - remaining
end

function jobs.remove(job)
  if storage.jobs then storage.jobs[job.id] = nil end
  builder.clear(job.renders)
  if AUTO_BELT and AUTO_BELT.update_tick then AUTO_BELT.update_tick() end
end

return jobs
