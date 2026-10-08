-- Spends the per-tick search budget over searching jobs and drives builds.
local jobs = require("scripts.jobs")

local scheduler = {}

-- Set by the planner: called once when a job leaves the searching stage.
scheduler.on_job_done = nil
-- Set by the planner: called once when a build finishes or is blocked.
scheduler.on_build_done = nil

local function searching()
  local list = {}
  for _, job in pairs(storage.jobs or {}) do
    if jobs.searching(job) then list[#list + 1] = job end
  end
  table.sort(list, function(a, b) return a.id < b.id end)
  return list
end

function scheduler.tick()
  local budget = settings.global["auto-belt-search-budget"].value
  local list = searching()
  if #list > 1 then
    -- Rotate the start so a small budget does not always serve the same jobs.
    local cursor = (storage.scheduler_cursor or 0) % #list
    storage.scheduler_cursor = cursor + 1
    local rotated = {}
    for i = 1, #list do rotated[i] = list[(i + cursor - 1) % #list + 1] end
    list = rotated
  end
  -- Only a job's first step in the tick may start with a chunk read that
  -- costs more than its share. A job that could use none of its share is
  -- waiting for such a read and is served again next tick.
  local first = true
  while budget > 0 and #list > 0 do
    local share = math.max(50, math.floor(budget / #list))
    local still = {}
    for _, job in ipairs(list) do
      if budget > 0 then
        local used = jobs.step(job, math.min(share, budget), first)
        budget = budget - math.max(used, 1)
        if jobs.searching(job) then
          if used > 0 then still[#still + 1] = job end
        elseif scheduler.on_job_done then
          scheduler.on_job_done(job)
        end
      else
        still[#still + 1] = job
      end
    end
    list = still
    first = false
  end

  local builder = AUTO_BELT and AUTO_BELT.builder
  if builder and next(storage.builds or {}) then
    local left = settings.global["auto-belt-build-batch"].value
    local list = {}
    for _, build in pairs(storage.builds) do list[#list + 1] = build end
    table.sort(list, function(a, b) return a.id < b.id end)
    for _, build in ipairs(list) do
      if left <= 0 then break end
      local status, placed = builder.step(build, left)
      left = left - placed
      if status ~= "running" then
        storage.builds[build.id] = nil
        if scheduler.on_build_done then scheduler.on_build_done(build) end
      end
    end
  end
  if AUTO_BELT and AUTO_BELT.update_tick then AUTO_BELT.update_tick() end
end

return scheduler
