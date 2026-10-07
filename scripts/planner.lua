-- The player flow: planner clicks, route preview, build and cancel.
-- Per-player state lives in storage.players[index]; handlers only record clicks
-- and start jobs, the scheduler does the work.
local endpoints = require("scripts.endpoints")
local jobs = require("scripts.jobs")
local builder = require("scripts.builder")
local cells = require("scripts.cells")

local planner = {}

local ITEM = "auto-belt-planner"
local RED = {r = 1, g = 0.1, b = 0.1}
local floor = math.floor

function planner.settings(index)
  storage.players = storage.players or {}
  local p = storage.players[index]
  if not p then
    p = {placement = "ghost", layout = "belts", tier = "transport-belt"}
    storage.players[index] = p
  end
  return p
end

local function say(player, key, ...)
  player.create_local_flying_text{text = {key, ...}, create_at_cursor = true}
end

-- Set by the panel at load: redraws the player's panel.
planner.refresh = nil

local function refresh(player)
  if planner.refresh then planner.refresh(player) end
end

local function mark(player, p, surface, x, y)
  p.markers = p.markers or {}
  p.markers[#p.markers + 1] = rendering.draw_circle{color = RED, radius = 0.5, filled = true,
    target = {x + 0.5, y + 0.5}, surface = surface, players = {player.index}}
end

local function clear_markers(p)
  builder.clear(p.markers)
  p.markers = nil
end

local function drop_job(p)
  local job = p.job_id and storage.jobs and storage.jobs[p.job_id]
  if job then jobs.remove(job) end
  p.job_id = nil
end

-- Forgets the player's start, route and markers.
local function reset(p)
  drop_job(p)
  clear_markers(p)
  p.start, p.reroute = nil, nil
end

function planner.cancel(player)
  local p = planner.settings(player.index)
  local had = p.start or p.job_id or p.reroute
  reset(p)
  if had then say(player, "auto-belt.cancelled") end
  refresh(player)
end

function planner.ready_job(index)
  local p = planner.settings(index)
  local job = p.job_id and storage.jobs and storage.jobs[p.job_id]
  if job and job.stage == "ready" and job.tiles then return job end
end

function planner.build(player)
  local p = planner.settings(player.index)
  local job = planner.ready_job(player.index)
  if not job then return end
  local build, error_key = builder.start(job)
  if not build then say(player, error_key); return end
  clear_markers(p)
  jobs.remove(job)
  p.job_id = nil
  refresh(player)
end

local function start_job(player, p, surface_index, starts, tier, goal)
  drop_job(p)
  clear_markers(p)
  local job = jobs.create{surface_index = surface_index, force = player.force, player_index = player.index,
    starts = starts, goal = goal, tier = tier, layout = p.layout, placement = p.placement}
  p.job_id = job.id
  p.start, p.reroute = nil, nil
  say(player, "auto-belt.routing")
  if p.layout == "undergrounds" and not tier.underground then say(player, "auto-belt.no-underground") end
  refresh(player)
end

function planner.on_select(event)
  if event.item ~= ITEM then return end
  local player = game.get_player(event.player_index)
  if not player then return end
  local p = planner.settings(event.player_index)
  local a = event.area
  local x = floor((a.left_top.x + a.right_bottom.x) / 2)
  local y = floor((a.left_top.y + a.right_bottom.y) / 2)
  local surface = event.surface or player.surface

  local ready = planner.ready_job(event.player_index)
  if ready and ready.tiles[cells.tile_key(x, y)] then
    return planner.build(player)
  end

  local r = p.reroute
  if r and r.tile.x == x and r.tile.y == y and r.surface_index == surface.index then
    local found
    if r.last then
      found = endpoints.start(surface, {x = r.last.x + 0.5, y = r.last.y + 0.5}, p.tier)
    else
      found = {starts = r.starts, tier = r.tier}
    end
    if found.error then say(player, found.error); return end
    return start_job(player, p, surface.index, found.starts, found.tier, r.goal)
  end

  if not p.start then
    reset(p)
    local found = endpoints.start(surface, {x = x + 0.5, y = y + 0.5}, p.tier)
    if found.error then say(player, found.error); refresh(player); return end
    p.start = {starts = found.starts, tier = found.tier, surface_index = surface.index}
    mark(player, p, surface, found.starts[1].x, found.starts[1].y)
    say(player, "auto-belt.start-set")
    refresh(player)
    return
  end

  local found = endpoints.goal(surface, {x = x + 0.5, y = y + 0.5})
  if found.error then say(player, found.error); return end
  if p.start.surface_index ~= surface.index then say(player, "auto-belt.other-surface"); return end
  local s = p.start
  drop_job(p)
  start_job(player, p, s.surface_index, s.starts, s.tier, found.goal)
end

function planner.on_cancel(event)
  if event.item and event.item ~= ITEM then return end
  local player = game.get_player(event.player_index)
  if player then planner.cancel(player) end
end

function planner.on_flip(event)
  local player = game.get_player(event.player_index)
  if not player then return end
  local stack = player.cursor_stack
  if not (stack and stack.valid_for_read and stack.name == ITEM) then return end
  local p = planner.settings(event.player_index)
  p.layout = p.layout == "belts" and "undergrounds" or "belts"
  refresh(player)
end

function planner.on_job_done(job)
  if not job.player_index then return end
  local player = game.get_player(job.player_index)
  if not player then return end
  local p = planner.settings(job.player_index)
  if job.stage == "ready" then
    if #job.entities == 0 then
      say(player, "auto-belt.already-connected")
      jobs.remove(job)
      p.job_id = nil
    else
      builder.preview(job)
      say(player, "auto-belt.ready", #job.entities)
    end
  else
    say(player, job.error or "auto-belt.no-route")
    clear_markers(p)
    if job.closest then mark(player, p, job.surface_index, job.closest.x, job.closest.y) end
    jobs.remove(job)
    p.job_id = nil
  end
  refresh(player)
end

function planner.on_build_done(build)
  if not build.player_index then return end
  local player = game.get_player(build.player_index)
  if not player then return end
  local p = planner.settings(build.player_index)
  clear_markers(p)
  if build.blocked then
    say(player, "auto-belt.blocked", build.blocked.x, build.blocked.y)
    mark(player, p, build.surface_index, build.blocked.x, build.blocked.y)
    p.reroute = {tile = {x = build.blocked.x, y = build.blocked.y}, last = build.last, goal = build.goal,
      starts = build.starts, tier = build.tier, surface_index = build.surface_index}
  else
    say(player, "auto-belt.built")
  end
  refresh(player)
end

function planner.on_player_removed(event)
  local p = storage.players and storage.players[event.player_index]
  if p then reset(p) end
  if storage.players then storage.players[event.player_index] = nil end
  for _, job in pairs(storage.jobs or {}) do
    if job.player_index == event.player_index then jobs.remove(job) end
  end
end

return planner
