local t = storage.ab_invalid
local J = AUTO_BELT.jobs
local s = game.surfaces["auto-belt-test"]
if not s then
  s = game.create_surface("auto-belt-test")
  s.generate_with_lab_tiles = true
  s.request_to_generate_chunks({0, 0}, 8)
  s.force_generate_chunk_requests()
end
s.request_to_generate_chunks({330, 330}, 3)
s.force_generate_chunk_requests()
local TIER = AUTO_BELT.tiers.get("transport-belt")
local ALL = {[0] = true, [1] = true, [2] = true, [3] = true}
if not t then
  for _, e in pairs(s.find_entities{{290, 310}, {390, 350}}) do e.destroy() end
  storage.grid = nil
  AUTO_BELT.grid.read_chunk(s, 10, 10)
  if AUTO_BELT.grid.reader(s.index)(325, 325) == nil then error("chunk (10, 10) not cached after read") end
  if not s.create_entity{name = "wooden-chest", position = {325.5, 325.5}, force = "player", raise_built = true} then error("chest not created") end
  if AUTO_BELT.grid.reader(s.index)(325, 325) ~= nil then error("cache record survived a built chest") end
  local job = J.create{surface_index = s.index, force = "player", starts = {{x = 300, y = 325, d = 1}},
    goal = {x = 350, y = 325, headings = ALL, place = true}, tier = TIER, layout = "belts", placement = "free"}
  storage.ab_invalid = {job = job.id}
  return "WAIT: routing"
end
local job = storage.jobs[t.job]
if job and J.searching(job) then return "WAIT: routing" end
storage.ab_invalid = nil
if not job then error("job gone") end
if job.stage ~= "ready" then error("job ended " .. job.stage .. " " .. tostring(job.error)) end
local n = #job.entities
for _, x in ipairs(job.entities) do
  if x.x == 325 and x.y == 325 then error("planned entity sits on the chest tile") end
end
J.remove(job)
return "PASS: built chest drops the cached chunk and the route avoids it, " .. n .. " entities"
