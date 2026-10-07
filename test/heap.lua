local heap = require("scripts.heap")

test("heap: pops in key order and peeks without removing", function()
  local h = heap.new()
  for _, k in ipairs{5, 1, 9, 3, 7, 2, 8} do heap.push(h, k, "v" .. k) end
  local key, val = heap.peek(h)
  equal(key, 1); equal(val, "v1"); equal(heap.size(h), 7)
  local out = {}
  while heap.size(h) > 0 do out[#out + 1] = heap.pop(h) end
  equal(table.concat(out, ","), "1,2,3,5,7,8,9")
  equal(heap.pop(h), nil)
end)

test("heap: large keys keep their order", function()
  local h = heap.new()
  heap.push(h, 3 * 4194304 + 7, "b")
  heap.push(h, 3 * 4194304 + 2, "a")
  heap.push(h, 4 * 4194304, "c")
  local _, v = heap.pop(h); equal(v, "a")
  _, v = heap.pop(h); equal(v, "b")
end)
