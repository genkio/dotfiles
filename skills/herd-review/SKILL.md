---
name: herd-review
description: "Herd-native code review: review a diff with one-shot reviewer workers in tmux panes (cheap models, pre-gathered shared context), then synthesize fact-checked findings for the implementer. Use ONLY when explicitly named, or when reviewer workers must run non-Claude models/CLIs (codex, opencode) that in-session subagents can't spawn. For normal code review default to subagent-review (read-only subagents pinned to a cheap model). Never invoke the built-in /code-review; its finders inherit the calling session's model and usage limits."
---

# herd-review - herd-native code review

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

reviewing a published PR: also pull its existing review threads + comments
(`gh pr view --comments` / `gh api .../pulls/<n>/comments`) into context.md.
classify every prior finding before deduping - "already raised" is not
"resolved":

- fixed by a commit: dedup it
- unanswered: re-raise it
- closed by author rebuttal WITHOUT a code change: do NOT dedup. fact-check
  the rebuttal like a fresh claim (spec/RFC/BCP citations get checked
  against the actual deployment context, not taken on authority); even if
  you end up agreeing, it goes in the synthesis as a shipping-unfixed risk,
  noting whether a follow-up ticket exists (a deferral without one is
  untracked risk - say so; the human files it). "author pushed back" is a
  state, not a resolution.

note a prior approval. skip only when a blind review is explicitly
requested (A/B evals).

## step 2 - fan out one-shot reviewers

three lenses, each a fresh one-shot reviewer pane on a cheap or mid tier -
never the master's (priciest) model. spawn each with `$LAUNCH` (your agent's
launch command, as in the herdlet skill) and a cheap/mid model id for your
backend (Claude `haiku`/`sonnet`).
write each lens prompt to `$WORK/lens-<x>.md` before spawning.

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
- major/blocker consequence must state blast radius: who hits it and how
  often in production ("every web user at token expiry" vs "one mobile
  user replaying a token"). severity tracks production impact, not code
  locality - a race on a path every request shares is a blocker.

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
    "HERDLET_ID=$PROJ/rev-$x CC_IMESSAGE_SKIP=1 $LAUNCH --model <cheap-id> \
     --permission-mode acceptEdits -p 'read and follow $WORK/lens-$x.md'"
done
herdlet wait --id $PROJ/rev-a,$PROJ/rev-b,$PROJ/rev-c --state done,blocked --timeout 550
```

the any-of wait (herdlet >= 0.3.0) wakes on the first transition; repeat
it until `herdlet list --prefix $PROJ/rev-` shows all done. a headless
reviewer should never sit `blocked` - if one does, `peek` it, it went
off-script.

optional 4th reviewer for cross-model diversity: if `codex` is on PATH,
run it through `codex exec` (stdin closed with `< /dev/null`, wrapped in
`timeout`, output redirected to `$WORK/findings-codex.md`, poll the file -
never `tail`). prefer the canonical reviewer prompt at
`~/pafin/skills/cryptact/prompts/codex-review.md` when present (substitute
the real $WORK paths); else feed it the lens-b prompt. different model
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
6. cheap dynamic check (driver only, when safe): if the diff adds an
   entrypoint/CLI or touches module loading / side-effect imports,
   smoke-import or run it once. read-only lenses cannot see load-time
   failures - a missing side-effect import passes every static read and
   fails 100% at runtime.
7. scope check: if the diff changes a symbol shared by flows outside the
   PR's stated scope (e.g. a mobile PR touching the web session path),
   name each such flow and what changed for it in the summary - even when
   no finding fired on it. the human tests what the PR says it's about;
   flows it silently changes are the ones nobody exercises.

write the survivors to `plans/<milestone>-review-findings.md` with stable
ids (F1, F2, ...) and `herdlet send` the implementer worker the path. kill
the reviewer panes; a re-review after fixes gets fresh one-shot reviewers.

finding ids are workspace bookkeeping, not vocabulary: they must never
appear in committed code, comments, test names, or commit messages. plans/
is git-ignored, so `(review F6)` in a comment is noise nobody outside the
session can resolve - the fix carries its rationale in plain words, in
place. tell the implementer this when handing over the findings file, and
treat any id that leaks into the diff as a finding on the next round.

## re-review rounds - the leniency ladder

each round asks for less, never more, and everything worth raising goes out
all at once - never raise on round N+1 what you could have raised on round N
unless the code changed since. one exception: a major/blocker closed by
rebuttal without a code change stays raisable in every round (and in later
sessions) until it is fixed or the accepted risk is in the human-facing
summary - politeness must not compound across rounds.

- round 1: full spectrum - blocker/major/minor/nit in one pass
- round 2: verify round-1 findings are fixed without regressing the changed
  lines. blockers/majors always go out; beyond that only minors + IMPORTANT
  nits (risks a future bug or real confusion - no naming bikeshed, no
  "could be slightly simpler"). drop the rest silently.
- round 3+: nothing above nit remains = call it done; at most the few
  important nits ride along
- prior clean round + nothing new on the diff since = say exactly that,
  zero comments

(company version, incl. GitHub round counting:
`~/pafin/skills/cryptact/docs/review-round.md`)

## hard rules

- never run the built-in /code-review (or any in-session fan-out review)
  from a herd session
- reviewers are read-only on the codebase; only `$WORK` files are written
- never commit, push, or open a PR off the back of a review; findings go
  to the implementer, the human owns the PR
- GitHub is read-only: `gh` only to view/fetch (pr view, api GET). never
  post comments, reviews, approvals, or tickets - every outbound word on
  the PR is written by the human. findings live in local $WORK/plans
  files only.
