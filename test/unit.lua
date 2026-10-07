-- Server-free test runner. Each test file registers cases with test(name, fn).
local passed, failed = 0, 0
local filter, verbose = UNIT_FILTER, UNIT_VERBOSE

function test(name, fn)
  if filter and not name:find(filter, 1, true) then return end
  local ok, err = pcall(fn)
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

local FILES = {"cells", "heap", "refine"}
for _, name in ipairs(FILES) do dofile("test/" .. name .. ".lua") end

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then error("unit tests failed") end
