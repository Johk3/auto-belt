local planner = require("scripts.planner")
local panel = require("scripts.panel")
local endpoints = require("scripts.endpoints")
local jobs = require("scripts.jobs")
local builder = require("scripts.builder")
local layout = require("scripts.layout")
require("scripts.grid")
require("scripts.tiers")
require("scripts.scheduler")
require("scripts.cells")
local ALL = {[0] = true, [1] = true, [2] = true, [3] = true}
local TIER = {belt = "transport-belt", underground = "underground-belt", max_distance = 5}

local function setup()
  storage = {jobs = {}, builds = {}, players = {}, next_id = 1}
  settings = {global = {["auto-belt-max-effort"] = {value = 5000000}, ["auto-belt-allow-free"] = {value = true},
    ["auto-belt-build-batch"] = {value = 150}, ["auto-belt-search-budget"] = {value = 600}}}
  local player = fake_player()
  game = {tick = 1, players = {[1] = player}, get_player = function() return player end,
    get_surface = function() return player.surface end}
  endpoints.start = function() return {starts = {{x = 3, y = 4, d = 1}}, tier = TIER} end
  endpoints.goal = function() return {goal = {x = 9, y = 4, headings = ALL, place = true}} end
  return player
end

local function click(x, y)
  return {player_index = 1, item = "auto-belt-planner", surface = game.players[1].surface,
    area = {left_top = {x = x, y = y}, right_bottom = {x = x, y = y}}}
end

