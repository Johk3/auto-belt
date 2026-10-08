local L = __LENGTH__
local NS = __NS__ -- the route runs south instead of east
local WARM = __WARM__ -- keep the obstacles and the chunk cache of the previous run
local J = AUTO_BELT.jobs
-- (a, c): a along the route, c across it.
local function at(a, c) if NS then return {c, a} else return {a, c} end end
game.tick_paused = true
local s = game.surfaces["auto-belt-bench"]
if not s then
  s = game.create_surface("auto-belt-bench")
  s.generate_with_lab_tiles = true
end
if not WARM then
  for a = 0, L + 64, 96 do s.request_to_generate_chunks(at(a, 0), 5) end
  s.force_generate_chunk_requests()
  -- Clear both route strips, so obstacles of the other direction stay out of the corridor.
  for _, e in pairs(s.find_entities{{-200, -200}, {L + 128, 200}}) do e.destroy() end
  for _, e in pairs(s.find_entities{{-200, -200}, {200, L + 128}}) do e.destroy() end
  local across = NS and defines.direction.east or defines.direction.north
  for a = 30, L - 30, 30 do
    for c = -30, 29 do
      local p = at(a + 0.5, c + 0.5)
      if not s.create_entity{name = "transport-belt", position = p, direction = across, force = "player"} then error("belt line not placed at " .. p[1] .. "," .. p[2]) end
    end
  end
  for a = 45, L - 45, 90 do
    for da = 0, 11 do
      for c = -6, 5 do
        local p = at(a + da + 0.5, c + 0.5)
        if not s.create_entity{name = "wooden-chest", position = p, force = "player"} then error("chest block not placed at " .. p[1] .. "," .. p[2]) end
      end
    end
  end
  storage.grid = nil
end
storage.scheduler_cursor = nil
for id, job in pairs(storage.jobs or {}) do J.remove(job) end
local goal = at(L, 0)
local job = J.create{surface_index = s.index, force = "player", starts = {{x = 0, y = 0, d = NS and 2 or 1}},
  goal = {x = goal[1], y = goal[2], headings = {[0] = true, [1] = true, [2] = true, [3] = true}, place = true},
  tier = AUTO_BELT.tiers.get("transport-belt"), layout = "belts", placement = "ghost"}
storage.bench_job = job.id
rcon.print("setup " .. job.stage)
