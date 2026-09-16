# Review context

Repo: personal dotfiles managed with GNU Stow (see AGENTS.md at repo root).
Diff under review: `plans/review-2eec14e/review.diff` = `git diff --cached`
(everything staged vs HEAD 2eec14e). Nothing is unstaged.

## What the change claims to do

Add SketchyBar as a new stow package and wire it into AeroSpace (the tiling
WM added in the previous commit), following how JankyBorders was wired.

1. **New stow package `sketchybar/`** -> `~/.config/sketchybar/`
   - `sketchybarrc`: bar geometry, AeroSpace workspace items on the left,
     volume + clock on the right, no icons anywhere.
   - `plugins/aerospace.sh` (per-workspace item script), `plugins/clock.sh`,
     `plugins/volume.sh`.
   - Started from `aerospace.toml`'s `after-startup-command`, like borders.
     Deliberately NOT a `brew services` daemon.

2. **New AeroSpace helper scripts** in `aerospace/.config/aerospace/scripts/`:
   - `chrome.sh <all|none|display-list>`: switches the sketchybar bar and the
     JankyBorders focus ring together. Owns the ring's colors/width (moved out
     of the TOML line so fullscreen-toggle can restore them).
   - `chrome-sync.sh`: derives the desired chrome from whether the focused
     window is fullscreen; only the fullscreen window's own display loses its
     bar (`--bar display=<others>`), falling back to `hidden=on` when a single
     monitor leaves no list. Memoizes in `$TMPDIR`.
   - `spaces-sync.sh [force]`: computes the workspace indicator payload
     (workspaces holding windows + the focused one even when empty; nothing at
     all when only one workspace is in use) and pushes it through the custom
     `aerospace_workspace_change` event. Memoizes in `$TMPDIR`.
   - `sync.sh`: calls spaces-sync then chrome-sync; the single entry point for
     every hook.
   - `fullscreen-toggle.sh`: bound to rcmd-enter; `aerospace fullscreen
     --no-outer-gaps` then `sync.sh`.

3. **aerospace.toml**: `after-startup-command` starts sketchybar + chrome.sh;
   `exec-on-workspace-change` and `on-focus-changed` both call `sync.sh`;
   `gaps.outer.top` becomes per-monitor `[{ monitor.'built-in' = 13 }, 42]`;
   rcmd-enter now runs `fullscreen-toggle.sh` instead of plain `fullscreen`.

4. **macos-bootstrap.sh**: new "Menu bar" section auto-hiding the macOS menu
   bar (a `defaults write` plus an `optional osascript`), placed before Dock.

5. **Wiring**: `brew/Brewfile.apps` adds the sketchybar formula (same tap as
   borders); `opinionated-flow.sh` trusts that formula and stows `sketchybar`;
   `restow.sh` adds `sketchybar` AND `aerospace` to `HOME_PKGS` (aerospace was
   missing from the previous commit); README + AGENTS.md updated.

## Design constraints that were verified empirically this session

These were measured on the machine, not assumed - do not re-litigate them,
but DO check the code actually implements them:

- macOS reserves 29pt at the top of a notched built-in display even with the
  menu bar auto-hidden (`NSScreen.visibleFrame` vs `frame`); a non-notched or
  external display reserves nothing. Hence the per-monitor `gaps.outer.top`:
  each value is the 40pt bar height + 2pt, minus what the display reserves.
- sketchybar's `display=<n>` indices match AppKit/NSScreen numbering, which is
  what AeroSpace reports as `%{monitor-appkit-nsscreen-screens-id}`. AeroSpace's
  own `%{monitor-id}` is a DIFFERENT ordering (here: monitor-id 1 = DELL,
  AppKit id 1 = built-in), so using it would blank the wrong screen.
- AeroSpace drops a window's fullscreen state as soon as that window loses
  focus. That is why `on-focus-changed` drives the sync.
- `on-focus-changed` fires on every mouse-driven focus change because
  `focus-follows-mouse.enabled = true`. Hence the memo files.
- The macOS UI font is only reachable as `.AppleSystemUIFont`; there is no
  user-facing `SF Pro`/`SF Mono` family and `"SF Pro"` silently falls back to
  Helvetica. SF Symbols codepoints resolve to LastResort. A Nerd Font cask was
  added and then deliberately removed again (the bar has no glyphs now), which
  is why nothing in the diff references one.
- `borders` has no disable verb; the ring is hidden by setting transparent
  colors rather than killing the process.

## Focus list

- **Correctness of the shell scripts**: quoting, POSIX `sh` portability (they
  have `#!/bin/sh` and run under dash-like semantics via bash-as-sh on macOS),
  `dirname "$0"` resolution when invoked through a stow symlink, exit codes,
  behaviour when a command fails or returns empty.
- **The memo files**: staleness, races between the two hooks that both call
  `sync.sh` concurrently, first-run behaviour, behaviour after a sketchybar
  restart or a monitor being unplugged.
- **Integration**: does `aerospace.toml` reference script paths that exist and
  are executable; does `$HOME` expand in AeroSpace's `exec-and-forget`; does
  the sketchybarrc `PATH`/`AEROSPACE` handling actually reach click scripts.
- **Bootstrap/provisioning**: would a fresh machine running `make apps` end up
  in the same state as this machine; ordering of stow vs install; anything that
  would fail or hang non-interactively (over ssh, no GUI).
- **Intel/second-machine safety**: this repo is shared with an Intel MacBook
  with a NON-notched built-in display - flag anything that is silently wrong
  there (the `gaps.outer.top` built-in value is a known, documented one).
- **Docs**: AGENTS.md/README claims that contradict the code.

## Out of scope / known-good, do not spend time on

- Whether sketchybar should be a `brew services` daemon instead (decided: no).
- The choice of Hack Nerd Font vs SF Symbols (settled; no font is installed
  now and the bar deliberately has no icons).
- Style/aesthetics of the bar (colors, paddings, box styling) - the user
  approved these visually.
- The repo's own comment conventions are strict: comments explain WHY, never
  restate code. Flag missing/misleading WHY comments only where the code is
  genuinely surprising.
