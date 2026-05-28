-- Re-apply the tmux theme whenever macOS toggles light/dark appearance.
-- Ghostty handles its own auto-switch; this keeps tmux in sync.

local M = {}

local script = os.getenv("HOME") .. "/dotfiles/tmux/bin/apply-theme.sh"

local function apply()
  hs.execute(script, true)
end

function M.start()
  M.watcher = hs.distributednotifications.new(apply, "AppleInterfaceThemeChangedNotification")
  M.watcher:start()
  apply()
end

return M
