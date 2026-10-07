local L = __LENGTH__
local J = AUTO_BELT.jobs
game.tick_paused = true
local s = game.surfaces["auto-belt-bench"]
if not s then
  s = game.create_surface("auto-belt-bench")
  s.generate_with_lab_tiles = true
end
for x = 0, L + 64, 96 do s.request_to_generate_chunks({x, 0}, 5) end
s.force_generate_chunk_requests()
for _, e in pairs(s.find_entities{{-64, -200}, {L + 128, 200}}) do e.destroy() end
for x = 30, L - 30, 30 do
  for y = -30, 29 do
    if not s.create_entity{name = "transport-belt", position = {x + 0.5, y + 0.5}, direction = defines.direction.north, force = "player"} then error("belt line not placed at " .. x .. "," .. y) end
  end
end
for x = 45, L - 45, 90 do
  for dx = 0, 11 do
    for dy = -6, 5 do
      if not s.create_entity{name = "wooden-chest", position = {x + dx + 0.5, dy + 0.5}, force = "player"} then error("chest block not placed at " .. x .. "," .. dy) end
    end
  end
end
storage.grid = nil
storage.scheduler_cursor = nil
for id, job in pairs(storage.jobs or {}) do J.remove(job) end
local job = J.create{surface_index = s.index, force = "player", starts = {{x = 0, y = 0, d = 1}},
  goal = {x = L, y = 0, headings = {[0] = true, [1] = true, [2] = true, [3] = true}, place = true},
  tier = AUTO_BELT.tiers.get("transport-belt"), layout = "belts", placement = "ghost"}
storage.bench_job = job.id
rcon.print("setup " .. job.stage)
