# herdr runbook

Mechanics for herdr agents, reviewer output, and saved state in `~/.claude/prompts/orchestrator.md` and `~/.claude/prompts/review.md`; PR commands are in `~/.claude/prompts/pr-runbook.md`. Check installed `herdr` help and real session metadata before relying on a command or field.

## Roles and launch arguments

This is the single source for roles, default models, and permissions. Per-run user choices win.

| Role | Used by | Default model | Launch arguments |
|---|---|---|---|
| Orchestrator | both modes | Claude Opus, high effort | the invoking session, not launched here |
| Advisor | both modes | Claude Fable, medium effort | `--kind claude -- --model claude-fable-5-1 --effort medium` |
| Executor | orchestrator; review reproduction | Claude Opus, medium effort | `--kind claude -- --model opus --effort medium` |
| Reviewer (Reviewer A in review mode) | both modes | DeepSeek Flash, maximum thinking, read-only | `--kind pi -- --provider fireworks --model accounts/fireworks/models/deepseek-v4p1-flash --thinking max --tools read,grep,find,ls` |
| Second reviewer (critical changes; Reviewer B in review mode) | both modes | Codex GPT-5.6 Sol, medium thinking, read-only | `--kind pi -- --provider openai-codex --model openai-codex/gpt-5.6-sol --thinking medium --tools read,grep,find,ls` |
| Reviewer C | review mode | Claude Opus, high effort, read-only | `--kind claude -- --model opus --effort high --tools Read,Grep,Glob --strict-mcp-config` |
| Small read-only lookup | both modes | Sonnet or Haiku | Agent tool, not a pane |

Reviewers get read-only tools only; never add write or shell tools, even to let one save its response. The advisor launches with full tools but is read-only by instruction: it must not edit files, run tests or services, or change any environment.

Confirm effective provider, model, and effort from launch configuration and session evidence, never self-description. Claude transcripts record the model but not the effort, so the launch arguments you passed are the effort evidence; a pi session file appears only after the first turn, with `model_change` and `thinking_level_change` records. If a route is unavailable or resolves to another model, stop and ask the user. Never fall back without permission, and record any approved substitution.

## Names and workspace

Use one name as tab label, agent name, and session name (`--name`), so the user can filter herd sessions:

- Orchestrator mode: `herd-<run>-<role>`, such as `herd-r9-exec-1`.
- Review mode: `herd-pr<N>-advisor` for the advisor, and the round for everyone else, such as `herd-pr6232-r2-rev-a`.
- At most 32 characters of lowercase letters, digits, `_`, and `-`. Check `herdr agent list` first and add `-2` only if the name is taken by a live agent; a new session's advisor reuses the base name when it is free.

Take the workspace from `HERDR_WORKSPACE_ID`, else from the current pane, never the focused workspace. If both are empty, stop and ask.

```bash
herdr pane current --current   # workspace is .result.pane.workspace_id
```

## Launch and dispatch

Before launching a parallel implementation writer, create its worktree from the integration repository. Choose and record an absolute path, a new branch, and the baseline commit. A serial writer can use its assigned integration tree. A review reproduction worker uses the review worktree with the temporary-file limits in `review.md`. Every agent must be able to read its brief or packet.

```bash
git worktree add -b <branch> <absolute-worktree-path> <baseline-oid>
```

```bash
herdr tab create --workspace <workspace-id> --cwd <absolute-dir> --label <name> --no-focus
herdr agent start <name> --kind claude --pane <returned-pane-id> -- --name <name> --model opus --effort medium
herdr agent prompt <name> "Read <absolute-brief-path> in full and execute it." --wait --timeout 550000
```

Substitute the role's launch arguments, always after `--name <name>`. A first Claude launch in a new directory can stop at the folder-trust dialog, and `agent start` returns `agent_not_ready`. Read the pane to confirm it. Accept only for a directory you created for this run or the worktree the user started the session in; otherwise ask. The dialog defaults to "No, exit", so select "Yes, I trust this folder", then wait; the agent keeps its name, so do not start it again:

```bash
herdr agent send-keys <name> down enter
herdr agent wait <name> --until idle --timeout 60000
```

A worker brief names its own TASK/ATTEMPT. Dispatch an advisor or reviewer packet with `Read <absolute-packet-path> in full and execute it. Your TASK/ATTEMPT is <task>/<attempt>.`, so one packet can serve several reviewers.

