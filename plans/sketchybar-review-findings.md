# sketchybar + AeroSpace review - synthesized findings

Three read-only lenses (line scan, contract, cross-file) over the staged diff.
Driver fact-checked every claim against the running system. Nothing applied.

## Real

**F1 [minor-moderate] chrome memo survives a standalone sketchybar restart.**
`chrome-sync.sh` exits early when `want` equals the memo, and the memo lives in
`$TMPDIR`, outside the sketchybar process. Restart sketchybar alone
(`--reload`, crash, manual relaunch) while a window is fullscreen and the bar
comes back visible everywhere while the memo still says otherwise, so the next
focus event computes the same `want` and skips the re-apply. Wrong until the
next fullscreen transition.
Both lenses (A and B) raised it; both missed that login is NOT affected:
`after-startup-command` calls `chrome.sh all` directly, which is unconditional.
Fix: mirror the `spaces-sync.sh force` line at the bottom of `sketchybarrc`,
either by removing the chrome memo there or giving `chrome-sync.sh` the same
`force` argument.

**F2 [minor] `after-startup-command` calls bare `sketchybar`; that resolves
only because AeroSpace injects Homebrew into the exec PATH.**
Driver-found, no lens raised it. AeroSpace's own process PATH is
`/usr/bin:/bin:/usr/sbin:/sbin`, but `aerospace list-exec-env-vars` shows it
hands children `PATH=/opt/homebrew/bin:/opt/homebrew/sbin:...` - an Apple
silicon prefix. Every other script in this diff spells both prefixes
(`PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"`). Whether AeroSpace injects
`/usr/local/bin` on Intel is not verifiable from this machine; if it does not,
the bar never starts there, silently. Cheap insurance: start sketchybar from
`chrome.sh` (which already sets both prefixes) instead of the bare TOML line.

**F3 [minor] `macos-bootstrap.sh` menu-bar line is the file's only cross-app
AppleEvent.** Every other `osascript` in that script is JXA calling ObjC
in-process (charge limit, wallpaper) and needs no Automation TCC grant; the
wallpaper section's own comment records System Events scripting being avoided.
The new `tell application "System Events"` needs a grant a fresh machine does
not have, and `optional()` only catches a bad exit code after the call returns.
Lens B called it an indefinite hang over ssh - unproven, AppleEvent sends carry
their own timeout - but a minutes-long stall plus a dialog nobody can answer is
plausible, and it does contradict the file's established pattern.
Options: bound it (background + kill), or drop the live-apply half and rely on
the `defaults write` taking effect at next login, which the script header
already tells the user to expect.

**F4 [nit] `Makefile:60` comment is stale.** Reads "GUI casks, hammerspoon, and
Sublime's headless Package Control setup"; the phase now also stows `aerospace`
and `sketchybar`, and `opinionated-flow.sh`, README and AGENTS.md were all
updated in this diff.

**F5 [nit] `make apps` before `make macos` leaves the top gap wrong.**
`gaps.outer.top` is sized assuming the menu bar is auto-hidden, which the
`macos` phase does; the phases are independently invokable. Self-corrects once
`macos` runs. Doc line at most - AGENTS.md already says to run `make macos`
first on a new machine.

## False positives

**FP1 [lens B, major] "plugins call bare `sketchybar` with no PATH, so the
clock/volume/workspace updates will silently fail."**
The daemon inherits AeroSpace's exec PATH, which includes Homebrew (see F2), so
its plugin children resolve `sketchybar` fine. The premise - that the rc's
`PATH=` line not reaching daemon-spawned scripts implies those scripts have no
Homebrew on PATH - does not hold. The observable evidence agrees: the clock has
been ticking and the volume updating all session. Only the Intel-prefix
question in F2 survives from this.

**FP2 [lens A, minor] "guard the memo write on the apply command's exit
status."** Diagnosis is right that a failed apply is recorded as success, but
the proposed guard would not work: `chrome.sh` ends with the `borders` call, so
its exit status reports borders, not the `sketchybar --bar` that would have
failed. Not worth restructuring for a failure mode nobody has hit.
