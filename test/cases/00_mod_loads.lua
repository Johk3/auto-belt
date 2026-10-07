if script.active_mods["auto-belt"] ~= "__MOD_VERSION__" then error("auto-belt not active") end
if not AUTO_BELT then error("AUTO_BELT missing") end
local s = game.surfaces["auto-belt-test"]
if not s then
  s = game.create_surface("auto-belt-test")
  s.generate_with_lab_tiles = true
  s.request_to_generate_chunks({0, 0}, 8)
  s.force_generate_chunk_requests()
end
return "PASS: mod loads"