`start` does not submit work; the prompt does. Dispatch with `--wait`, which requires observed `working` or `blocked` before it accepts a settled state; a bare `agent wait` after an unwaited prompt can return at once on the previous state. To run several agents in parallel, send each prompt without `--wait`, confirm it started with `herdr agent wait <name> --until working --timeout 30000` (a single `agent get` right after the prompt can still show `idle`), and record the dispatch time; then wait on each. Dispatch once; if the outcome is uncertain, inspect lifecycle, transcript, worktree, and report before sending anything again.

## Agent records

Record in the handover, for every agent: name, tab and pane IDs returned by `tab create`, session handle (`agent_session.value` from the `agent start` result), cwd, baseline, branch, effective routing, task and attempt, dispatch and stop times, report path, keep-warm state, and whether the tab is open and why.

## Wait and capture

```bash
herdr agent wait <name> --timeout 550000
herdr agent read <name> --source recent-unwrapped
```

A wait timeout is not failure: wait again rather than sleep-looping or sending a status prompt, and never interrupt healthy long work. A unit completes only when the agent is `idle` or `done` and its report or captured response names the current task and attempt. An older report is not completion.

`agent read` can lose most of a long response; then take it from the transcript instead of asking the agent to repeat it:

- Claude: `~/.claude/projects/<cwd-slug>/<agent_session.value>.jsonl`; assistant records have `type: assistant` with text blocks in `message.content`. One message can span several records that share a `message.id`.
- pi: `agent_session.value` is the session file; assistant records have `message.role: assistant`, and the turn's last one has `stopReason: "stop"`.

Find the user record of the prompt you dispatched. The response is the final assistant text of that turn; early commentary before tool calls is allowed and is not part of it. Skip tool-only records and keep-warm `ok` replies. The response should begin with `TASK/ATTEMPT: <task>/<attempt>`. If the header is missing but the text clearly answers this dispatch, record a protocol deviation and use it; if a different ID appears, it is not this assignment's response. Verify the schema in the current installation.

Save read-only responses in full yourself under `.agents/runs/<run-id>/`, or in review mode as `review.md` describes.

## Reviewer output format

Both modes use this one format. Put the block below, verbatim, in every review packet, and dispatch with the packet line from "Launch and dispatch", using IDs such as `auth-review/1` or `pr6232-r2-rev-a/1`.

````markdown
Start your response with one line: `TASK/ATTEMPT: <task>/<attempt>`, using the IDs you were
assigned when this packet was dispatched. After it, return a flat list, highest severity first.
One finding per line and nothing else: no preamble, no summary, no "looks good overall".

```
[blocker|major|minor|nit] path/to/file.ext:LINE | what is wrong and its consequence | proof (file:line, before/now, or repro) | fix
```

- blocker: must fix before merge (bug, data loss, security hole, breaks the build).
- major: should fix (wrong approach, missing edge case, real correctness risk).
- minor: worth fixing (clarity, small correctness issue, missing test).
- nit: optional polish.

For an open previous finding, prepend its ID to the schema above:
`F3 [major] path:LINE | issue | proof | fix`. A previous finding you consider fixed gets no line.
For a blocker or major in unchanged code, explain in the proof why earlier rounds missed it.
Apart from this packet and the files it names, do not open `.agents/`; it holds other
reviews. You can read files but not run code. When a proof depends on behavior, give the input, the
expected result, and the result the code produces.

A few real bugs beat ten defensive comments. Leave out confirmations that correct code is
correct, linter nits, speculative performance concerns, and defensive code for impossible
cases. If a finding is not worth the author's time, do not write it.

If there are no findings, the line after TASK/ATTEMPT says exactly `No findings.` and nothing
follows it.
````

## Recover and resume

A long turn is not a stall; repetition without new evidence or state change may be. Fix the cause before retrying. The default budget is one recovery retry: same task ID, new attempt ID, and renaming never resets it. Record every attempt and outcome.

Before resuming a session, re-read the brief, handover, and routing. Original forms (check installed help):

```bash
herdr agent start <claude-name> --kind claude --pane <id> -- --resume <claude-session-id>
herdr agent start <pi-name> --kind pi --pane <id> -- --session <pi-session-path>
```

