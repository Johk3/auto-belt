-- Route jobs: one per planned route. All state is plain data in storage.jobs.
-- The search only advances inside jobs.step, which the scheduler budgets.
local cells = require("scripts.cells")
local refine = require("scripts.refine")
local layout = require("scripts.layout")
local grid = require("scripts.grid")

local jobs = {}

local PAD = 32
local SHORT = 96

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
    layout = p.layout, placement = p.placement, stage = "refine", effort = 0,
  }
  job.search = refine.new{
    starts = starts, goal = goal, mode = p.layout,
    region = {x1 = x1 - PAD, y1 = y1 - PAD, x2 = x2 + PAD, y2 = y2 + PAD},
    max_distance = tier.underground and tier.max_distance or 0,
    weight10 = near < SHORT and 10 or 12,
  }
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
  job.stage, job.error, job.search = "failed", error_key, nil
end

local function finish(job)
  local entities = layout.build(job.search.result, job.goal, job.tier)
  if not entities then return fail(job, "auto-belt.no-route") end
  job.entities, job.tiles = entities, layout.tiles(entities)
  job.stage, job.search = "ready", nil
end

-- Advances the search by up to `budget` units; returns the units used.
function jobs.step(job, budget)
  if job.stage ~= "refine" then return 0 end
  local max_effort = settings.global["auto-belt-max-effort"].value
  budget = math.min(budget, max_effort - job.effort)
  if budget <= 0 then fail(job, "auto-belt.search-limit"); return 0 end
  local remaining = budget
  local cell = grid.reader(job.surface_index)
  while remaining > 0 and job.stage == "refine" do
    local status, used = refine.step(job.search, remaining, cell)
    remaining = remaining - used
    job.effort = job.effort + used
    if status == "found" then
      finish(job)
    elseif status == "failed" then
      fail(job, "auto-belt.no-route")
    elseif status == "need" then
      local surface = game.get_surface(job.surface_index)
      if not surface then
        fail(job, "auto-belt.no-route")
      else
        local cx, cy = cells.chunk_of(job.search.need.x, job.search.need.y)
        grid.read_chunk(surface, cx, cy)
        remaining = remaining - grid.CHUNK_UNITS
        job.effort = job.effort + grid.CHUNK_UNITS
        cell = grid.reader(job.surface_index)
      end
    end
  end
  if job.stage == "refine" and job.effort >= max_effort then fail(job, "auto-belt.search-limit") end
  return budget - remaining
end

function jobs.remove(job)
  if storage.jobs then storage.jobs[job.id] = nil end
  for _, object in pairs(job.renders or {}) do
    if object.valid then object.destroy() end
  end
end

return jobs
