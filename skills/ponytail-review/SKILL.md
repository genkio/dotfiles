---
name: ponytail-review
description: "Herd-native code review: review a diff with one-shot reviewer workers in tmux panes (cheap models, pre-gathered shared context), then synthesize fact-checked findings for the implementer. Use INSTEAD of the built-in /code-review or any in-session multi-agent review whenever coordinating agents via herdlet - in-session review subagents all inherit the calling session's model and usage limits."
---

# ponytail-review - herd-native code review

requires tmux + the herdlet CLI (same preconditions as the herdlet skill).
you are the driver: you gather context once, spawn disposable reviewers,
and synthesize. the expensive model (you) never fans out in-session
subagents and never makes a reviewer re-derive context.

## why not the built-in /code-review

slash-command review skills fan out finder subagents INSIDE the calling
session: every finder inherits the caller's model and burns the caller's
usage limits. from a herd master that means 8+ finders on your most
expensive model in one burst - measured in practice: ~280k output tokens,
~29M cache-read tokens, and a tripped session limit that stalled the whole
herd for hours. never invoke them from a herd session.

## step 1 - gather context once

```bash
PROJ=<project>                                  # your herdlet id prefix
WORK=plans/review-$(git rev-parse --short HEAD)
mkdir -p "$WORK"
git diff <base>...HEAD > "$WORK/review.diff"    # the diff under review
```

write `$WORK/context.md`:

- what the change claims to do (quote the spec / milestone brief)
- the agreed contract/design, quoted, if a brief exists (plans/*.md)
- focus list: correctness, security/auth, migrations + back-compat,
  perf on hot paths only, tests
- anything known-good or out of scope (don't pay reviewers to rediscover it)

## step 2 - fan out one-shot reviewers

three lenses, each a fresh `claude -p` pane on a mid or cheap tier -
never bare `claude`, never the master's model. write each lens prompt to
`$WORK/lens-<x>.md` before spawning.

every lens prompt carries the same contract:

- read `$WORK/context.md` first, then `$WORK/review.diff`; the repo is
  checked out in cwd - read any file for context the diff doesn't show
- use Read/Grep/Glob only; never edit code
- verify every claim against real code: open the file:line, trace concrete
  execution paths with concrete inputs, check the opposite before
  concluding. a line you can't confirm is a line you don't cite.
- write findings to `$WORK/findings-<x>.md`, highest severity first, one
  per line: `[blocker|major|minor|nit] file:line - issue + consequence;
  proof; fix.` quality over quantity. if clean, write exactly `No findings.`

the lenses:

- **a - line scan**: hunk-by-hunk diff read; diff-local bugs (logic, edge
  cases, off-by-one, error handling, type coercion)
- **b - contract vs impl**: three questions in order: is the problem real,
  is this the right solution (simpler / more correct / less risky
  alternative? matches the agreed design?), is it correctly implemented.
  a coherent implementation of the wrong thing is a finding.
- **c - cross-file tracer**: trace changed symbols to callers/callees
  outside the diff; stale call sites, violated invariants, integration
  breaks.

```bash
for x in a b c; do
  tmux split-window -d -c "$PWD" \
    "HERDLET_ID=$PROJ/rev-$x CC_IMESSAGE_SKIP=1 claude --model sonnet \
     --permission-mode acceptEdits -p 'read and follow $WORK/lens-$x.md'"
done
herdlet wait --id $PROJ/rev-a,$PROJ/rev-b,$PROJ/rev-c --state done,blocked --timeout 550
```

the any-of wait (herdlet >= 0.3.0) wakes on the first transition; repeat
it until `herdlet list --prefix $PROJ/rev-` shows all done. a headless
reviewer should never sit `blocked` - if one does, `peek` it, it went
off-script.

optional 4th reviewer for cross-model diversity: if `codex` is on PATH,
run the lens-b prompt through `codex exec` (stdin closed with
`< /dev/null`, wrapped in `timeout`, output redirected to
`$WORK/findings-codex.md`, poll the file - never `tail`). different model
families catch different bugs.

## step 3 - synthesize (this is the value-add)

do NOT concatenate the findings files:

1. merge the same issue across reviewers - consensus is signal
2. fact-check every claim against the real code; drop or correct anything
   that doesn't hold (reviewers hallucinate line numbers and invent issues)
3. scrutinize lone findings hardest - a single-reviewer finding is either
   the best catch or a false positive
4. drop noise: linter nits, speculative perf, defensive code for impossible
   cases, confirmations that correct code is correct
5. prioritize blocker > major > minor > nit; if a finding isn't worth the
   implementer's time, cut it

write the survivors to `plans/<milestone>-review-findings.md` with stable
ids (F1, F2, ...) and `herdlet send` the implementer worker the path. kill
the reviewer panes; a re-review after fixes gets fresh one-shot reviewers.

## re-review after fixes

each round asks for less, never more: round 2 checks only that round-1
findings are fixed and the fixes didn't regress the changed lines - no new
nits that could have been raised in round 1. round 3+: blockers/majors
only, otherwise call it done.

## hard rules

- never run the built-in /code-review (or any in-session fan-out review)
  from a herd session
- reviewers are read-only on the codebase; only `$WORK` files are written
- never commit, push, or open a PR off the back of a review; findings go
  to the implementer, the human owns the PR
