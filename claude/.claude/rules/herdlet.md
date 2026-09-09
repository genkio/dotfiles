Herdlet workers (tmux panes, herdlet 0.7.0+). Spawn every Claude Code worker
with `herdlet spawn`, never a hand-built launch line:

```sh
herdlet spawn --id <project>/<role> --model <model> --effort <level> \
  --title "<one-line purpose>" --brief plans/<topic>-brief.md
```

It applies the house defaults for you. It splits the CALLER's pane, so the
worker cannot land in whatever window the owner happens to be looking at, and
opens a new window instead when the split has no space. It sets
`CC_IMESSAGE_SKIP=1` so only the master pages the owner, and
`CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN=1` so the pane stays peekable. It names
the session `<id>: <title>` so the worker is findable in the resume picker and
`lr` later. It passes `--permission-mode auto` and requires `--model` and
`--effort`, so a worker never inherits the master's model. It registers the
record with the model and effort BEFORE the worker's first hook, so the worker
is addressable by name from t=0, including while it sits on a trust prompt. With
`--brief` it sends the pointer line once that first hook fires. Exit 0 means the
pane is up; exit 1 means the pane already died, so check the flags.

By hand only for non-Claude agents and one-shot `-p` wrappers:
`tmux split-window -d -h -P -F '#{pane_id}' -t "$TMUX_PANE" -c "$PWD"
"CC_IMESSAGE_SKIP=1 HERDLET_ID=<project>/<role> <cmd>"`. `-t "$TMUX_PANE"` is
not optional there, for the reason above.

Wait in a background shell call, never a sleep loop:
`herdlet wait --id <id> --state done,blocked,limited --timeout 560 --timeout-ok`.
`--timeout-ok` makes a timeout exit 0, so the harness does not read it as a
failed command. `limited` means the worker is sitting on a usage-limit banner:
do NOT respawn it, its context is intact. Re-check usage, then wait again; it
resumes on its own at the reset.

Read a finished worker with `herdlet peek --transcript --id <id>` for its last
message verbatim. Plain `peek` is only for what is on SCREEN right now: a menu,
a banner, a running command. Long instructions go in a file and are sent as one
pointer line, or with `herdlet send --id <id> --file <path>`.

Approving a worker's remaining prompt is the orchestrator's call, not the
owner's: `herdlet approve --id <id> --option <n>` (option 1 = Yes). Use
`--wait` on it to resume waiting in the same call.

Peer channel (0.8.0+): `herdlet pair --id <a> --with <b> --topic <file>` links
two workers; `herdlet unpair` removes it. A worker (`$HERDLET_ID` set) may
`send` only to a paired peer; other targets exit 3 with "not paired with <id>;
raise it in your report to the master". A peer send appends one line under
`## Thread` in the topic file and emits a `peer_send` event on `herdlet watch`;
it never touches the master's record, so master waits do not fire. The master
(no `$HERDLET_ID`) is unrestricted. `herdlet spawn` adds the child to the
SPAWNER's peers only (topic = the brief, else `plans/<id with / as ->-thread.md`),
so a nested master can `send` to what it spawned while children never gain a
path upward; only an explicit `pair` is symmetric. `remove`, `ack` of an ended
worker and the prune sweep drop dangling peer links.
