-- Tile cell bits, directions and numeric keys shared by every routing module.
local cells = {}

cells.BLOCKED = 1   -- a belt cannot be placed here
cells.WALL = 2      -- an underground cannot pass beneath this tile
cells.HUG_H = 4     -- beside an existing belt running east-west
cells.HUG_V = 8     -- beside an existing belt running north-south
cells.CROWDED = 16  -- beside a machine, inserter, pole or similar
cells.UG_H = 32     -- an east-west underground sits here or passes beneath
cells.UG_V = 64     -- a north-south underground sits here or passes beneath
cells.THIN = 128    -- blocked, but the blocked run is short enough to tunnel under

cells.DX = {[0] = 0, 1, 0, -1}
cells.DY = {[0] = -1, 0, 1, 0}

local band = bit32.band
local OFFSET, SPAN = 1048576, 2097152 -- 2^20, 2^21: room for the whole map

function cells.left(d) return (d + 3) % 4 end
function cells.right(d) return (d + 1) % 4 end
function cells.reverse(d) return (d + 2) % 4 end
function cells.hug_bit(d) return d % 2 == 1 and cells.HUG_H or cells.HUG_V end
function cells.ug_bit(d) return d % 2 == 1 and cells.UG_H or cells.UG_V end
function cells.has(mask, bit) return band(mask, bit) ~= 0 end

function cells.tile_key(x, y) return (x + OFFSET) * SPAN + (y + OFFSET) end
function cells.state_id(x, y, d) return cells.tile_key(x, y) * 4 + d end

function cells.decode(id)
  local d = id % 4
  local rest = (id - d) / 4
  local y = rest % SPAN
  local x = (rest - y) / SPAN
  return x - OFFSET, y - OFFSET, d
end

function cells.chunk_of(x, y) return math.floor(x / 32), math.floor(y / 32) end
function cells.chunk_key(cx, cy) return (cx + 32768) * 65536 + (cy + 32768) end

return cells
