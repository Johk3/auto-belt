data:extend{
  {type = "bool-setting", name = "auto-belt-allow-free", setting_type = "runtime-global", default_value = true, order = "a"},
  {type = "int-setting", name = "auto-belt-search-budget", setting_type = "runtime-global", default_value = 50, minimum_value = 50, maximum_value = 20000, order = "b"},
  {type = "int-setting", name = "auto-belt-build-batch", setting_type = "runtime-global", default_value = 150, minimum_value = 1, maximum_value = 5000, order = "c"},
  {type = "int-setting", name = "auto-belt-max-effort", setting_type = "runtime-global", default_value = 5000000, minimum_value = 10000, maximum_value = 100000000, order = "d"},
}
