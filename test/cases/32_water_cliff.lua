local t = storage.ab_water
local J, B = AUTO_BELT.jobs, AUTO_BELT.builder
local s = game.surfaces["auto-belt-test"]
if not s then
  s = game.create_surface("auto-belt-test")
  s.generate_with_lab_tiles = true
  s.request_to_generate_chunks({0, 0}, 8)
  s.force_generate_chunk_requests()
end
s.request_to_generate_chunks({30, 540}, 4)
s.force_generate_chunk_requests()
local TIER = AUTO_BELT.tiers.get("transport-belt")
local ALL = {[0] = true, [1] = true, [2] = true, [3] = true}
local function build_now(job)
  local build = B.start(job)
  J.remove(job)
  storage.builds[build.id] = nil
  AUTO_BELT.update_tick()
  return B.step(build, 1000)
end
local function walk(y, x2)
  local seen, e = 0, s.find_entities_filtered{position = {0.5, y + 0.5}, type = {"transport-belt", "underground-belt"}}[1]
  while e and seen < 200 do
    seen = seen + 1
    if e.position.x == x2 + 0.5 and e.position.y == y + 0.5 then break end
    if e.type == "underground-belt" and e.belt_to_ground_type == "input" then e = e.neighbours
    else e = e.belt_neighbours.outputs[1] end
  end
  if not e or e.position.x ~= x2 + 0.5 then error("belt chain broken after " .. seen .. " entities") end
  return seen
end
local function pairs_of(entities)
  local n = 0
  for _, x in ipairs(entities) do if x.kind ~= "belt" then n = n + 1 end end
  return n
end
if not t then
  for _, e in pairs(s.find_entities{{-10, 460}, {90, 620}}) do e.destroy() end
  local tiles, restore = {}, {}
  for x = 28, 30 do
    for y = 470, 570 do tiles[#tiles + 1] = {name = "water", position = {x, y}} end
  end
  s.set_tiles(tiles)
  storage.grid = nil
  local job = J.create{surface_index = s.index, force = "player", starts = {{x = 0, y = 520, d = 1}},
    goal = {x = 60, y = 520, headings = ALL, place = true}, tier = TIER, layout = "belts", placement = "free"}
  storage.ab_water = {job = job.id, phase = "water"}
  return "WAIT: routing water"
end
local job = storage.jobs[t.job]
if job and J.searching(job) then return "WAIT: routing" end
if not job then storage.ab_water = nil; error("job gone") end
if job.stage ~= "ready" then storage.ab_water = nil; error("job ended " .. job.stage .. " " .. tostring(job.error)) end
if t.phase == "water" then
  local ug = pairs_of(job.entities)
  if ug ~= 2 then storage.ab_water = nil; error("water route has " .. ug .. " underground entities, need exactly 2") end
  local status = build_now(job)
  if status ~= "done" then storage.ab_water = nil; error("water build " .. status) end
  local seen = walk(520, 60)
  local tiles = {}
  for x = 28, 30 do
    for y = 470, 570 do tiles[#tiles + 1] = {name = "lab-dark-1", position = {x, y}} end
  end
  s.set_tiles(tiles)
  local made = 0
  for x = -40, 80, 4 do
    if s.create_entity{name = "cliff", position = {x, 600}, cliff_orientation = "west-to-east"} then made = made + 1 end
  end
  if made == 0 then storage.ab_water = nil; return "SKIP: cliffs cannot be created on lab tiles" end
  storage.grid = nil
  local job2 = J.create{surface_index = s.index, force = "player", starts = {{x = 30, y = 585, d = 2}},
    goal = {x = 30, y = 615, headings = ALL, place = true}, tier = TIER, layout = "belts", placement = "free"}
  storage.ab_water = {job = job2.id, phase = "cliff", seen = seen, made = made}
  return "WAIT: routing cliff"
end
storage.ab_water = nil
local ug = pairs_of(job.entities)
if ug < 2 then error("cliff route has " .. ug .. " underground entities, need a tunnel") end
local status = build_now(job)
if status ~= "done" then error("cliff build " .. status) end
return "PASS: water crossed with one underground pair (" .. t.seen .. " entities); cliff line (" .. t.made .. " pieces) tunnelled under with " .. ug .. " underground entities"
