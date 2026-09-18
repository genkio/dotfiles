// @ts-nocheck

import { spawn } from "node:child_process";
import { homedir } from "node:os";
import { join } from "node:path";

const BIN_DIR = join(homedir(), "dotfiles", "tmux", "bin");

function runHook(script, ...args) {
  try {
    const child = spawn(join(BIN_DIR, script), args, {
      detached: true,
      stdio: "ignore",
    });
    child.on("error", () => {});
    child.unref();
  } catch {
  }
}

const busy = () => runHook("agent-busy.sh");
const idle = () => runHook("agent-idle.sh");
const attention = () => runHook("agent-attention.sh");
const clear = () => runHook("agent-pane-state.sh", "");

export default function (pi) {
  pi.on("session_start", (_event, ctx) => {
    if (ctx.isIdle?.() === false) busy();
    else clear();
  });

  pi.on("agent_start", () => busy());
  pi.on("turn_start", () => busy());
  pi.on("ui_prompt_start", () => attention());
  pi.on("ui_prompt_end", () => busy());

  pi.on("agent_settled", (_event, ctx) => {
    if (ctx.isIdle?.() !== true) return;
    idle();
  });

  pi.on("session_shutdown", () => clear());
}
