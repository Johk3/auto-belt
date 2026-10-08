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

test("heap: random interleaved operations maintain min-heap order", function()
  -- Deterministic random generator for reproducibility
  local lcg_state = 12345
  local function lcg() lcg_state = (lcg_state * 1103515245 + 12345) % 2147483648; return lcg_state end

  local h = heap.new()

  -- Push 200 keys with duplicates
  for i = 1, 200 do
    local k = lcg() % 100
    heap.push(h, k, "v" .. i)
  end

  -- Interleave pushes and pops
  for i = 1, 50 do
    local k = lcg() % 100
    heap.push(h, k, "e" .. i)
    if heap.size(h) > 0 then
      heap.pop(h)
    end
  end

  -- Drain and verify sorted order
  local prev = nil
  while heap.size(h) > 0 do
    local k = heap.pop(h)
    if prev ~= nil then
      check(k >= prev, "out of order: " .. k .. " < " .. prev)
    end
    prev = k
  end

  -- Verify empty
  equal(heap.size(h), 0)
  equal(heap.pop(h), nil)
  equal(heap.peek(h), nil)
end)

test("heap: pop leaves no stale slots", function()
  local h = heap.new()
  for i = 1, 5 do heap.push(h, i, i * 10) end
  while heap.size(h) > 0 do heap.pop(h) end
  equal(next(h.key_blocks), nil)
  equal(next(h.val_blocks), nil)
end)

test("heap: order holds across blocks and empty blocks are dropped", function()
  local h = heap.new()
  local n = heap.BLOCK * 2 + 37
  local seed = 11
  for i = 1, n do
    seed = (seed * 1103515245 + 12345) % 2147483648
    heap.push(h, math.floor(seed / 65536) % 5000, i)
  end
  local blocks = 0
  for _ in pairs(h.key_blocks) do blocks = blocks + 1 end
  equal(blocks, 3)
  local last = -1
  for _ = 1, n - 10 do
    local key = heap.pop(h)
    check(key >= last, "keys come out in order")
    last = key
  end
  blocks = 0
  for _ in pairs(h.key_blocks) do blocks = blocks + 1 end
  equal(blocks, 1)
  -- Refill past the dropped blocks, then drain.
  for i = 1, heap.BLOCK + 3 do heap.push(h, (i * 7919) % 3001, i) end
  last = -1
  while heap.size(h) > 0 do
    local key = heap.pop(h)
    check(key >= last, "keys come out in order after a refill")
    last = key
  end
  equal(next(h.key_blocks), nil)
end)
