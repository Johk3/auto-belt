-- Binary min-heap over parallel arrays of keys and values. Position i lives in
-- block floor(i / BLOCK), slot i % BLOCK + 1: a long search keeps hundreds of
-- thousands of entries, and one flat array that doubles at that size stalls the
-- game for several milliseconds. A block that empties is dropped.
local heap = {}

local floor = math.floor
local BLOCK = 4096
heap.BLOCK = BLOCK

function heap.new()
  return {key_blocks = {}, val_blocks = {}, n = 0}
end

function heap.push(h, key, val)
  local kb, vb = h.key_blocks, h.val_blocks
  local i = h.n + 1
  h.n = i
  local o = i % BLOCK
  local b = (i - o) / BLOCK
  local keys, vals = kb[b], vb[b]
  if not keys then
    keys, vals = {}, {}
    kb[b], vb[b] = keys, vals
  end
  local slot = o + 1

  -- Sift up; keys, vals and slot locate position i.
  while i > 1 do
    local parent = floor(i / 2)
    local po = parent % BLOCK
    local pb = (parent - po) / BLOCK
    local pkeys = kb[pb]
    local pslot = po + 1
    local pkey = pkeys[pslot]
    if pkey <= key then break end
    local pvals = vb[pb]
    keys[slot] = pkey
    vals[slot] = pvals[pslot]
    i, keys, vals, slot = parent, pkeys, pvals, pslot
  end
  keys[slot] = key
  vals[slot] = val
end

function heap.peek(h)
  if h.n > 0 then
    return h.key_blocks[0][2], h.val_blocks[0][2]
  end
  return nil
end

function heap.pop(h)
  local n = h.n
  if n == 0 then return nil end
  local kb, vb = h.key_blocks, h.val_blocks
  local root_keys, root_vals = kb[0], vb[0]
  local key, val = root_keys[2], root_vals[2]

  -- Take the last entry out, dropping its block when it empties.
  local o = n % BLOCK
  local b = (n - o) / BLOCK
  local keys, vals = kb[b], vb[b]
  local last_key, last_val = keys[o + 1], vals[o + 1]
  keys[o + 1], vals[o + 1] = nil, nil
  if o == 0 or n == 1 then kb[b], vb[b] = nil, nil end
  n = n - 1
  h.n = n
  if n == 0 then return key, val end

  -- Move it to the root and sift down; keys, vals and slot locate position i.
  local i, slot = 1, 2
  keys, vals = root_keys, root_vals
  while true do
    local child = i * 2
    if child > n then break end

    -- Find the smaller child; child is even, so child + 1 shares its block.
    local co = child % BLOCK
    local cb = (child - co) / BLOCK
    local ckeys = kb[cb]
    local cslot = co + 1
    local ckey = ckeys[cslot]
    if child < n then
      local rkey = ckeys[cslot + 1]
      if rkey < ckey then child, cslot, ckey = child + 1, cslot + 1, rkey end
    end

    -- If child >= last_key, heap property is satisfied
    if ckey >= last_key then break end

    -- Move child up
    local cvals = vb[cb]
    keys[slot] = ckey
    vals[slot] = cvals[cslot]
    i, keys, vals, slot = child, ckeys, cvals, cslot
  end
  keys[slot] = last_key
  vals[slot] = last_val

  return key, val
end

function heap.size(h)
  return h.n
end

return heap
