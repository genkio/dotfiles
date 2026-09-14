Herdlet workers (tmux panes, herdlet 0.9.0+). Load the `herdlet` skill before
the first spawn; it owns the flags, exit codes and menu rules. This file is
only the standing orders:

- Spawn every worker with `herdlet spawn`, never a hand-built launch line. It
  requires `--model` and `--effort`, so a worker never inherits the master's
  model; it splits your own pane, not the window the owner is looking at.
- Claude workers by default. A second model family means pi on OpenAI's Codex
  models (`pi --provider openai-codex --model gpt-5.6-sol --thinking medium`),
  only when the user asks for it; otherwise that pairing is the one-shot
  cross-model reviewer (`-p -t read -ne`) the review skills already run.
  `herdlet spawn` cannot launch it - `--agent` takes claude or codex only - so
  build that pane by hand. Thinking medium unless the unit would put Claude on
  high.
- Pre-seed the worker's allowlist with `--allow <prefix>` so it prompts less.
- Wait in a background shell call, never a sleep loop: `herdlet wait --id <id>
  --state done,blocked,limited --timeout 560 --timeout-ok`. `limited` means a
  usage-limit banner: never respawn, wait again.
- Unblocking is the orchestrator's job: `herdlet approve --id <id> --choice
  always` (by option text; never `--option <digit>`).
- Instructions go through `herdlet send --ack` (verified submit); long text via
  a file and a one-line pointer. Read results from the report file, then
  `peek --transcript`; plain `peek` only for what is on screen right now.
- Retire done workers with `ack --kill-pane`. Resume `stale`/`ended` workers,
  never respawn them.
- Pair two workers only for loops that need no ruling (implementer/tester,
  reviewer/implementer): `herdlet pair --id <a> --with <b> --topic <file>`.
