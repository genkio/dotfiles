return {
  -- Values can be an app name/bundle ID/path, an app table like
  -- { app = "Firefox", fullscreen = true }, a table with an action,
  -- or multiple apps via { "Firefox", "Google Chrome" } / { apps = { ... } }.
  -- `fullscreen = true` still just focuses the app when its current window is
  -- already snapped to a tiled position (left/right half, or the 2/3 and 1/3
  -- splits from key 3).
  ["0"] = { action = "window_maximize" },
  ["1"] = { action = "window_left" },
  ["2"] = { action = "window_right" },
  ["3"] = { action = "window_two_thirds" },
  ["`"] = { action = "window_next_screen" },
  a = { app = "Alacritty", fullscreen = true },
  c = "Calendar",
  f = "Finder",
  i = "iPhone Mirroring",
  m = "Mail",
  n = { action = "notification_center" },
  o = { action = "finder_in_alacritty" },
  q = { action = "run_in_alacritty", command = "vi ~/box/notes.txt" },
  t = "TablePlus",
  s = "Sublime",
  u = "com.netease.uuremote",
  w = "WeChat",
  z = { app = "Firefox", fullscreen = true },
}
