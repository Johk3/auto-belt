-- Belt tiers from the loaded prototypes: belt, paired underground and reach.
local tiers = {}

local cached

function tiers.list()
  if cached then return cached end
  local list = {}
  local belts = prototypes.get_entity_filtered{{filter = "type", type = "transport-belt"}}
  for name, p in pairs(belts) do
    local ug = p.related_underground_belt
    list[#list + 1] = {
      belt = name,
      underground = ug and ug.name or nil,
      max_distance = ug and ug.max_underground_distance or 0,
      speed = p.belt_speed,
    }
  end
  table.sort(list, function(a, b)
    if a.speed ~= b.speed then return a.speed < b.speed end
    return a.belt < b.belt
  end)
  cached = list
  return list
end

function tiers.get(belt_name)
  for _, t in ipairs(tiers.list()) do
    if t.belt == belt_name then return t end
  end
end

function tiers.for_speed(speed)
  for _, t in ipairs(tiers.list()) do
    if math.abs(t.speed - speed) < 1e-9 then return t end
  end
end

-- Longest run of blocked tiles an underground can tunnel under, clamped to 4..10.
function tiers.longest_gap()
  local gap = 4
  for _, t in ipairs(tiers.list()) do
    gap = math.max(gap, t.max_distance - 1)
  end
  return math.min(gap, 10)
end

return tiers
