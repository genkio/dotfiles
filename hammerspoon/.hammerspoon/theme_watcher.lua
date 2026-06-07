-- Re-apply the tmux and Alacritty themes whenever macOS toggles light/dark
-- appearance. Ghostty handles its own auto-switch; tmux and Alacritty can't,
-- so this watcher keeps them in sync.

local M = {}

local tmux_theme = os.getenv("HOME") .. "/dotfiles/tmux/bin/apply-theme.sh"
local alacritty_theme = os.getenv("HOME") .. "/dotfiles/scripts/apply-alacritty-theme.sh"

local function apply()
  hs.execute(tmux_theme, true)
  hs.execute(alacritty_theme, true)
end

function M.start()
  M.watcher = hs.distributednotifications.new(apply, "AppleInterfaceThemeChangedNotification")
  M.watcher:start()
  apply()
end

return M
