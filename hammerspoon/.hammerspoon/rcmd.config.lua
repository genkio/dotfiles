return {
  -- Values can be an app name/bundle ID/path, an app table like
  -- { app = "Brave Browser", fullscreen = true }, a table with an action,
  -- or multiple apps via { "Brave Browser", "Google Chrome" } / { apps = { ... } }.
  ["0"] = { action = "window_maximize" },
  ["1"] = { action = "window_left" },
  ["2"] = { action = "window_right" },
  b = { app = "Brave Browser", fullscreen = true },
  c = "Calendar",
  f = "Finder",
  g = { app = "Ghostty", fullscreen = true },
  i = "iPhone Mirroring",
  m = "Mail",
  n = { action = "notification_center" },
  t = "TablePlus",
  s = "Sublime Text"
}
