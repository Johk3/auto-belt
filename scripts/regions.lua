-- Splits one chunk into connected regions of passable tiles (4-neighbour flood fill).
local cells = require("scripts.cells")
local band = bit32.band
local regions = {}
local MAX = 254

function regions.passable(m)
  return band(m, cells.WALL) == 0 and (band(m, cells.BLOCKED) == 0 or band(m, cells.THIN) ~= 0)
end

function regions.build(str)
  local labels, centroids, count = {}, {}, 0
  for i = 1, 1024 do labels[i] = 0 end
  local stack = {}
  for i = 1, 1024 do
    if labels[i] == 0 and regions.passable(string.byte(str, i)) then
      count = count + 1
      local label = count <= MAX and count or 255
      local sx, sy, n, top = 0, 0, 0, 1
      stack[1] = i
      labels[i] = label
      while top > 0 do
        local j = stack[top]; top = top - 1
        local x = (j - 1) % 32
        local y = (j - 1 - x) / 32
        sx, sy, n = sx + x, sy + y, n + 1
        local function visit(k)
          if labels[k] == 0 and regions.passable(string.byte(str, k)) then
            labels[k] = label; top = top + 1; stack[top] = k
          end
        end
        if x > 0 then visit(j - 1) end
        if x < 31 then visit(j + 1) end
        if y > 0 then visit(j - 32) end
        if y < 31 then visit(j + 32) end
      end
      if label ~= 255 then centroids[label] = {x = math.floor(sx / n + 0.5), y = math.floor(sy / n + 0.5)} end
    end
  end
  local chars = {}
  for i = 1, 1024 do chars[i] = string.char(labels[i]) end
  return {labels = table.concat(chars), count = math.min(count, MAX), centroids = centroids}
end

function regions.label(rec, lx, ly)
  local label = string.byte(rec.labels, ly * 32 + lx + 1)
  return label == 255 and 0 or label
end

return regions
