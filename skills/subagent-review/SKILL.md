---
name: subagent-review
description: "In-session code review: review a diff with read-only reviewer subagents (Agent/Task tool, each pinned to a cheap/mid model), then synthesize fact-checked findings for the implementer. DEFAULT review skill: use for any code-review request (bare 'review this branch/diff/PR' included) instead of the built-in /code-review, regardless of tmux/herdlet availability. Counterpart of herd-review (tmux-pane sessions), which is reserved for explicit requests or non-Claude reviewer models. Same three lenses and same synthesis; only the fan-out mechanism differs."
---

# subagent-review - in-session code review

you are the driver: you gather context once, spawn read-only reviewer
subagents in-session, and synthesize. this is the subagent twin of
herd-review - same lenses (a/b/c), same context contract, same
synthesis. the ONLY difference is step 2's fan-out mechanism: Agent/Task
subagents instead of tmux-pane sessions. no tmux, no herdlet required.

## relationship to herd-review - read this first

herd-review exists because the built-in /code-review fans out finder
subagents that inherit the caller's (expensive) model and burn its usage
limits. this skill DOES fan out in-session subagents - on purpose - so it
must neutralize that same cost from the other side: every reviewer subagent
is pinned to a cheap/mid model, NEVER the driver's. if your harness cannot
pin a cheaper model per subagent, use herd-review instead.

- the most reliable pin is a custom subagent type: frontmatter `model:` set
  to the cheap/mid tier (Claude `haiku`/`sonnet`) 
  plus `tools: Read, Grep, Glob` - cheap AND read-only in one,
  independent of whether your Task tool exposes a per-call model override.
  the built-in `Explore` type is read-only but can't pin a cheaper model.
  the driver (priciest model) only synthesizes.
- on Claude this type already exists: spawn each lens as the `review-lens`
  agent (`~/.claude/agents/review-lens.md`, sonnet + Read/Grep/Glob). do not
  define a new type unless review-lens is missing.
- spawn all three reviewers in a SINGLE message so they run concurrently.
  the harness notifies you when each finishes - never sleep-poll for them.

## step 1 - gather context once

```bash
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

## step 2 - fan out read-only reviewer subagents

three lenses, each a fresh read-only subagent on a cheap/mid model - never
the driver's. spawn all three in one message (they run concurrently). every
lens carries the same contract:

- read `$WORK/context.md` first, then `$WORK/review.diff`; the repo is
  checked out in cwd - read any file for context the diff doesn't show
- use Read/Grep/Glob only; never edit, write code, commit, or push
- verify every claim against real code: open the file:line, trace concrete
  execution paths with concrete inputs, check the opposite before
  concluding. a line you can't confirm is a line you don't cite.
- return findings as your final message, highest severity first, one per
  line: `[blocker|major|minor|nit] file:line - issue + consequence;
  proof; fix.` quality over quantity. if clean, return exactly `No findings.`
- major/blocker consequence must state blast radius: who hits it and how
  often in production ("every web user at token expiry" vs "one mobile
  user replaying a token"). severity tracks production impact, not code
  locality - a race on a path every request shares is a blocker.

the lenses (identical to herd-review):

- **a - line scan**: hunk-by-hunk diff read; diff-local bugs (logic, edge
  cases, off-by-one, error handling, type coercion)
- **b - contract vs impl**: three questions in order: is the problem real,
  is this the right solution (simpler / more correct / less risky
  alternative? matches the agreed design?), is it correctly implemented.
  a coherent implementation of the wrong thing is a finding.
- **c - cross-file tracer**: trace changed symbols to callers/callees
  outside the diff; stale call sites, violated invariants, integration
  breaks.

a subagent's final message is returned to you (the driver), not shown to
the user. persist each one verbatim to `$WORK/findings-<x>.md` so there is a
fact-check trail, then synthesize from the files.

optional 4th reviewer for cross-model diversity: if `codex` is on PATH and
authenticated, the driver runs it via Bash (`codex exec`, stdin closed with
`< /dev/null`, wrapped in `timeout`, output to `$WORK/findings-codex.md` -
it cannot be a subagent). prefer the canonical reviewer prompt at
`~/pafin/skills/cryptact/prompts/codex-review.md` when present (substitute
the real $WORK paths); else feed it the lens-b prompt. different model
families catch different bugs.

## step 3 - synthesize (this is the value-add)

do NOT concatenate the findings:

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
ids (F1, F2, ...) and hand the path to the implementer. a re-review after
fixes gets fresh one-shot subagents.

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

- reviewer subagents are pinned to a cheap/mid model, never the driver's;
  if you can't pin one, use herd-review instead
- spawn all reviewers in one message; never sleep-poll for them
- reviewers are read-only on the codebase; only `$WORK` files are written
  (by the driver, from the returned findings)
- never commit, push, or open a PR off the back of a review; findings go
  to the implementer, the human owns the PR
- GitHub is read-only: `gh` only to view/fetch (pr view, api GET). never
  post comments, reviews, approvals, or tickets - every outbound word on
  the PR is written by the human. findings live in local $WORK/plans
  files only.
