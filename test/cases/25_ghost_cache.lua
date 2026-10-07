local s = game.surfaces["auto-belt-test"]
if not s then
  s = game.create_surface("auto-belt-test")
  s.generate_with_lab_tiles = true
  s.request_to_generate_chunks({0, 0}, 8)
  s.force_generate_chunk_requests()
end
local grid, cells = AUTO_BELT.grid, AUTO_BELT.cells
for _, e in pairs(s.find_entities{{-5, 235}, {60, 255}}) do e.destroy() end
local X, Y = 5, 245
local cx, cy = cells.chunk_of(X, Y)
grid.read_chunk(s, cx, cy)
if grid.reader(s.index)(X, Y) ~= 0 then error("tile not cached free before the ghost") end
local ghost = AUTO_BELT.builder.place(s, "player", {name = "transport-belt", kind = "belt", x = X, y = Y, d = 1}, "ghost", nil)
if not ghost then error("ghost not placed") end
local v = grid.reader(s.index)(X, Y)
if v ~= nil and not cells.has(v, cells.BLOCKED) then error("cache still reads the ghost tile free") end
grid.read_chunk(s, cx, cy)
if not cells.has(grid.reader(s.index)(X, Y), cells.BLOCKED) then error("ghost not read as blocked") end
ghost.order_deconstruction("player")
if ghost.valid then error("ghost still there after deconstruction") end
if grid.reader(s.index)(X, Y) ~= nil then error("cache kept the deconstructed ghost") end
return "PASS: ghost placement and ghost deconstruction drop the cached chunk"
