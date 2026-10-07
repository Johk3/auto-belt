-- Settings panel shown while the planner is in hand.
local planner = require("scripts.planner")

local panel = {}

local ITEM = "auto-belt-planner"

local function holding(player)
  local stack = player.cursor_stack
  return stack and stack.valid_for_read and stack.name == ITEM
end

local function free_allowed()
  return settings.global["auto-belt-allow-free"].value
end

local function create(frame, p)
  frame.add{type = "switch", name = "auto_belt_placement", switch_state = "left",
    left_label_caption = {"auto-belt.placement-ghost"}, right_label_caption = {"auto-belt.placement-free"}}
  frame.add{type = "switch", name = "auto_belt_layout", switch_state = "left",
    left_label_caption = {"auto-belt.layout-belts"}, right_label_caption = {"auto-belt.layout-undergrounds"}}
  frame.add{type = "choose-elem-button", name = "auto_belt_tier", elem_type = "entity",
    elem_filters = {{filter = "type", type = "transport-belt"}}, tooltip = {"auto-belt.tier-tooltip"}}
  frame.add{type = "button", name = "auto_belt_build", caption = {"auto-belt.build"}, style = "confirm_button"}
  frame.add{type = "button", name = "auto_belt_cancel", caption = {"auto-belt.cancel"}, style = "red_button"}
end

function panel.update(player)
  local frame = player.gui.left.auto_belt_panel
  if frame and not frame.valid then frame = nil end
  if not holding(player) then
    if frame then frame.destroy() end
    return
  end
  local p = planner.settings(player.index)
  local allowed = free_allowed()
  if not allowed and p.placement == "free" then p.placement = "ghost" end
  if not frame then
    frame = player.gui.left.add{type = "frame", name = "auto_belt_panel", direction = "vertical",
      caption = {"auto-belt.panel-title"}}
    create(frame, p)
  end
  frame.auto_belt_placement.switch_state = p.placement == "free" and "right" or "left"
  frame.auto_belt_placement.enabled = allowed
  frame.auto_belt_placement.tooltip = allowed and "" or {"auto-belt.free-disabled"}
  frame.auto_belt_layout.switch_state = p.layout == "undergrounds" and "right" or "left"
  frame.auto_belt_tier.elem_value = p.tier
  local ready = planner.ready_job(player.index) ~= nil
  frame.auto_belt_build.visible = ready
  frame.auto_belt_cancel.visible = ready
end

planner.refresh = panel.update

local function own(event)
  local element = event.element
  if not (element and element.valid and element.name:sub(1, 10) == "auto_belt_") then return end
  return element, game.get_player(event.player_index)
end

function panel.on_switch(event)
  local element, player = own(event)
  if not player then return end
  local p = planner.settings(player.index)
  local right = element.switch_state == "right"
  if element.name == "auto_belt_placement" then
    p.placement = right and "free" or "ghost"
  elseif element.name == "auto_belt_layout" then
    p.layout = right and "undergrounds" or "belts"
  end
  panel.update(player)
end

function panel.on_elem(event)
  local element, player = own(event)
  if not player or element.name ~= "auto_belt_tier" then return end
  local p = planner.settings(player.index)
  if element.elem_value then p.tier = element.elem_value end
  panel.update(player)
end

function panel.on_click(event)
  local element, player = own(event)
  if not player then return end
  if element.name == "auto_belt_build" then
    planner.build(player)
  elseif element.name == "auto_belt_cancel" then
    planner.cancel(player)
  end
end

return panel
