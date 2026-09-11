// Pi bridge to the dotfiles tmux agent-state hooks.
//
// Claude Code (claude/.claude/settings.json) and Codex (codex/.codex/hooks.json)
// wire tmux/bin/agent-{busy,attention,idle}.sh through their hook configs. Pi has
// no hook config file, so this extension is the hook: it runs the same scripts,
// which set @agent_pane_state on Pi's pane and re-derive the window-level flags,
// so Pi's border and window title stay in step with the other agents.
//
//   agent_start / turn_start -> busy       (orange)
//   ui_prompt_start          -> attention  (red: waiting on the user)
//   ui_prompt_end            -> busy       (prompt answered, agent resumes)
//   agent_settled            -> idle       (green unless the user is watching)
//   session_start / shutdown -> clear      (no stale state from a dead run)
//
// The scripts no-op without TMUX_PANE, so Pi outside tmux is unaffected.
// @ts-nocheck

import { spawn } from "node:child_process";
import { homedir } from "node:os";
import { join } from "node:path";

const BIN_DIR = join(homedir(), "dotfiles", "tmux", "bin");

// Fire and forget: agent events must never wait on tmux, and a missing
// ~/dotfiles checkout must never break the agent loop. stderr is ignored
// because the scripts may not exist off a dotfiles machine.
function runHook(script, ...args) {
  try {
    const child = spawn(join(BIN_DIR, script), args, {
      detached: true,
      stdio: "ignore",
    });
    child.on("error", () => {});
    child.unref();
  } catch {
    // Agent state is cosmetic.
  }
}

const busy = () => runHook("agent-busy.sh");
const idle = () => runHook("agent-idle.sh");
const attention = () => runHook("agent-attention.sh");
const clear = () => runHook("agent-pane-state.sh", "");

export default function (pi) {
  pi.on("session_start", (_event, ctx) => {
    // A reload can replace this extension mid-run, so trust ctx.isIdle()
    // instead of assuming a fresh session has no agent running.
    if (ctx.isIdle?.() === false) busy();
    else clear();
  });

  pi.on("agent_start", () => busy());
  // Covers a reload between agent_start and the current turn.
  pi.on("turn_start", () => busy());
  pi.on("ui_prompt_start", () => attention());
  pi.on("ui_prompt_end", () => busy());

  pi.on("agent_settled", (_event, ctx) => {
    // Another extension may already have started a new run.
    if (ctx.isIdle?.() !== true) return;
    idle();
  });

  pi.on("session_shutdown", () => clear());
}
