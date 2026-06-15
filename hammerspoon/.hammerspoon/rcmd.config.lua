return {
  -- Values can be an app name/bundle ID/path, an app table like
  -- { app = "Brave Browser", fullscreen = true }, a table with an action,
  -- or multiple apps via { "Brave Browser", "Google Chrome" } / { apps = { ... } }.
  -- `fullscreen = true` still just focuses the app when its current window is
  -- already snapped to the left or right half of the screen.
  ["0"] = { action = "window_maximize" },
  ["1"] = { action = "window_left" },
  ["2"] = { action = "window_right" },
  ["`"] = { action = "window_next_screen" },
  b = { app = "Brave Browser", fullscreen = true },
  c = "Calendar",
  f = "Finder",
  i = "iPhone Mirroring",
  k = { app = "kitty", fullscreen = true },
  m = "Mail",
  n = { action = "notification_center" },
  o = { action = "finder_in_kitty" },
  q = { action = "run_in_kitty", command = "vi ~/box/notes.txt" },
  t = "TablePlus",
  s = "Safari",
  u = "com.netease.uuremote"
}
