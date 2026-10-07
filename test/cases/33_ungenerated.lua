local t = storage.ab_ungen
local J = AUTO_BELT.jobs
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
  s.request_to_generate_chunks({0, 0}, 8)
  s.force_generate_chunk_requests()
  for _, e in pairs(s.find_entities{{-5, -215}, {60, -185}}) do e.destroy() end
  if s.is_chunk_generated{93, -7} then error("goal chunk is generated") end
  storage.grid = nil
  local job = J.create{surface_index = s.index, force = "player", starts = {{x = 20, y = -200, d = 1}},
    goal = {x = 3000, y = -200, headings = ALL, place = true}, tier = TIER, layout = "belts", placement = "free"}
  storage.ab_ungen = {job = job.id, tick = game.tick}
  return "WAIT: routing"
end
local job = storage.jobs[t.job]
if job and J.searching(job) then
  if game.tick - t.tick > 3000 then storage.ab_ungen = nil; error("job still searching after 3000 ticks, stage " .. job.stage) end
  return "WAIT: routing"
end
storage.ab_ungen = nil
if not job then error("job gone") end
local stage, key, ticks = job.stage, job.error, game.tick - t.tick
J.remove(job)
if stage ~= "failed" then error("job ended " .. stage .. ", expected failed") end
if key ~= "auto-belt.no-route" and key ~= "auto-belt.search-limit" then error("unexpected error " .. tostring(key)) end
return "PASS: route into ungenerated chunks fails with " .. key .. " after " .. ticks .. " ticks"
