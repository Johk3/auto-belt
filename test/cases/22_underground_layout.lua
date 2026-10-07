local t = storage.ab_ug_layout
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
  for _, e in pairs(s.find_entities{{-5, 135}, {60, 155}}) do e.destroy() end
  local job = J.create{surface_index = s.index, force = "player", starts = {{x = 0, y = 145, d = 1}},
    goal = {x = 40, y = 145, headings = ALL, place = true}, tier = TIER, layout = "undergrounds", placement = "free"}
  storage.ab_ug_layout = {job = job.id}
  return "WAIT: routing"
end
local job = storage.jobs[t.job]
if job and job.stage == "refine" then return "WAIT: routing" end
if job then
  if job.stage ~= "ready" then error("job ended " .. job.stage .. " " .. tostring(job.error)) end
  t.build = B.start(job).id
  J.remove(job)
  return "WAIT: building"
end
if storage.builds[t.build] then return "WAIT: building" end
local inputs, belts = 0, 0
for _, e in pairs(s.find_entities{{-5, 135}, {60, 155}}) do
  if e.type == "transport-belt" then belts = belts + 1 end
  if e.type == "underground-belt" and e.belt_to_ground_type == "input" then
    inputs = inputs + 1
    local n = e.neighbours
    if not (n and n.valid and n.type == "underground-belt" and n.belt_to_ground_type == "output") then
      error("input at " .. e.position.x .. " has no output neighbour")
    end
  end
end
storage.ab_ug_layout = nil
if inputs < 3 then error("too few undergrounds: " .. inputs) end
if belts > 2 then error("too many belts: " .. belts) end
return "PASS: underground layout, " .. inputs .. " pairs, " .. belts .. " belts"
