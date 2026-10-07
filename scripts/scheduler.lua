-- Spends the per-tick search budget over searching jobs and drives builds.
local jobs = require("scripts.jobs")

local scheduler = {}

-- Set by the planner: called once when a job leaves the searching stage.
scheduler.on_job_done = nil

local function searching()
  local list = {}
  for _, job in pairs(storage.jobs or {}) do
    if job.stage == "refine" then list[#list + 1] = job end
  end
  table.sort(list, function(a, b) return a.id < b.id end)
  return list
end

function scheduler.tick()
  local budget = settings.global["auto-belt-search-budget"].value
  local list = searching()
  while budget > 0 and #list > 0 do
    local share = math.max(50, math.floor(budget / #list))
    local still = {}
    for _, job in ipairs(list) do
      if budget > 0 then
        local used = jobs.step(job, math.min(share, budget))
        budget = budget - math.max(used, 1)
        if job.stage == "refine" then
          still[#still + 1] = job
        elseif scheduler.on_job_done then
          scheduler.on_job_done(job)
        end
      else
        still[#still + 1] = job
      end
    end
    list = still
  end

  local builder = AUTO_BELT and AUTO_BELT.builder
  if builder then
    local batch = settings.global["auto-belt-build-batch"].value
    for _, build in pairs(storage.builds or {}) do builder.step(build, batch) end
  end
  AUTO_BELT.update_tick()
end

return scheduler