local function count(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end
local function said(player, key)
  for _, f in ipairs(player.flying) do
    local text = f.text
    if text == key or (type(text) == "table" and text[1] == key) then return true end
  end
  return false
end

local function ready_job(player_index)
  local job = jobs.create{surface_index = 1, force = "player", player_index = player_index, starts = {{x = 3, y = 4, d = 1}},
    goal = {x = 4, y = 4, headings = ALL, place = true}, tier = TIER, layout = "belts", placement = "ghost"}
  job.stage = "ready"
  job.search = nil
  job.entities = {{name = "transport-belt", kind = "belt", x = 3, y = 4, d = 1}, {name = "transport-belt", kind = "belt", x = 4, y = 4, d = 1}}
  job.tiles = layout.tiles(job.entities)
  return job
end

test("planner: two clicks create one job and clear the start", function()
  local player = setup()
  planner.on_select(click(3.5, 4.5))
  check(storage.players[1].start ~= nil, "start stored")
  check(said(player, "auto-belt.start-set"), "start message")
  planner.on_select(click(9.5, 4.5))
  equal(count(storage.jobs), 1)
  equal(storage.players[1].start, nil)
end)

test("planner: an endpoint error shows its message and creates no job", function()
  local player = setup()
  endpoints.start = function() return {error = "auto-belt.start-blocked"} end
  planner.on_select(click(3.5, 4.5))
  equal(count(storage.jobs), 0)
  check(said(player, "auto-belt.start-blocked"), "error message shown")
end)

test("planner: a click on the ready route starts a build", function()
  setup()
  local job = ready_job(1)
  storage.players[1] = {placement = "ghost", layout = "belts", tier = "transport-belt", job_id = job.id}
  planner.on_select(click(4.5, 4.5))
  equal(count(storage.builds), 1)
  equal(count(storage.jobs), 0)
end)

test("planner: free placement disabled keeps the preview and says so", function()
  local player = setup()
  local job = ready_job(1)
  job.placement = "free"
  settings.global["auto-belt-allow-free"].value = false
  storage.players[1] = {placement = "free", layout = "belts", tier = "transport-belt", job_id = job.id}
  planner.on_select(click(4.5, 4.5))
  equal(count(storage.builds), 0)
  equal(count(storage.jobs), 1)
  check(said(player, "auto-belt.free-disabled"), "message shown")
end)

test("planner: cancel clears the start and the job", function()
  setup()
  planner.on_select(click(3.5, 4.5))
  planner.on_select(click(9.5, 4.5))
  planner.on_select(click(1.5, 1.5))
  planner.on_cancel({player_index = 1, item = "auto-belt-planner"})
  equal(storage.players[1].start, nil)
  equal(count(storage.jobs), 0)
end)

test("planner: flip switches the layout only while the planner is held", function()
  local player = setup()
  planner.on_flip({player_index = 1})
  equal(planner.settings(1).layout, "belts")
  player.cursor_stack = {valid_for_read = true, name = "auto-belt-planner"}
  planner.on_flip({player_index = 1})
  equal(planner.settings(1).layout, "undergrounds")
end)

test("planner: a job leaving the search reports to its player only", function()
  local player = setup()
  local job = ready_job(1)
  storage.players[1] = {placement = "ghost", layout = "belts", tier = "transport-belt", job_id = job.id}
  planner.on_job_done(job)
  check(said(player, "auto-belt.ready"), "ready message")
  equal(count(storage.jobs), 1)
  job.entities, job.tiles = {}, {}
  planner.on_job_done(job)
  check(said(player, "auto-belt.already-connected"), "connected message")
  equal(count(storage.jobs), 0)
  local engine_job = ready_job(nil)
  planner.on_job_done(engine_job)
  equal(count(storage.jobs), 1)
end)

test("planner: a failed job shows its message and a marker, then goes away", function()
  local player = setup()
  local job = ready_job(1)
  job.stage, job.error, job.closest = "failed", "auto-belt.no-route", {x = 5, y = 4}
  storage.players[1] = {placement = "ghost", layout = "belts", tier = "transport-belt", job_id = job.id}
  planner.on_job_done(job)
  check(said(player, "auto-belt.no-route"), "message")
  equal(count(storage.jobs), 0)
  equal(#storage.players[1].markers, 1)
end)

test("planner: a blocked build allows one reroute click at the stop tile", function()
  local player = setup()
  planner.on_build_done({player_index = 1, surface_index = 1, blocked = {x = 6, y = 4}, last = {x = 5, y = 4},
    goal = {x = 9, y = 4, headings = ALL, place = true}, starts = {{x = 3, y = 4, d = 1}}, tier = TIER})
  check(said(player, "auto-belt.blocked"), "blocked message")
  local reroute = storage.players[1].reroute
  equal(reroute.tile.x, 6)
  planner.on_select(click(6.5, 4.5))
  equal(count(storage.jobs), 1)
  equal(storage.players[1].reroute, nil)
  equal(storage.players[1].start, nil)
end)

test("planner: a reroute without a last entity reuses the build's starts", function()
  setup()
  endpoints.start = function() error("must not read the map") end
  planner.on_build_done({player_index = 1, surface_index = 1, blocked = {x = 3, y = 4},
    goal = {x = 9, y = 4, headings = ALL, place = true}, starts = {{x = 3, y = 4, d = 1}}, tier = TIER})
  planner.on_select(click(3.5, 4.5))
  equal(count(storage.jobs), 1)
end)

test("planner: a finished build says so", function()
  local player = setup()
  planner.on_build_done({player_index = 1, surface_index = 1})
  check(said(player, "auto-belt.built"), "built message")
end)

test("panel: shows with the planner in hand, with legal element names", function()
  local player = setup()
  player.cursor_stack = {valid_for_read = true, name = "auto-belt-planner"}
  panel.update(player)
  check(player.gui.left.auto_belt_panel and player.gui.left.auto_belt_panel.valid, "panel shown")
  player.cursor_stack = {valid_for_read = false}
  panel.update(player)
  check(not (player.gui.left.auto_belt_panel and player.gui.left.auto_belt_panel.valid), "panel hidden")
end)

test("panel: build and cancel show only while the route is ready, switches follow the settings", function()
  local player = setup()
  player.cursor_stack = {valid_for_read = true, name = "auto-belt-planner"}
  panel.update(player)
  local frame = player.gui.left.auto_belt_panel
  equal(frame.auto_belt_build.visible, false)
  equal(frame.auto_belt_tier.elem_value, "transport-belt")
  local job = ready_job(1)
  planner.settings(1).job_id = job.id
  planner.settings(1).layout = "undergrounds"
  panel.update(player)
  equal(frame.auto_belt_build.visible, true)
  equal(frame.auto_belt_layout.switch_state, "right")
  panel.on_switch({player_index = 1, element = {valid = true, name = "auto_belt_placement", switch_state = "right"}})
  equal(planner.settings(1).placement, "free")
  settings.global["auto-belt-allow-free"].value = false
  panel.update(player)
  equal(planner.settings(1).placement, "ghost")
  equal(frame.auto_belt_placement.enabled, false)
end)

test("builder: preview stores render objects on the job and remove destroys them", function()
  local player = setup()
  local calls, created = 0, {}
  local saved = rendering
  rendering = setmetatable({}, {__index = function()
    return function()
      calls = calls + 1
      local object = {valid = true}
      object.destroy = function() object.valid = false end
      created[#created + 1] = object
      return object
    end
  end})
  local job = ready_job(1)
  builder.preview(job)
  rendering = saved
  check(calls > 0 and #job.renders == calls, "render objects stored")
  jobs.remove(job)
  for _, object in ipairs(created) do check(not object.valid, "render object destroyed") end
  local engine_job = ready_job(nil)
  builder.preview(engine_job)
  equal(engine_job.renders, nil)
end)

test("control: on_tick is registered exactly while a job or build exists, on_load only reads", function()
  local registered, handlers = {}, {}
  local saved_script, saved_events, saved_belt = script, defines.events, AUTO_BELT
  script = {
    on_event = function(event, handler)
      if type(event) == "table" then
        for _, e in ipairs(event) do handlers[e] = handler end
      else
        handlers[event] = handler
        registered[event] = handler
      end
    end,
    on_init = function(f) handlers.init = f end,
    on_load = function(f) handlers.load = f end,
    on_configuration_changed = function(f) handlers.config = f end,
    on_nth_tick = function() end,
  }
  defines.events = setmetatable({}, {__index = function(_, name) return name end})
  require = REAL_REQUIRE
  local ok, err = pcall(dofile, "control.lua")
  local belt = AUTO_BELT
  local restore = function() script, defines.events, AUTO_BELT = saved_script, saved_events, saved_belt end
  if not ok then restore(); error(err) end
  script = {on_event = function(event, handler) registered[event] = handler end}
  local body = function()
  storage = {jobs = {}, builds = {}}
  registered.on_tick = nil
  belt.update_tick()
  equal(registered.on_tick, nil)
  storage.jobs[1] = {}
  belt.update_tick()
  check(registered.on_tick ~= nil, "registered for a job")
  storage.jobs = {}
  storage.builds[2] = {}
  belt.update_tick()
  check(registered.on_tick ~= nil, "registered for a build")
  storage.builds = {}
  belt.update_tick()
  equal(registered.on_tick, nil)
  storage = {jobs = {[1] = {}}, builds = {}}
  registered.on_tick = nil
  local before = {}
  for k, v in pairs(storage) do before[k] = v end
  handlers.load()
  check(registered.on_tick ~= nil, "on_load registers from storage")
  equal(count(storage), count(before))
  for k, v in pairs(before) do equal(storage[k], v) end
  end
  local good, failure = pcall(body)
  restore()
  check(good, failure)
end)
