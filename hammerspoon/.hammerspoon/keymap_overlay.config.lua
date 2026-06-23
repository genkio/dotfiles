-- All keys optional; anything unset falls back to the module defaults.
-- rightCmd+x (via rcmd) shows/hides the overlay; its "Load .vil" button swaps layout.

return {
  -- The file the overlay renders. The "Load .vil" button copies your pick here.
  -- "~" expands to home.
  vilPath = "~/dotfiles/hammerspoon/.hammerspoon/keymap_overlay.vil",

  -- Starting folder for the "Load .vil" file picker.
  pickerDir = "~/Downloads",

  -- USERxx macro slots -> short labels on the keycaps.
  macroNames = {
    USER00 = "M0",
    USER01 = "M1",
    USER02 = "M2",
  },

  hideLayers = { 2, 3 }, -- L2/L3 unused (numbers folded into L1, no macros)
  hideKeys = { "USER00", "USER01", "USER02" }, -- macro keys: unused, blanked everywhere
  geometry = { margin = 12 }, -- screen-edge gap; the window auto-fits the layout
  accent = "#7aa2f7",
  startHidden = true,
}
