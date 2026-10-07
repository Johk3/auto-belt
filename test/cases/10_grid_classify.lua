local s = game.surfaces["auto-belt-test"]
if not s then
  s = game.create_surface("auto-belt-test")
  s.generate_with_lab_tiles = true
  s.request_to_generate_chunks({0, 0}, 8)
  s.force_generate_chunk_requests()
end
local grid, cells = AUTO_BELT.grid, AUTO_BELT.cells
for _, e in pairs(s.find_entities{{0, 0}, {32, 32}}) do e.destroy() end
s.create_entity{name = "assembling-machine-1", position = {5.5, 5.5}, force = "player"}
s.create_entity{name = "transport-belt", position = {10.5, 10.5}, direction = defines.direction.east, force = "player"}
local u1 = s.create_entity{name = "underground-belt", position = {0.5, 14.5}, direction = defines.direction.east, type = "input", force = "player"}
local u2 = s.create_entity{name = "underground-belt", position = {4.5, 14.5}, direction = defines.direction.east, type = "output", force = "player"}
if not (u1.neighbours and u1.neighbours.unit_number == u2.unit_number) then error("underground pair not linked") end
s.set_tiles({{name = "water", position = {20, 20}}})
s.create_entity{name = "tree-01", position = {25.5, 5.5}}
storage.grid = nil
local rec = grid.read_chunk(s, 0, 0)
local function at(x, y) return string.byte(rec.cells, y * 32 + x + 1) end
local has = cells.has
if not has(at(5, 5), cells.BLOCKED) then error("assembler not blocked") end
if not has(at(3, 5), cells.CROWDED) then error("assembler neighbour not crowded") end
if not has(at(10, 9), cells.HUG_H) then error("belt neighbour lacks HUG_H") end
if not has(at(2, 14), cells.UG_H) then error("tile between underground pair lacks UG_H") end
if has(at(2, 14), cells.BLOCKED) then error("tile between pair should be free") end
if not has(at(20, 20), cells.BLOCKED) then error("water not blocked") end
if not has(at(25, 5), cells.BLOCKED) then error("tree not blocked") end
if at(15, 18) ~= 0 then error("open lab tile not free: " .. at(15, 18)) end
if not has(at(20, 20), cells.THIN) then error("single water tile should be thin") end
return "PASS: grid classifies the map"
