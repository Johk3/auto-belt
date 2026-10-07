local s = game.surfaces["auto-belt-test"]
if not s then
  s = game.create_surface("auto-belt-test")
  s.generate_with_lab_tiles = true
  s.request_to_generate_chunks({0, 0}, 8)
  s.force_generate_chunk_requests()
end
local grid, cells = AUTO_BELT.grid, AUTO_BELT.cells
for _, e in pairs(s.find_entities{{0, 0}, {40, 40}}) do e.destroy() end
s.create_entity{name = "assembling-machine-1", position = {5.5, 5.5}, force = "player"}
s.create_entity{name = "transport-belt", position = {10.5, 10.5}, direction = defines.direction.east, force = "player"}
local u1 = s.create_entity{name = "underground-belt", position = {0.5, 14.5}, direction = defines.direction.east, type = "input", force = "player"}
local u2 = s.create_entity{name = "underground-belt", position = {4.5, 14.5}, direction = defines.direction.east, type = "output", force = "player"}
if not (u1.neighbours and u1.neighbours.unit_number == u2.unit_number) then error("underground pair not linked") end
s.set_tiles({{name = "water", position = {20, 20}}})
s.create_entity{name = "tree-01", position = {25.5, 5.5}}
s.create_entity{name = "entity-ghost", inner_name = "transport-belt", position = {3.5, 28.5}, direction = defines.direction.east, force = "player"}
s.create_entity{name = "transport-belt", position = {8.5, 24.5}, direction = defines.direction.north, force = "player"}
for x = 21, 32 do
  for y = 20, 31 do
    if not s.create_entity{name = "wooden-chest", position = {x + 0.5, y + 0.5}, force = "player"} then error("chest block not placed") end
  end
end
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
if not has(at(3, 28), cells.BLOCKED) then error("ghost belt not blocked") end
if not has(at(7, 24), cells.HUG_V) or not has(at(9, 24), cells.HUG_V) then error("north-south belt neighbours lack HUG_V") end
if has(at(7, 24), cells.HUG_H) then error("north-south belt neighbour has HUG_H") end
if not has(at(26, 25), cells.BLOCKED) then error("chest block not blocked") end
if has(at(26, 25), cells.THIN) then error("12 x 12 block should not be thin") end
if has(at(26, 25), cells.WALL) then error("chest block should not be a wall") end
storage.grid = nil
local far = grid.read_chunk(s, 200, 200)
if #far.cells ~= 1024 then error("ungenerated record has wrong size") end
for _, i in ipairs({1, 500, 1024}) do
  local v = string.byte(far.cells, i)
  if not (has(v, cells.BLOCKED) and has(v, cells.WALL)) then error("ungenerated chunk cell " .. i .. " is not BLOCKED+WALL") end
end
return "PASS: grid classifies the map"
