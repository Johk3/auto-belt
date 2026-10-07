local t = storage.ab_long
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
  s.request_to_generate_chunks({0, 0}, 24)
  s.force_generate_chunk_requests()
  for _, e in pairs(s.find_entities{{-5, 295}, {645, 425}}) do e.destroy() end
  for x = 40, 600, 40 do
    for y = 300, 419 do
      if not s.create_entity{name = "transport-belt", position = {x + 0.5, y + 0.5}, direction = defines.direction.north, force = "player"} then error("belt line not placed at " .. x .. "," .. y) end
    end
  end
  for _, b in ipairs({{100, 350}, {300, 340}, {480, 360}}) do
    for x = b[1], b[1] + 19 do
      for y = b[2], b[2] + 19 do
        if not s.create_entity{name = "wooden-chest", position = {x + 0.5, y + 0.5}, force = "player"} then error("chest block not placed at " .. x .. "," .. y) end
      end
    end
  end
  storage.grid = nil
  local job = J.create{surface_index = s.index, force = "player", starts = {{x = 0, y = 360, d = 1}},
    goal = {x = 620, y = 360, headings = ALL, place = true}, tier = TIER, layout = "belts", placement = "free"}
  if job.stage ~= "abstract" then error("long route did not start in the abstract stage: " .. job.stage) end
  storage.ab_long = {job = job.id, tick = game.tick}
  return "WAIT: routing"
end
local job = storage.jobs[t.job]
if job and J.searching(job) then return "WAIT: routing" end
if job then
  if job.stage ~= "ready" then storage.ab_long = nil; error("job ended " .. job.stage .. " " .. tostring(job.error)) end
  if not (job.chunks and #job.chunks > 0) then storage.ab_long = nil; error("job has no abstract chunk path") end
  if not (job.chunk_reads and job.chunk_reads > 0) then storage.ab_long = nil; error("abstract stage read no chunks") end
  t.ticks = game.tick - t.tick
  t.entities = job.entities
  t.build = B.start(job).id
  J.remove(job)
  return "WAIT: building"
end
if storage.builds[t.build] then return "WAIT: building" end
local first = s.find_entities_filtered{position = {0.5, 360.5}, type = {"transport-belt", "underground-belt"}}[1]
local seen, e = 0, first
while e and seen < 2000 do
  seen = seen + 1
  if e.position.x == 620.5 and e.position.y == 360.5 then break end
  if e.type == "underground-belt" and e.belt_to_ground_type == "input" then e = e.neighbours
  else e = e.belt_neighbours.outputs[1] end
end
storage.ab_long = nil
if not e or e.position.x ~= 620.5 or e.position.y ~= 360.5 then error("belt chain broken after " .. seen .. " entities") end
if seen ~= #t.entities then error("chain length " .. seen .. " vs entities " .. #t.entities) end
return "PASS: 620-tile route in " .. t.ticks .. " ticks"
