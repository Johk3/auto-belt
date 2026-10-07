local layout = require("scripts.layout")
local fake = require("test.fake_grid")
local TIER = {belt = "transport-belt", underground = "underground-belt"}
local ALL = {[0] = true, [1] = true, [2] = true, [3] = true}

test("layout: belts face their outgoing move, the corner turns", function()
  local states = {{x = 0, y = 0, d = 1}, {x = 1, y = 0, d = 1}, {x = 1, y = 1, d = 2}}
  local e = layout.build(states, {x = 1, y = 1, headings = ALL, place = true}, TIER)
  equal(#e, 3)
  equal(e[1].d, 1); equal(e[2].d, 2); equal(e[2].x, 1); equal(e[3].d, 2)
  equal(e[3].kind, "belt"); equal(e[3].name, "transport-belt")
end)

test("layout: a jump becomes an input and an output", function()
  local states = {{x = 0, y = 0, d = 1}, {x = 5, y = 0, d = 1}}
  local e = layout.build(states, {x = 5, y = 0, headings = {[1] = true}, place = false}, TIER)
  equal(#e, 2)
  equal(e[1].kind, "input"); equal(e[1].x, 0); equal(e[1].d, 1)
  equal(e[2].kind, "output"); equal(e[2].x, 4); equal(e[2].d, 1)
  equal(e[2].name, "underground-belt")
end)

test("layout: nothing is built when the start already feeds the end", function()
  local e = layout.build({{x = 3, y = 3, d = 0}}, {x = 3, y = 3, headings = {[0] = true}, place = false}, TIER)
  equal(#e, 0)
end)

test("layout: one belt when both clicks were on one tile", function()
  local e = layout.build({{x = 3, y = 3, d = 0}}, {x = 3, y = 3, headings = ALL, place = true}, TIER)
  equal(#e, 1); equal(e[1].x, 3)
end)

test("layout: a route crossing itself is rejected", function()
  local states = {{x = 0, y = 0, d = 1}, {x = 1, y = 0, d = 2}, {x = 1, y = 1, d = 3}, {x = 0, y = 1, d = 0}, {x = 0, y = 0, d = 1}}
  local e, err = layout.build(states, {x = 0, y = 0, headings = ALL, place = true}, TIER)
  equal(e, nil); equal(err, "loop")
end)

test("layout: overlapping same-axis spans are rejected", function()
  local states = {{x = 0, y = 0, d = 1}, {x = 6, y = 0, d = 1}}
  local e = layout.build(states, {x = 6, y = 0, headings = ALL, place = true}, TIER)
  -- a second pair whose input sits inside the first span on the same axis
  e[#e + 1] = {name = "underground-belt", kind = "input", x = 2, y = 0, d = 3}
  equal(layout.validate(e), "loop")
end)

test("layout: a solved route converts without loops", function()
  local rows = {"..........", "....|.....", ".........."}
  local s = fake.solve(fake.grid(rows), {starts = {{x = 0, y = 1, d = 1}}, goal = {x = 9, y = 1, headings = ALL, place = true},
    region = fake.box(rows), mode = "belts", max_distance = 5})
  local e = layout.build(s.result, {x = 9, y = 1, headings = ALL, place = true}, TIER)
  check(e ~= nil, "layout failed")
  local tiles = layout.tiles(e)
  check(tiles[require("scripts.cells").tile_key(9, 1)], "goal tile listed")
end)
