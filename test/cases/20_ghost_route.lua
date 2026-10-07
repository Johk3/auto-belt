local t = storage.ab_ghost_route
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
  for _, e in pairs(s.find_entities{{-5, 50}, {60, 90}}) do e.destroy() end
  for y = 60, 80 do s.create_entity{name = "transport-belt", position = {20.5, y + 0.5}, direction = defines.direction.south, force = "player"} end
  local job = J.create{surface_index = s.index, force = "player", starts = {{x = 0, y = 70, d = 1}},
    goal = {x = 40, y = 70, headings = ALL, place = true}, tier = TIER, layout = "belts", placement = "ghost"}
  storage.ab_ghost_route = {job = job.id}
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
local underground = 0
for _, e in ipairs(t.entities) do
  local ghosts = s.find_entities_filtered{position = {e.x + 0.5, e.y + 0.5}, name = "entity-ghost"}
  local ghost = ghosts[1]
  if not ghost then error("no ghost at " .. e.x .. "," .. e.y) end
  if ghost.ghost_name ~= e.name then error("ghost " .. ghost.ghost_name .. " vs " .. e.name .. " at " .. e.x .. "," .. e.y) end
  if e.kind ~= "belt" then
    underground = underground + 1
    if ghost.belt_to_ground_type ~= e.kind then error("ghost type " .. tostring(ghost.belt_to_ground_type) .. " vs " .. e.kind) end
  end
end
storage.ab_ghost_route = nil
if #t.entities < 40 then error("route too short: " .. #t.entities) end
return "PASS: ghost route, " .. underground .. " underground ghosts typed"
