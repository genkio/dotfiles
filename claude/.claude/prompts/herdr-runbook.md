# herdr runbook

Operational companion to `prompts/orchestrator.md` and `prompts/review.md` for herdr agents; pull request mechanics are in `prompts/pr-runbook.md`. Use the user's per-run model, effort, budget, and environment choices when they differ from these defaults. Check installed `herdr` help and actual session metadata before relying on a command or interpreting a field; CLI behavior and provider aliases may change.

## Routing

| Role | Default launch arguments | Purpose |
|---|---|---|
| Advisor | `--kind claude -- --model claude-fable-5-1 --effort medium` | Persistent planning and final acceptance |
| Executor | `--kind claude -- --model opus --effort medium` | Implementation and local fix loop |
| Reviewer | `--kind pi -- --provider fireworks --model accounts/fireworks/models/deepseek-v4p1-flash --thinking max --tools read,grep,find,ls` | Read-only focused review |
| Critical second reviewer | `--kind pi -- --provider openai-codex --model openai-codex/gpt-5.6-sol --thinking medium --tools read,grep,find,ls` | Independent read-only review |
| Opus reviewer (review mode) | `--kind claude -- --model opus --effort high --tools Read,Grep,Glob --strict-mcp-config` | Independent read-only review |

The orchestrator runs as Claude Opus high effort, configured by the invoking session; it is not a pane launched by this runbook. Small read-only lookups can use the Agent tool with Sonnet or Haiku. Preserve explicit per-run overrides. Check effective provider/model/effort from launch and available session evidence: fuzzy model selection and provider capabilities can change the effective setting. Never use an agent's self-description as proof.

## Launch and dispatch

Create an isolated worktree for each concurrent writer and choose its cwd before creating a pane. Ensure the worker can access its absolute brief and report paths. Keep the canonical integration/service environment under orchestrator ownership.

The first Claude launch in a new directory can stop at the folder-trust dialog, and `agent start` then returns `agent_not_ready`. Read the pane to confirm the dialog. Accept it only for a directory the orchestrator created for the run or the user has authorized; otherwise ask the user. Wait for `idle` before sending the first prompt.

Name every agent `herd-<run>-<role>`, where `<run>` is the run ID or `pr<N>` and `<role>` is unique within it (`herd-pr6232-advisor`, `herd-pr6232-rev-a`, `herd-r9-exec-1`). Use that one string as the tab label, the herdr agent name, and the session display name (`--name`, which both `claude` and `pi` accept), so the user can filter herd sessions in the tab bar, `herdr agent list`, and the resume picker.

```bash
herdr tab create --workspace "$HERDR_WORKSPACE_ID" --cwd <absolute-worktree-or-repo-dir> --label herd-<run>-<role> --no-focus
herdr agent start herd-<run>-<role> --kind claude --pane <returned-pane-id> -- --name herd-<run>-<role> --model opus --effort medium
herdr agent prompt herd-<run>-<role> "Read <absolute-brief-path> in full and execute it." --wait --timeout 550000
```

Dispatch with `--wait`: it requires observed `working` or `blocked` activity before it accepts a settled state. A standalone `agent wait` issued right after a prompt sent without `--wait` can return immediately on the agent's previous `idle` or `done` state while the new turn is still starting. If you dispatch without `--wait`, confirm with `herdr agent get <name>` that the agent is `working` before starting a standalone wait.

For the advisor, substitute its routing row and send the structured planning packet. Keep its agent/session handle for acceptance. For a reviewer, substitute the read-only routing row and send a complete review packet accessible through its allowed read tools; supply a full diff including untracked/new files. Reviewers cannot run shell commands or write reports. Capture their final response yourself.

Record the actual tab ID, pane ID, session handle (`agent_session.value` when supplied), cwd, baseline, branch, routing, task/attempt ID, dispatch timestamp, and report path in `.agents/runs/<run-id>/handover.md`. Do not infer that `start` alone submitted an assignment. Dispatch once; after an uncertain prompt outcome, inspect state and transcript before retrying.

## Wait, capture, and resume

```bash
herdr agent wait <name> --timeout 550000
herdr agent read <name> --source recent-unwrapped
```

Use lifecycle waits while other independent work continues; a wait timeout does not mean failure. Restart a wait when appropriate, without a sleep loop or a status prompt. A completion signal requires idle/done lifecycle state plus a report or captured final response that names the current task **and attempt**. An old report is not completion. Inspect the latest transcript, worktree, and report before replaying any prompt after a disconnect.

`agent read` can lose most of a long response, especially in a narrow pane. When it does not show the complete final response, take it from the session transcript instead of asking the agent to repeat itself. For Claude, read `~/.claude/projects/<cwd-slug>/<agent_session.value>.jsonl` and take the text blocks of the last `type: assistant` record's `message.content`. For pi, `agent_session.value` is the session file path; take the text blocks of the last record whose `message.role` is `assistant`. Verify the schema in the current installation.

Capture read-only reviewer responses in full and save them under `.agents/runs/<run-id>/`, or `.agents/reviews/pr<N>/round-<k>/` in review mode. A reviewer may receive a packet but must not be given write or shell tools merely to save its response. Freeze the reviewed source snapshot so the packet corresponds to the diff being judged.

When recovering a session, use the recorded handle and consult installed CLI help for the current resume syntax. The original setup used these forms:

