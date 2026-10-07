-- Runtime entry: event wiring only. Game logic lives in scripts/.
AUTO_BELT = {}

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
