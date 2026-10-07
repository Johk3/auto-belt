-- Runtime entry: event wiring only. Game logic lives in scripts/.
local grid = require("scripts.grid")
local tiers = require("scripts.tiers")

AUTO_BELT = {}
AUTO_BELT.grid = grid
AUTO_BELT.tiers = tiers
AUTO_BELT.cells = require("scripts.cells")
local scheduler = require("scripts.scheduler")
AUTO_BELT.jobs = require("scripts.jobs")
AUTO_BELT.endpoints = require("scripts.endpoints")
AUTO_BELT.scheduler = scheduler
AUTO_BELT.on_tick = scheduler.tick

local function update_tick()
  local busy = next(storage.jobs or {}) ~= nil or next(storage.builds or {}) ~= nil
  script.on_event(defines.events.on_tick, busy and AUTO_BELT.on_tick or nil)
end
AUTO_BELT.update_tick = update_tick

local function setup()
  storage.jobs = storage.jobs or {}
  storage.builds = storage.builds or {}
  storage.players = storage.players or {}
  storage.next_id = storage.next_id or 1
end

script.on_init(function() setup(); update_tick() end)
script.on_configuration_changed(function() setup(); update_tick() end)
script.on_load(function() update_tick() end)

-- Grid invalidation: handlers only drop cache entries.
local function on_entity_event(event) grid.on_entity(event.entity) end
local entity_events = {
  defines.events.on_built_entity, defines.events.on_robot_built_entity,
  defines.events.on_space_platform_built_entity, defines.events.script_raised_built,
  defines.events.script_raised_revive, defines.events.on_player_mined_entity,
  defines.events.on_robot_mined_entity, defines.events.on_space_platform_mined_entity,
  defines.events.on_entity_died, defines.events.script_raised_destroy,
  defines.events.on_player_rotated_entity,
}
script.on_event(entity_events, on_entity_event)

local function on_tile_event(event) grid.on_tiles(event.surface_index, event.tiles) end
script.on_event({
  defines.events.on_player_built_tile, defines.events.on_robot_built_tile,
  defines.events.on_space_platform_built_tile, defines.events.on_player_mined_tile,
  defines.events.on_robot_mined_tile, defines.events.on_space_platform_mined_tile,
  defines.events.script_raised_set_tiles,
}, on_tile_event)

local function on_surface_gone(event) grid.drop_surface(event.surface_index) end
script.on_event(defines.events.on_surface_cleared, on_surface_gone)
script.on_event(defines.events.on_surface_deleted, on_surface_gone)

script.on_event(defines.events.on_chunk_generated, function(event)
  local a = event.area
  grid.invalidate_box(event.surface.index, a.left_top.x, a.left_top.y,
    a.right_bottom.x - 1, a.right_bottom.y - 1)
end)
