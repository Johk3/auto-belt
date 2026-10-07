local t = storage.ab_invalid
local J = AUTO_BELT.jobs
local G = AUTO_BELT.grid
local s = game.surfaces["auto-belt-test"]
if not s then
  s = game.create_surface("auto-belt-test")
  s.generate_with_lab_tiles = true
  s.request_to_generate_chunks({0, 0}, 8)
  s.force_generate_chunk_requests()
end
s.request_to_generate_chunks({330, 330}, 8)
s.force_generate_chunk_requests()
local TIER = AUTO_BELT.tiers.get("transport-belt")
local ALL = {[0] = true, [1] = true, [2] = true, [3] = true}
local function fail(msg)
  if t and t.budget then settings.global["auto-belt-search-budget"] = {value = t.budget} end
  storage.ab_invalid = nil
  error(msg)
end
if not t then
  for _, e in pairs(s.find_entities{{90, 310}, {570, 350}}) do e.destroy() end
  storage.grid = nil
  G.read_chunk(s, 10, 10)
  if G.reader(s.index)(325, 325) == nil then error("chunk (10, 10) not cached after read") end
  if not s.create_entity{name = "wooden-chest", position = {325.5, 325.5}, force = "player", raise_built = true} then error("chest not created") end
  if G.reader(s.index)(325, 325) ~= nil then error("cache record survived a built chest") end
  local job = J.create{surface_index = s.index, force = "player", starts = {{x = 300, y = 325, d = 1}},
    goal = {x = 350, y = 325, headings = ALL, place = true}, tier = TIER, layout = "belts", placement = "free"}
  storage.ab_invalid = {job = job.id, phase = 1}
  return "WAIT: routing"
end
local job = storage.jobs[t.job]
if t.phase == 1 then
  if job and J.searching(job) then return "WAIT: routing" end
  if not job then fail("job gone") end
  if job.stage ~= "ready" then fail("job ended " .. job.stage .. " " .. tostring(job.error)) end
  for _, x in ipairs(job.entities) do
    if x.x == 325 and x.y == 325 then fail("planned entity sits on the chest tile") end
  end
  t.n1 = #job.entities
  J.remove(job)
  for _, e in pairs(s.find_entities{{90, 310}, {570, 350}}) do e.destroy() end
  storage.grid = nil
  t.budget = settings.global["auto-belt-search-budget"].value
  settings.global["auto-belt-search-budget"] = {value = 50}
  local long = J.create{surface_index = s.index, force = "player", starts = {{x = 100, y = 325, d = 1}},
    goal = {x = 560, y = 325, headings = ALL, place = true}, tier = TIER, layout = "belts", placement = "free"}
  if long.stage ~= "abstract" then fail("long route did not start in the abstract stage") end
  t.job, t.phase, t.tick = long.id, 2, game.tick
  return "WAIT: abstract stage"
end
if not job then fail("long job gone") end
if t.phase == 2 then
  if job.stage == "abstract" then
    if game.tick - t.tick > 3000 then fail("abstract stage took over 3000 ticks") end
    return "WAIT: abstract stage"
  end
  if job.stage ~= "refine" then fail("refine window missed, stage " .. job.stage .. " " .. tostring(job.error)) end
  local frontier = job.search.closest and job.search.closest.x or 100
  local cx = frontier + 30
  if cx >= 540 then fail("refine frontier already at x " .. frontier .. ", window missed") end
  t.chest = cx
  if not s.create_entity{name = "wooden-chest", position = {cx + 0.5, 325.5}, force = "player", raise_built = true} then fail("chest not created") end
  if G.reader(s.index)(cx, 325) ~= nil then fail("chest chunk record survived the chest") end
  t.phase = 3
  return "WAIT: refining"
end
if J.searching(job) then
  if game.tick - t.tick > 3000 then fail("refine took over 3000 ticks") end
  return "WAIT: refining"
end
if job.stage ~= "ready" then fail("long job ended " .. job.stage .. " " .. tostring(job.error)) end
for _, x in ipairs(job.entities) do
  if x.x == t.chest and x.y == 325 then fail("long route plans an entity on the chest tile") end
end
local n2 = #job.entities
J.remove(job)
settings.global["auto-belt-search-budget"] = {value = t.budget}
storage.ab_invalid = nil
return "PASS: built chest drops the cached chunk and the route avoids it, " .. t.n1 .. " entities; chest placed during refine is avoided, " .. n2 .. " entities"