```bash
herdr agent start <claude-name> --kind claude --pane <id> -- --resume <claude-session-id>
herdr agent start <pi-name> --kind pi --pane <id> -- --session <pi-session-path>
```

Re-read the current brief, handover, and routing before resuming. Never attach two active writers to the same writable scope. Confirm the old worker is stopped or isolated before replacement; reconcile any late work against the current integration state.

## Close finished agents

Close an agent's tab as soon as its assignment is complete: its lifecycle is idle/done, its report or final response is captured and saved, and its session handle and stop time are in the handover. The transcript stays on disk, so the session can still be resumed or accounted for after the tab is gone.

```bash
herdr tab close <tab-id>
```

Keep an agent open only while you expect to prompt that same session again: the advisor until its final acceptance or judgment, or a worker whose unit is still in review and may get a correction cycle. Record the reason in the handover, and close the tab when the reason ends. Reviewers never qualify, because a later round starts fresh reviewers. Before closing, confirm the agent is not `working` and disarm its keep-warm. Close only tabs you created, never the orchestrator's own pane or a user's tab.

## Keep the advisor warm

Reuse one Fable session from planning through final acceptance. Keep it warm with `~/.config/herdr/scripts/keepwarm.sh`, never with hand-sent pings. While armed, it sends the fixed text `Reply with exactly: ok` after 50 minutes without an assistant turn, only while the advisor is idle, checks that each ping read the cache, and stops itself when the cache went cold, the window ends, or the session leaves the pane. Its arguments are the advisor's pane ID, not its agent name.

Run `keepwarm.sh check <pane>` after the advisor's first turn (the planning packet), not right after launch: a fresh session has no transcript until its first turn. If the check fails, do not warm the advisor; record the reason in the handover.

A ping can collide with a real prompt, and `agent prompt --wait` may then accept the ping's turn as the reply. Once the check passes, wrap every later advisor prompt:

```bash
KEEPWARM_QUIET=1 ~/.config/herdr/scripts/keepwarm.sh disarm <pane>
herdr agent prompt herd-<run>-advisor "<packet>" --wait --timeout 550000
KEEPWARM_QUIET=1 ~/.config/herdr/scripts/keepwarm.sh arm <pane>
```

`disarm` returns only after any in-flight ping has finished. `arm` keeps the advisor warm for 8 hours by default; pass a duration such as `2h` or `90m` when you know when the advisor is next needed. `KEEPWARM_QUIET=1` skips the arm/disarm notifications; stop and failure notifications still reach the user.

The runner can stop on its own; check `keepwarm.sh status` rather than assuming it is still armed. A ping response is maintenance, not progress, approval, or acceptance evidence. Record the session handle, armed state, and deadline in the handover. Disarm after acceptance or when the session will not be reused, then close its tab. On final acceptance, resume this session but send a fresh evidence packet rather than relying solely on memory.

Each ping's cache read and write counts are logged in `~/.local/state/herdr-keepwarm/log`, including pings that `disarm` waited out (marked `(disarm)`); use them for keep-warm accounting.

## Monorepo verification environments

Worker worktrees provide source isolation. Install dependencies there only for checks the assignment requires and the brief authorizes. A pnpm store can be shared, but each worktree may still need its own dependency links and generated state.

The orchestrator maintains a single canonical integration worktree for combined checks. After integrating reviewed commits, follow repository instructions for installation (for example, `pnpm install --frozen-lockfile` where prescribed), build, lint, typecheck, and tests. Run the final gate against the final combined tree, not an earlier worker snapshot.

The orchestrator owns service startup, fixtures, databases, and e2e execution in the canonical acceptance environment. Follow any user-specified environment skill. A worker may touch this environment only during an explicitly delegated named phase. Include code revision, dependency/configuration state, working directory, commands, exit status, and salient outputs in the advisor's final evidence packet.

## Reports, retries, and integration

Name reports with unique task and attempt IDs, and verify the IDs inside the report. If delivery, lifecycle, or a report is uncertain, inspect before retrying. Default to one cause-addressing recovery retry, unless the user specifies otherwise. Do not silently drop required scope. After review, commit only reviewed paths in the worker worktree and cherry-pick into the integration branch. Escalate substantive conflicts to a worker; record commit IDs and verification state in the handover. Never push or deploy without authorization.

## Usage and run accounting

Record dispatch/completion boundaries per assignment, especially when sessions are reused. Measure elapsed time from those boundaries; avoid counting one session's cumulative usage twice. Claude transcript records commonly expose `message.usage` fields such as `input_tokens`, `output_tokens`, `cache_read_input_tokens`, and `cache_creation_input_tokens`. The previous setup located Claude transcripts at `~/.claude/projects/<cwd-slug>/<agent_session.value>.jsonl`; verify the path and schema in the current installation. Pi session usage has a different schema and can include events outside ordinary assistant messages. Inspect actual records and aggregate usage within assignment boundaries, including corrections and maintenance turns as separately labeled activity.

Record effective route, model, effort/thinking, outcome, elapsed time, input/output/cache-read/cache-creation tokens when available, and correction cycles in `.agents/runs/<run-id>/agent-stats.md`. Mark absent or incomparable telemetry `unknown`; do not delay otherwise completed work for token accounting. Compare keep-warm cost and observed cache reads before claiming it saved money.
