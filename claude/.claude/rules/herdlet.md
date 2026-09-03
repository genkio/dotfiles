Herdlet workers (tmux panes spawned per the herdlet skill): herdlet has no
spawn command or launch config, so the defaults live in the launch line. Every
Claude Code worker is spawned with `--permission-mode auto`, an explicit `--model`,
and an explicit `--effort`:

```sh
tmux split-window -d -h -P -F '#{pane_id}' -t "$TMUX_PANE" -c "$PWD" \
  "HERDLET_ID=<project>/<role> claude -n '<project>/<role>: <one-line purpose>' --model <model> --effort <level> --permission-mode auto"
```

`-t "$TMUX_PANE"` is not optional: without it tmux splits whatever window the
owner is looking at, and the worker lands in another project's window.
Prepend `CC_IMESSAGE_SKIP=1 CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN=1`
so only the master pages the owner and the pane stays peekable. `-n` names the
session (`customTitle` in the transcript) so it is findable in the resume picker
and `lr` later; without it the title is guessed from "read the brief and do it".

Approving a worker's remaining prompt is the orchestrator's call, not the
owner's: `herdlet approve --id <id> --option <n>` (option 1 = Yes). Use
`--wait` on it to resume waiting in the same call. Wait on `done,blocked` with
a long timeout; never poll panes with sleep loops.
