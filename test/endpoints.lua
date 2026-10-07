local endpoints = require("scripts.endpoints")
local tiers = require("scripts.tiers")
local fake = require("test.fake_grid")

local SPEED = 0.03125
local LIST = {
  {belt = "a-belt", underground = "a-underground", max_distance = 5, speed = SPEED},
  {belt = "b-belt", underground = "b-underground", max_distance = 9, speed = SPEED},
}

-- One entity at (2, 1) facing east on a free map.
local function surface_with(entity)
  storage = {}
  game = {tick = 1}
  fake.records({".....", ".....", "....."}, 1)
  entity.position = {x = 2.5, y = 1.5}
  entity.direction = 4
  return {index = 1, find_entities_filtered = function(f)
    local x, y = math.floor(f.area[1][1]), math.floor(f.area[1][2])
    local ghost = entity.type == "entity-ghost"
    if x ~= 2 or y ~= 1 or (f.ghost_type ~= nil) ~= ghost then return {} end
    return {entity}
  end}
end

local function start_tier(entity)
  local saved = tiers.list
  tiers.list = function() return LIST end
  local ok, result = pcall(endpoints.start, surface_with(entity), {x = 2.5, y = 1.5}, "a-belt")
  tiers.list = saved
  if not ok then error(result) end
  check(not result.error, tostring(result.error))
  return result.tier.belt
end

test("endpoints: a clicked belt or belt ghost keeps its own tier among equal speeds", function()
  equal(start_tier{type = "transport-belt", name = "b-belt", prototype = {belt_speed = SPEED}}, "b-belt")
  equal(start_tier{type = "entity-ghost", name = "entity-ghost", ghost_type = "transport-belt",
    ghost_name = "b-belt", ghost_prototype = {belt_speed = SPEED}}, "b-belt")
  equal(start_tier{type = "underground-belt", name = "b-underground", belt_to_ground_type = "output",
    prototype = {belt_speed = SPEED}}, "a-belt")
end)
