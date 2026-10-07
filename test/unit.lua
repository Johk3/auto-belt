-- Server-free test runner. Each test file registers cases with test(name, fn).
local passed, failed = 0, 0
local filter, verbose = UNIT_FILTER, UNIT_VERBOSE

function test(name, fn)
  if filter and not name:find(filter, 1, true) then return end
  REAL_REQUIRE = REAL_REQUIRE or require
  local real_require = REAL_REQUIRE
  require = function(name) error("require at runtime: " .. tostring(name), 2) end
  local ok, err = pcall(fn)
  require = real_require
  if ok then
    passed = passed + 1
    if verbose then print("ok    " .. name) end
  else
    failed = failed + 1
    print("FAIL  " .. name .. ": " .. tostring(err))
  end
end

function check(condition, message)
  if not condition then error(message or "check failed", 2) end
end

function equal(actual, expected, message)
  if actual ~= expected then
    error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
  end
end

storage = {}
game = {tick = 0}


-- The game rejects a child name that matches a LuaGuiElement method or
-- attribute, because children are read as attributes of their parent.
local GUI_MEMBERS = {}
for member in ([[add clear destroy get_mod get_index_in_parent swap_children clear_items get_item set_item
  add_item remove_item get_slider_minimum get_slider_maximum set_slider_minimum_maximum get_slider_value_step
  get_slider_discrete_values set_slider_value_step set_slider_discrete_values focus scroll_to_top
  scroll_to_bottom scroll_to_left scroll_to_right scroll_to_element scroll_to_item select_all select add_tab
  remove_tab force_auto_center close_dropdown index gui parent name caption value direction style visible
  text children_names state player_index sprite resize_to_sprite hovered_sprite clicked_sprite tooltip
  elem_tooltip horizontal_scroll_policy vertical_scroll_policy type children items selected_index quality
  number show_percent_for_small_numbers location auto_center badge_text auto_toggle toggled
  game_controller_interaction position surface_index zoom minimap_player_index force elem_type elem_value
  elem_filters selectable word_wrap read_only enabled ignored_by_interaction locked draw_vertical_lines
  draw_horizontal_lines draw_horizontal_line_after_headers column_count vertical_centering slider_value
  mouse_button_filter numeric allow_decimal allow_negative is_password lose_focus_on_confirm
  clear_and_focus_on_right_click drag_target selected_tab_index tabs entity anchor tags raise_hover_events
  switch_state allow_none_state left_label_caption left_label_tooltip right_label_caption right_label_tooltip
  valid object_name]]):gmatch("%S+") do GUI_MEMBERS[member] = true end

local function gui_element(args)
  local element = {valid = true, style = {}, children = {}}
  for key, value in pairs(args or {}) do element[key] = value end
  -- A style given by name reads back as a style object, as in the game.
  if type(element.style) ~= "table" then element.style = {name = element.style} end
  element.add = function(spec)
    if spec.name and GUI_MEMBERS[spec.name] then
      error('Invalid name "' .. spec.name .. '": LuaGuiElement contains a property or method with the same name.')
    end
    local child = gui_element(spec)
    element.children[#element.children + 1] = child
    if spec.name then element[spec.name] = child end
    return child
  end
  element.destroy = function() element.valid = false end
  return element
end

-- Fakes for the engine globals the game modules touch.
defines = {direction = {north = 0, east = 4, south = 8, west = 12},
  build_check_type = {manual = 0, manual_ghost = 1}, events = {}}
local function render_object() return {valid = true, destroy = function() end} end
rendering = setmetatable({}, {__index = function() return render_object end})

function fake_player()
  local player = {index = 1, valid = true, surface = {index = 1, name = "nauvis"}, force = "player",
    gui = {left = gui_element(), screen = gui_element()}, flying = {}, cursor_stack = {valid_for_read = false}}
  player.create_local_flying_text = function(args) player.flying[#player.flying + 1] = args end
  return player
end

local FILES = {"cells", "heap", "refine", "layout", "grid", "jobs", "planner"}
for _, name in ipairs(FILES) do dofile("test/" .. name .. ".lua") end

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then error("unit tests failed") end