Never attach two writers to one writable scope. Stop or isolate the old worker before a replacement starts, and reconcile late work against the current integration state.

### Reconcile agents

Run `herdr agent list` and match each agent named for this run or PR against its handover record, including the pane ID. Classify each one, and recover or replace only after any state comparison the mode requires:

- `working`: let it finish and wait on it. Never launch a replacement for a live agent.
- `idle` or `done`: find the user record of the recorded dispatch in its transcript. If there is none, the dispatch never landed: send it now under the same attempt and record it. Otherwise, if its response is not saved, capture it as in "Wait and capture".
- Missing and recorded as closed with its output saved: expected; no action.
- Missing while the handover shows its attempt unfinished: the attempt was interrupted. Inspect its transcript, report, and worktree, then use the recovery budget.
- Not in the handover: the log is behind. Identify its task from its transcript and record it; if you cannot, stop and ask the user.

## Saved state and resume (orchestrator mode)

Save state after each of your own actions that changes a tree (creating a worktree, freezing, staging, committing, cherry-picking) and before compaction or exit. Save the integration tree as `state-integration.txt`, and each worker worktree that still holds uncommitted work as `state-<worktree-dir-name>.txt`, in `.agents/runs/<run-id>/`. Run each tree's save as its own `bash -euo pipefail` process, so any failing command aborts it; `set -e` inside a subshell of your own shell is not reliable (it is off on the left of `&&`, and some harness shells ignore it):

```bash
bash -euo pipefail -c '
  git -C <dir> rev-parse HEAD
  git -C <dir> diff --full-index --binary HEAD | git hash-object --stdin
  git -C <dir> diff --cached --full-index --binary HEAD | git hash-object --stdin
  git -C <dir> -c core.quotePath=false ls-files -o --exclude-standard -- . ":!.agents"
  git -C <dir> -c core.quotePath=false ls-files -o --exclude-standard -- . ":!.agents" | git -C <dir> hash-object --stdin-paths
' > <run-dir>/state-<label>.txt.tmp && mv <run-dir>/state-<label>.txt.tmp <run-dir>/state-<label>.txt
```

The two diff hashes cover working-tree content and the index separately, and the untracked listing covers the whole tree, so new files outside a worker's scope show up too. On a nonzero exit, keep the previous state file, record the failure, and never use the partial output. After a successful save, append `<time> state saved: <labels>; working agents: <names or none>` to the event log and set `State saved: <time>` in NOW. That line is the boundary resume compares against.

To resume, read the handover NOW section, event log, and saved state before any other action: no dispatch, sync, staging, or commit. Then:

1. Reconcile agents as above.
2. Produce each state again with the same commands and compare it with the saved file using `diff`.
3. The integration tree must match. A difference is explained only by an orchestrator action the event log records after the last `state saved` line, such as a commit; confirm that action's result and record it.
4. In a worker worktree, `HEAD` and the index must match unless the event log records your own staging or commit there, because workers never commit or stage. A recorded freeze moves the new files from the untracked listing into the working-tree hash and leaves the index hash unchanged. Other working-tree and untracked changes inside the worker's scope are explained when the worker is still `working`, or its report for the current attempt accounts for them. Changes outside its scope are not.
5. Stop and tell the user about any unexplained difference. Never reset, stash, clean, or overwrite to make the state match; the difference is evidence.
6. Save fresh state, log the reconciliation, and continue from the recorded next action.

## Close finished agents

Close a tab once the agent is `idle` or `done`, its output is saved, and its records are in the handover; the transcript stays on disk. Keep a tab open only while you will prompt that session again: the advisor until its last verdict or judgment, or a worker until its unit is committed. Reviewers never qualify. A later fix, such as one for `changes_required`, is a new attempt and can resume the recorded session.

Before closing, confirm with `herdr agent get <name>` that it is not `working` and its pane matches the recorded pane ID, and disarm keep-warm if it is armed. Then `herdr tab close <recorded-tab-id>`. Close only tabs you created, never your own pane or a user's tab.

## Keep the advisor warm

