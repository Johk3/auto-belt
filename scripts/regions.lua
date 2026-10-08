-- Splits one chunk into connected regions of passable tiles (4-neighbour flood fill).
local cells = require("scripts.cells")
local band = bit32.band
local byte, char, floor = string.byte, string.char, math.floor
local unpack = table.unpack or unpack
local WALL, BLOCKED, THIN = cells.WALL, cells.BLOCKED, cells.THIN
local regions = {}
local MAX = 254

function regions.passable(m)
  return band(m, WALL) == 0 and (band(m, BLOCKED) == 0 or band(m, THIN) ~= 0)
end

-- PASSABLE[m] caches regions.passable for every cell byte.
local PASSABLE = {}
for m = 0, 255 do PASSABLE[m] = regions.passable(m) end

-- Scratch tables, fully rewritten by every build: filling fresh tables of
-- 1024 entries on each build costs more than the flood fill itself.
local labels, open, stack = {}, {}, {}

function regions.build(str)
  -- open[i] is true for a passable tile not labelled yet.
  local centroids, count = {}, 0
  for i = 1, 1024 do
    labels[i] = 0
    open[i] = PASSABLE[byte(str, i)]
  end
  for i = 1, 1024 do
    if open[i] then
      count = count + 1
      local label = count <= MAX and count or 255
      local sx, sy, n, top = 0, 0, 0, 1
      stack[1] = i
      labels[i] = label
      open[i] = false
      while top > 0 do
        local j = stack[top]; top = top - 1
        local x = (j - 1) % 32
        local y = (j - 1 - x) / 32
        sx, sy, n = sx + x, sy + y, n + 1
        local k = j - 1
        if x > 0 and open[k] then labels[k] = label; open[k] = false; top = top + 1; stack[top] = k end
        k = j + 1
        if x < 31 and open[k] then labels[k] = label; open[k] = false; top = top + 1; stack[top] = k end
        k = j - 32
        if y > 0 and open[k] then labels[k] = label; open[k] = false; top = top + 1; stack[top] = k end
        k = j + 32
        if y < 31 and open[k] then labels[k] = label; open[k] = false; top = top + 1; stack[top] = k end
      end
      if label ~= 255 then centroids[label] = {x = floor(sx / n + 0.5), y = floor(sy / n + 0.5)} end
    end
  end
  local chars = {}
  for row = 0, 31 do chars[row + 1] = char(unpack(labels, row * 32 + 1, row * 32 + 32)) end
  return {labels = table.concat(chars), count = math.min(count, MAX), centroids = centroids}
end

function regions.label(rec, lx, ly)
  local label = string.byte(rec.labels, ly * 32 + lx + 1)
  return label == 255 and 0 or label
end

return regions
