-- Binary min-heap over parallel arrays.
local heap = {}

function heap.new()
  return {keys = {}, vals = {}, n = 0}
end

function heap.push(h, key, val)
  h.n = h.n + 1
  local i = h.n
  h.keys[i] = key
  h.vals[i] = val

  -- Sift up
  while i > 1 do
    local parent = math.floor(i / 2)
    if h.keys[parent] <= key then break end
    h.keys[i] = h.keys[parent]
    h.vals[i] = h.vals[parent]
    i = parent
  end
  h.keys[i] = key
  h.vals[i] = val
end

function heap.peek(h)
  if h.n > 0 then
    return h.keys[1], h.vals[1]
  end
  return nil
end

function heap.pop(h)
  if h.n == 0 then return nil end

  local key, val = h.keys[1], h.vals[1]

  if h.n == 1 then
    h.n = 0
    return key, val
  end

  -- Move last to root and sift down
  local last_key = h.keys[h.n]
  local last_val = h.vals[h.n]
  h.n = h.n - 1

  local i = 1
  while true do
    local left = i * 2
    local right = left + 1
    if left > h.n then break end

    -- Find the smaller child
    local child = left
    if right <= h.n and h.keys[right] < h.keys[left] then
      child = right
    end

    -- If child >= last_key, heap property is satisfied
    if h.keys[child] >= last_key then break end

    -- Move child up
    h.keys[i] = h.keys[child]
    h.vals[i] = h.vals[child]
    i = child
  end
  h.keys[i] = last_key
  h.vals[i] = last_val

  return key, val
end

function heap.size(h)
  return h.n
end

return heap
