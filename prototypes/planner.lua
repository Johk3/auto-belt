local icon = "__base__/graphics/icons/transport-belt.png"
data:extend{
  {
    type = "selection-tool",
    name = "auto-belt-planner",
    icon = icon,
    icon_size = 64,
    stack_size = 1,
    flags = {"only-in-cursor", "spawnable", "not-stackable"},
    subgroup = "tool",
    order = "z-auto-belt",
    select = {border_color = {r = 0.3, g = 0.7, b = 1}, cursor_box_type = "entity", mode = {"nothing"}},
    alt_select = {border_color = {r = 1, g = 0.3, b = 0.3}, cursor_box_type = "not-allowed", mode = {"nothing"}},
    reverse_select = {border_color = {r = 1, g = 0.3, b = 0.3}, cursor_box_type = "not-allowed", mode = {"nothing"}},
  },
  {
    type = "shortcut",
    name = "auto-belt-planner",
    action = "spawn-item",
    item_to_spawn = "auto-belt-planner",
    associated_control_input = "auto-belt-give",
    icon = icon, icon_size = 64, small_icon = icon, small_icon_size = 64,
  },
  {type = "custom-input", name = "auto-belt-give", key_sequence = "ALT + B", action = "spawn-item", item_to_spawn = "auto-belt-planner", consuming = "game-only"},
  {type = "custom-input", name = "auto-belt-flip", key_sequence = "SHIFT + B", consuming = "none"},
}
