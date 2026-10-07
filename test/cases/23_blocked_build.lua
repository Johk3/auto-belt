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
if t.stage == "reroute" then
  local job2 = storage.jobs[t.job2]
  if job2 and job2.stage == "refine" then return "WAIT: rerouting" end
  if job2 then
    if job2.stage ~= "ready" then error("reroute ended " .. job2.stage .. " " .. tostring(job2.error)) end
    t.build2 = B.start(job2).id
    J.remove(job2)
    return "WAIT: rebuilding"
  end
  if storage.builds[t.build2] then return "WAIT: rebuilding" end
  storage.ab_blocked = nil
  local seen, e = 0, s.find_entities_filtered{position = {0.5, 175.5}, type = "transport-belt"}[1]
  while e and seen < 200 do
    seen = seen + 1
    if e.position.x == 30.5 and e.position.y == 175.5 then break end
    if e.type == "underground-belt" and e.belt_to_ground_type == "input" then e = e.neighbours
    else e = e.belt_neighbours.outputs[1] end
  end
  if not e or e.position.x ~= 30.5 or e.position.y ~= 175.5 then error("rerouted chain broken after " .. seen .. " entities") end
  return "PASS: build stops at the blocked tile, keeps earlier entities, and the reroute completes the chain"
end
if storage.builds[t.build] or not t.result then return "WAIT: building" end
AUTO_BELT.scheduler.on_build_done = AUTO_BELT.ab_saved_done
AUTO_BELT.ab_saved_done = nil
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
local r = AUTO_BELT.planner.reroute_record(t.result)
if not r.start or r.start.x ~= last.x or r.start.y ~= last.y or r.start.d ~= t.entities[8].d then error("reroute start wrong") end
s.find_entities_filtered{position = {t.tile.x + 0.5, t.tile.y + 0.5}, name = "wooden-chest"}[1].destroy()
local job2, error_key = AUTO_BELT.planner.reroute_job(r, s)
if not job2 then error("reroute failed: " .. tostring(error_key)) end
if #s.find_entities_filtered{position = {last.x + 0.5, last.y + 0.5}, type = "transport-belt"} ~= 0 then error("last belt not removed") end
t.stage, t.job2 = "reroute", job2.id
return "WAIT: rerouting"
