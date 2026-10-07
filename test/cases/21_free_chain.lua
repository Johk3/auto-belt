local t = storage.ab_free_chain
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
  for _, e in pairs(s.find_entities{{-5, 95}, {60, 125}}) do e.destroy() end
  for y = 100, 120 do s.create_entity{name = "transport-belt", position = {20.5, y + 0.5}, direction = defines.direction.south, force = "player"} end
  local job = J.create{surface_index = s.index, force = "player", starts = {{x = 0, y = 110, d = 1}},
    goal = {x = 40, y = 110, headings = ALL, place = true}, tier = TIER, layout = "belts", placement = "free"}
  storage.ab_free_chain = {job = job.id}
  return "WAIT: routing"
end
local job = storage.jobs[t.job]
if job and job.stage == "refine" then return "WAIT: routing" end
if job then
  if job.stage ~= "ready" then error("job ended " .. job.stage .. " " .. tostring(job.error)) end
  t.entities = job.entities
  t.build = B.start(job).id
  J.remove(job)
  return "WAIT: building"
end
if storage.builds[t.build] then return "WAIT: building" end
local first = s.find_entities_filtered{position = {0.5, 110.5}, type = {"transport-belt", "underground-belt"}}[1]
local seen, e = 0, first
while e and seen < 200 do
  seen = seen + 1
  if e.position.x == 40.5 and e.position.y == 110.5 then break end
  if e.type == "underground-belt" and e.belt_to_ground_type == "input" then e = e.neighbours
  else e = e.belt_neighbours.outputs[1] end
end
storage.ab_free_chain = nil
if not e or e.position.x ~= 40.5 then error("belt chain broken after " .. seen .. " entities") end
if seen ~= #t.entities then error("chain length " .. seen .. " vs entities " .. #t.entities) end
return "PASS: free route forms one connected belt chain"
