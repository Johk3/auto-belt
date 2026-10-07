local t = storage.ab_blocked
local J, B = AUTO_BELT.jobs, AUTO_BELT.builder
local s = game.surfaces["auto-belt-test"]
if not s then
  s = game.create_surface("auto-belt-test")
  s.generate_with_lab_tiles = true
  s.request_to_generate_chunks({0, 0}, 8)
  s.force_generate_chunk_requests()
end
local TIER = AUTO_BELT.tiers.get("transport-belt")
local ALL = {[0] = true, [1] = true, [2] = true, [3] = true}
if not t then
  for _, e in pairs(s.find_entities{{-5, 165}, {60, 185}}) do e.destroy() end
  local job = J.create{surface_index = s.index, force = "player", starts = {{x = 0, y = 175, d = 1}},
    goal = {x = 30, y = 175, headings = ALL, place = true}, tier = TIER, layout = "belts", placement = "free"}
  storage.ab_blocked = {job = job.id}
  return "WAIT: routing"
end
local job = storage.jobs[t.job]
if job and job.stage == "refine" then return "WAIT: routing" end
if job then
  if job.stage ~= "ready" then error("job ended " .. job.stage .. " " .. tostring(job.error)) end
  t.entities = job.entities
  local tile = job.entities[10]
  t.tile = {x = tile.x, y = tile.y}
  s.create_entity{name = "wooden-chest", position = {tile.x + 0.5, tile.y + 0.5}, force = "player"}
  AUTO_BELT.ab_saved_done = AUTO_BELT.scheduler.on_build_done
  AUTO_BELT.scheduler.on_build_done = function(build) storage.ab_blocked.result = build end
  t.build = B.start(job).id
  J.remove(job)
  return "WAIT: building"
end
if storage.builds[t.build] or not t.result then return "WAIT: building" end
AUTO_BELT.scheduler.on_build_done = AUTO_BELT.ab_saved_done
AUTO_BELT.ab_saved_done = nil
storage.ab_blocked = nil
local b = t.result.blocked
if not b or b.x ~= t.tile.x or b.y ~= t.tile.y then error("blocked tile wrong") end
if t.result.next ~= 10 then error("next is " .. tostring(t.result.next)) end
local last = t.entities[9]
if not t.result.last or t.result.last.x ~= last.x or t.result.last.y ~= last.y then error("last wrong") end
for i = 1, 9 do
  local e = t.entities[i]
  if #s.find_entities_filtered{position = {e.x + 0.5, e.y + 0.5}, type = {"transport-belt", "underground-belt"}} ~= 1 then
    error("entity " .. i .. " missing")
  end
end
return "PASS: build stops at the blocked tile and keeps earlier entities"
