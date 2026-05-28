-- Hotkey-driven manual theme toggle for tmux, Ghostty, and nvim.
-- Runs scripts/theme-toggle.sh which flips an override file and pokes
-- each consumer to re-apply.

local M = {}

local script = os.getenv("HOME") .. "/dotfiles/scripts/theme-toggle.sh"

function M.start()
  M.hotkey = hs.hotkey.bind({ "cmd", "alt", "ctrl" }, "t", function()
    hs.execute(script, true)
  end)
end

return M
