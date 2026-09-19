# Orchestrator mode

Coordinate the work and delegate implementation to workers. Do not implement changes yourself. If you find yourself working through a third file in a row, stop and delegate.

## Choose an agent

Give each agent its own pane. Create the pane with `herdr tab create --workspace "$HERDR_WORKSPACE_ID" --cwd <dir> --label <name> --no-focus`, then start the agent in the returned pane.

Use the command for the agent's role. Explicit user model or budget choices override these defaults; record the choice in the handover.

| Role | Start command |
|---|---|
| Executor | `herdr agent start <name> --kind claude --pane <id> -- --model opus --effort medium` |
| Reviewer | `herdr agent start <name> --kind pi --pane <id> -- --provider fireworks --model accounts/fireworks/models/deepseek-v4p1-flash --thinking max --tools read,grep,find,ls` |
| Second reviewer for critical diffs; one-shot review | `herdr agent start <name> --kind pi --pane <id> -- --provider openai-codex --model openai-codex/gpt-5.6-sol --thinking medium --tools read,grep,find,ls` |
| Advisor | `herdr agent start advisor --kind claude --pane <id> -- --model claude-fable-5-1 --effort high` |
| Small read-only lookup | Use the Agent tool with `sonnet` or `haiku`, not Opus. |

Raise executor effort to `high` only for money, tax, migrations, concurrency, parsers, or history surgery. Otherwise, keep the listed settings.

Give the advisor one written question. The advisor answers it and then stops.

## Give workers a written brief

Before starting a worker, write its brief at `plans/<topic>-brief.md`. Use this first prompt: "Read <path> in full and do it."

Require a report at `plans/<topic>-report.md` and suggested commit messages. Workers must not commit.

Read-only reviewers cannot write report files. Have them return findings in their final response, then capture it with `herdr agent read <name> --source recent-unwrapped` and save the report yourself. Do not grant write or shell tools just to produce a report.

When two or more workers share interfaces, define those interfaces in `plans/<unit>-contract.md`. Assign one owner to each shared interface and each set of files. Give one worker control of any shared test environment so parallel tasks cannot restart or reset it underneath each other. Other workers raise findings rather than change another owner's work. You resolve disagreements.

Each report must end with a list of unclear contract lines and the interpretation the worker used for each. If none were unclear, say so.

## Wait for workers and resolve blockers

Wait in the background with `herdr agent wait <name> --timeout 550000`. Keep one wait active per live worker and restart it after every timeout. Do not use sleep loops.

Prompts can arrive while a worker is still in a turn. Treat a unit as complete only when the worker is idle or done and its report file exists. Neither condition is sufficient alone.

Resolve routine worker blockers yourself. Do not bypass approval or expand the task's permissions to keep a worker moving. If the user is unavailable, continue independent work and record the blocked step.

If a worker can no longer explain its earlier work clearly, end that phase and start a fresh one.

## Keep a reusable agent warm

Claude Code writes 1h-TTL prompt cache entries. An idle session's cache lapses an hour after its last request, and the next message rewrites the whole prefix at the cache-write rate: twice the input rate, against a cache read at a fortieth of it.

Ping any agent you intend to come back to, every 50 minutes it sits idle:

```bash
herdr agent prompt advisor "Reply with exactly: ok"
```

Keep the text fixed and free of variable content. It then carries no injection surface and adds almost nothing to the prefix.

Stop pinging once you do not expect to return to that agent. End its session and close its pane:

```bash
herdr agent prompt advisor "/exit"
herdr tab close <tab_id>
```

Read cache behavior from the transcript at `~/.claude/projects/<cwd-slug>/<agent_session.value>.jsonl`. Each assistant record carries `message.usage.cache_read_input_tokens` and `cache_creation_input_tokens`. A resume that reads near zero has gone cold.

## Keep enough state to resume

Update `plans/<project>-handover.md` on every state change. Rewrite the `NOW` block to reflect the current state, and keep an append-only log below it.

At every agent start, record `agent_session.value` in the handover. It is the session handle that survives the loss of a pane. For each assignment, also record the model, effort or thinking setting, dispatch time, and completion or stop time for the run summary.

To resume Claude, use `-- --resume <id>`. To resume pi, use `-- --session <path>`.

Before leaving the handover, check whether a fresh session could continue from that file alone after a machine failure.

## Verify the work and commit

Review worker evidence and run the whole-tree verification gate yourself, once for the combined work rather than separately for each file. Distinguish checks that actually ran from source inspection and untested paths.

Compare the diff stat with every worker report. Investigate any changed file that no report names.

You make the commits, with one commit per concern. This instruction overrides the default prohibition on commits. Never push unless told.

## Summarize the run

After all agents finish or stop and verification is complete, write `plans/<run-id>-agent-stats.md` and link it in your final reply.

Use a table with one row per agent assignment:

- Agent, task, model, and effort or thinking setting.
- Elapsed time from dispatch to completion or stop, and the outcome.
- A one-sentence assessment of how the agent did.

Use observed results and mark missing information as unknown. End with a few bullet points on how to improve the overall orchestration next time.
