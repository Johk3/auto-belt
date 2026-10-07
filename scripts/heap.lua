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
    local smallest = i

    if left <= h.n and h.keys[left] < last_key then
      smallest = left
    end
    if right <= h.n and h.keys[right] < h.keys[smallest] then
      smallest = right
    end

    if smallest == i then break end

    h.keys[i] = h.keys[smallest]
    h.vals[i] = h.vals[smallest]
    i = smallest
  end
  h.keys[i] = last_key
  h.vals[i] = last_val

  return key, val
end

function heap.size(h)
  return h.n
end

return heap
