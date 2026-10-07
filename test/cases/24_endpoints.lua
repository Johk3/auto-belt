local t = storage.ab_endpoints
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
local EP = AUTO_BELT.endpoints
if not t then
  for _, e in pairs(s.find_entities{{-5, 195}, {60, 225}}) do e.destroy() end
  s.create_entity{name = "transport-belt", position = {0.5, 210.5}, direction = defines.direction.east, force = "player"}
  s.create_entity{name = "transport-belt", position = {30.5, 215.5}, direction = defines.direction.east, force = "player"}
  local a = EP.start(s, {x = 0.5, y = 210.5}, "transport-belt")
  if a.error or #a.starts ~= 1 then error("start failed: " .. tostring(a.error)) end
  local st = a.starts[1]
  if st.x ~= 1 or st.y ~= 210 or st.d ~= 1 then error("start wrong") end
  local g = EP.goal(s, {x = 30.5, y = 215.5})
  if g.error then error("goal failed: " .. g.error) end
  if not (g.goal.headings[1] and g.goal.headings[0] and g.goal.headings[2]) or g.goal.headings[3] then
    error("goal headings wrong")
  end
  if g.goal.x ~= 30 or g.goal.y ~= 215 or g.goal.place then error("goal tile wrong") end
  local extra = s.create_entity{name = "transport-belt", position = {1.5, 210.5}, direction = defines.direction.east, force = "player"}
  local c = EP.start(s, {x = 0.5, y = 210.5}, "transport-belt")
  if c.error ~= "auto-belt.start-connected" then error("expected start-connected, got " .. tostring(c.error)) end
  extra.destroy()
  local go = s.create_entity{name = "entity-ghost", inner_name = "underground-belt", position = {5.5, 203.5},
    direction = defines.direction.east, force = "player", type = "output"}
  local gs = EP.start(s, {x = 5.5, y = 203.5}, "transport-belt")
  if gs.error or gs.starts[1].x ~= 6 or gs.starts[1].y ~= 203 or gs.starts[1].d ~= 1 then
    error("ghost output start wrong: " .. tostring(gs.error))
  end
  local gi = s.create_entity{name = "entity-ghost", inner_name = "underground-belt", position = {10.5, 203.5},
    direction = defines.direction.east, force = "player", type = "input"}
  local gg = EP.goal(s, {x = 10.5, y = 203.5})
  if gg.error or not gg.goal.headings[1] or gg.goal.headings[0] or gg.goal.headings[2] or gg.goal.headings[3] then
    error("ghost input goal wrong: " .. tostring(gg.error))
  end
  local ge = EP.goal(s, {x = 5.5, y = 203.5})
  if ge.error ~= "auto-belt.end-not-input" then error("ghost output as goal: " .. tostring(ge.error)) end
  go.destroy()
  gi.destroy()
  local job = J.create{surface_index = s.index, force = "player", starts = a.starts, goal = g.goal,
    tier = a.tier, layout = "belts", placement = "free"}
  storage.ab_endpoints = {job = job.id}
  return "WAIT: routing"
end
local job = storage.jobs[t.job]
if job and job.stage == "refine" then return "WAIT: routing" end
if job then
  if job.stage ~= "ready" then error("job ended " .. job.stage .. " " .. tostring(job.error)) end
  t.count = #job.entities
  t.build = B.start(job).id
  J.remove(job)
  return "WAIT: building"
end
if storage.builds[t.build] then return "WAIT: building" end
local seen, e = 0, s.find_entities_filtered{position = {0.5, 210.5}, type = "transport-belt"}[1]
while e and seen < 200 do
  seen = seen + 1
  if e.position.x == 30.5 and e.position.y == 215.5 then break end
  if e.type == "underground-belt" and e.belt_to_ground_type == "input" then e = e.neighbours
  else e = e.belt_neighbours.outputs[1] end
end
storage.ab_endpoints = nil
if not e or e.position.x ~= 30.5 then error("belt chain broken after " .. seen .. " entities") end
if seen ~= t.count + 2 then error("chain length " .. seen .. " vs " .. t.count + 2) end
return "PASS: endpoint rules and a chain between two clicked belts"
