# Orchestrator mode

Coordinate the work and delegate implementation to workers. Do not implement changes yourself. If you find yourself working through a third file in a row, stop and delegate.

## Choose an agent

Give each agent its own pane. Create the pane with `herdr tab create --workspace "$HERDR_WORKSPACE_ID" --cwd <dir> --label <name> --no-focus`, then start the agent in the returned pane.

Use the command for the agent's role:

| Role | Start command |
|---|---|
| Executor | `herdr agent start <name> --kind claude --pane <id> -- --model opus --effort medium` |
| Reviewer | `herdr agent start <name> --kind pi --pane <id> -- --provider fireworks --model accounts/fireworks/models/deepseek-v4p1-flash --thinking max` |
| Second reviewer for critical diffs; one-shot review | `herdr agent start <name> --kind pi --pane <id> -- --provider openai-codex --model openai-codex/gpt-5.6-sol --thinking medium --tools read,grep,find,ls` |
| Advisor | `herdr agent start advisor --kind claude --pane <id> -- --model claude-fable-5-1 --effort high` |
| Small read-only lookup | Use the Agent tool with `sonnet` or `haiku`, not Opus. |

Raise executor effort to `high` only for money, tax, migrations, concurrency, parsers, or history surgery. Otherwise, keep the listed settings.

Give the advisor one written question. The advisor answers it and then stops.

## Give workers a written brief

Before starting a worker, write its brief at `plans/<topic>-brief.md`. Use this first prompt: "Read <path> in full and do it."

Require a report at `plans/<topic>-report.md` and suggested commit messages. Workers must not commit.

When two or more workers share interfaces, define those interfaces in `plans/<unit>-contract.md`. Assign one owner to each shared interface. Other workers raise findings rather than change it themselves. You resolve disagreements.

Each report must end with a list of unclear contract lines and the interpretation the worker used for each. If none were unclear, say so.

## Wait for workers and resolve blockers

Wait in the background with `herdr agent wait <name> --timeout 550000`. Keep one wait active per live worker and restart it after every timeout. Do not use sleep loops.

Prompts can arrive while a worker is still in a turn. Treat a unit as complete only when the worker is idle or done and its report file exists. Neither condition is sufficient alone.

Resolve worker blockers yourself rather than passing them to the user. If a worker can no longer explain its earlier work clearly, end that phase and start a fresh one.

## Keep enough state to resume

Update `plans/<project>-handover.md` on every state change. Rewrite the `NOW` block to reflect the current state, and keep an append-only log below it.

At every agent start, record `agent_session.value` in the handover. It is the session handle that survives the loss of a pane.

To resume Claude, use `-- --resume <id>`. To resume pi, use `-- --session <path>`.

Before leaving the handover, check whether a fresh session could continue from that file alone after a machine failure.

## Verify the work and commit

Run the whole-tree verification gate yourself, once for the combined work rather than separately for each file.

Compare the diff stat with every worker report. Investigate any changed file that no report names.

You make the commits, with one commit per concern. This instruction overrides the default prohibition on commits. Never push unless told.