Optional: use it only when the advisor will idle more than 50 minutes and a cold cache would cost more than the pings. Use `~/.config/herdr/scripts/keepwarm.sh` with the advisor's pane ID, never hand-sent pings. While armed, it sends `Reply with exactly: ok` after 50 minutes without an assistant turn, only while the advisor is idle, and stops itself when the cache went cold, the window ends, or the session leaves the pane.

To warm it, first run `keepwarm.sh check <pane>` after the advisor's first turn; a fresh session has no transcript before that. If the check fails, do not warm it and record why. Once armed, wrap every advisor prompt, because a ping can collide with it and `--wait` may accept the ping's turn:

```bash
KEEPWARM_QUIET=1 ~/.config/herdr/scripts/keepwarm.sh disarm <pane>
herdr agent prompt <advisor-name> "<packet>" --wait --timeout 550000
KEEPWARM_QUIET=1 ~/.config/herdr/scripts/keepwarm.sh arm <pane>
```

`disarm` waits out an in-flight ping; `arm` lasts 8 hours unless given a duration such as `2h`; `KEEPWARM_QUIET=1` silences only arm and disarm notices. Check `keepwarm.sh status` rather than assuming it is armed. A ping reply is never progress or acceptance evidence.

## Freeze and integrate

Freeze a worker's unit only after `herdr agent get <name>` shows it `idle` or `done` and its report for the current attempt is saved, because freezing writes to the worktree's index. Only the orchestrator freezes; workers never stage.

First list what actually changed, not only what the report says:

```bash
git -C <worker-dir> diff --name-only <baseline-oid>
git -C <worker-dir> -c core.quotePath=false ls-files -o --exclude-standard
```

First set aside unchanged pre-existing files recorded in the handover. Every remaining path must be within the brief's writable scope and accounted for by the report. Otherwise block the unit. Do not exclude changes to a user-owned file merely because its path existed at the baseline. Then mark the worker's new files and save the diff:

```bash
git -C <worker-dir> add -N -- <new-path>...
git -C <worker-dir> diff --full-index --binary <baseline-oid> > <absolute-run-dir>/<task>-reviewed.diff
```

Run the later staging, compare, and commit commands with the same `git -C <worker-dir>`, and stage by explicit path, never broadly. `--full-index` writes full blob IDs even for text files (`--binary` alone does not), so an identical diff means identical content. After review, stage exactly the reviewed paths and check that `git -C <worker-dir> diff --cached --full-index --binary <baseline-oid>` is byte-identical to the reviewed diff (`cmp`). Any difference means the content changed; freeze and review again. After committing, check that `git -C <worker-dir> diff --full-index --binary <baseline-oid> <commit>` still matches, then cherry-pick into the integration branch.

A cherry-pick onto a moved integration branch can merge into different content, and blob IDs then differ even for the same change, so compare patch IDs instead: `git diff <commit>^ <commit> | git patch-id --stable` in the worker worktree must equal the same for the new integration commit. Resolve mechanical conflicts yourself, send conflicts that need judgment to a worker, and review any integration commit whose patch ID differs before continuing. Record commit IDs in the handover. Never push or deploy without authorization.

Worktrees isolate source, not runtime. Install dependencies in one only for checks its brief authorizes; a shared pnpm store still needs per-worktree links. In the canonical integration worktree, follow the repository's install (for example `pnpm install --frozen-lockfile`), build, lint, typecheck, and test procedure, and run the final gate on the final combined tree. For services and e2e, follow the user's skill, and give the advisor the revision, configuration, commands, exit status, and salient output.

## Usage accounting

Write `agent-stats.md` in the run directory, or in `round-<k>/` in review mode, with one row per assignment: agent, task, effective model and effort, elapsed time, outcome, input, output, cache-read, and cache-creation tokens, correction cycles, and a short evidence-based assessment.

Count usage only between each assignment's dispatch and completion, so a reused session is not counted twice; label corrections and pings separately. Claude records expose `message.usage` (`input_tokens`, `output_tokens`, `cache_read_input_tokens`, `cache_creation_input_tokens`); count each `message.id` once, from its last record. pi records expose `usage` (`input`, `output`, `cacheRead`, `cacheWrite`, `cost.total`); inspect real records first, since schemas change. Keep-warm logs each ping's cache counts in `~/.local/state/herdr-keepwarm/log`, including `(disarm)` pings; compare that cost with observed cache reads before claiming savings. Mark missing values `unknown`.
