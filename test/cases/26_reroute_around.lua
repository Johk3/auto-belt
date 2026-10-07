local t = storage.ab_reroute
local J, B, P = AUTO_BELT.jobs, AUTO_BELT.builder, AUTO_BELT.planner
local s = game.surfaces["auto-belt-test"]
if not s then
  s = game.create_surface("auto-belt-test")
  s.generate_with_lab_tiles = true
  s.request_to_generate_chunks({0, 0}, 8)
  s.force_generate_chunk_requests()
end
local TIER = AUTO_BELT.tiers.get("transport-belt")
local ALL = {[0] = true, [1] = true, [2] = true, [3] = true}
local Y = -40
local function build_now(job)
  local build = B.start(job)
  J.remove(job)
  storage.builds[build.id] = nil
  AUTO_BELT.update_tick()
  local status = B.step(build, 1000)
  return build, status
end
if not t then
  for _, e in pairs(s.find_entities{{-5, Y - 15}, {60, Y + 15}}) do e.destroy() end
  local job = J.create{surface_index = s.index, force = "player", starts = {{x = 0, y = Y, d = 1}},
    goal = {x = 30, y = Y, headings = ALL, place = true}, tier = TIER, layout = "belts", placement = "free"}
  storage.ab_reroute = {job = job.id}
  return "WAIT: routing"
end
local job = storage.jobs[t.job]
if job and job.stage == "refine" then return "WAIT: routing" end
if not job then error("job gone") end
if job.stage ~= "ready" then error("job ended " .. job.stage .. " " .. tostring(job.error)) end
if not t.rerouted then
  local tile = job.entities[10]
  s.create_entity{name = "wooden-chest", position = {tile.x + 0.5, tile.y + 0.5}, force = "player"}
  local build, status = build_now(job)
  if status ~= "blocked" or build.blocked.x ~= tile.x then error("build did not block at the chest: " .. status) end
  local job2, error_key = P.reroute_job(P.reroute_record(build), s)
  if not job2 then error("reroute failed: " .. tostring(error_key)) end
  storage.ab_reroute = {job = job2.id, rerouted = true}
  return "WAIT: rerouting"
end
local _, status = build_now(job)
storage.ab_reroute = nil
if status ~= "done" then error("rerouted build " .. status) end
local seen, e = 0, s.find_entities_filtered{position = {0.5, Y + 0.5}, type = "transport-belt"}[1]
while e and seen < 200 do
  seen = seen + 1
  if e.position.x == 30.5 and e.position.y == Y + 0.5 then break end
  if e.type == "underground-belt" and e.belt_to_ground_type == "input" then e = e.neighbours
  else e = e.belt_neighbours.outputs[1] end
end
if not e or e.position.x ~= 30.5 or e.position.y ~= Y + 0.5 then error("chain broken after " .. seen .. " entities") end
return "PASS: reroute backs off and passes a blocker that is still there, " .. seen .. " entities in the chain"
