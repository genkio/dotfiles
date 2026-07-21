---
name: herd-review
description: "Cross-model review panel: subagent-review's in-session Claude lenses PLUS non-Claude coding agents (codex) as full reviewers in tmux panes, synthesized with model provenance and a cross-family rebuttal round. Use when explicitly named, or when the diff's stakes warrant a second model family (money/tax paths, migrations, verification/archival gates, security). Never a Claude-only pane fan-out - for normal review default to subagent-review. Never invoke the built-in /code-review; its finders inherit the calling session's model and usage limits."
---

# herd-review - cross-model review panel

requires tmux (+ the herdlet CLI when panes run as herd workers). you are
the driver: you gather context once, run the Claude lenses IN-SESSION
(subagent-review mechanics - panes never host Claude one-shots; subagents
do that cheaper and more reliably), give each non-Claude agent its own pane
as a FULL reviewer with its own loop, and synthesize with model provenance.
different model families have different blind spots; consensus across
families is the strongest confirmation a local review can produce, and a
finding only one family can see is the whole reason to pay for two.

## when to run this

cross-model review roughly doubles the cost - gate it on blast radius,
never on tmux being available: money/tax paths, migrations, verification
and archival gates, security-adjacent changes, or an explicit ask. routine
diffs stay on subagent-review alone (it already has a cheap ONE-SHOT codex
slot; this skill is the full-agent version with a rebuttal round).

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

## step 2 - fan out: Claude lenses in-session, other models in panes

the three Claude lenses run as in-session read-only subagents exactly per
subagent-review (a - line scan; b - contract vs impl; c - cross-file
tracer), against the same `$WORK/context.md` + `review.diff`, findings
persisted to `$WORK/findings-<x>.md` by the driver. do NOT spawn Claude
one-shots in panes - that was this skill's historical failure mode: pane
lifecycle babysitting and scrollback scraping for work subagents do
natively.

each NON-Claude agent gets a pane and runs as a full agent - its own loop,
its own choice of what to open in the repo. the value is a genuinely
different exploration, not a different logo on the same prompt.

- brief: `$WORK/lens-<agent>.md` = lens b's three questions (is the problem
  real / is this the right solution / is it correctly implemented) + the
  shared contract (context.md first, then the diff; repo checked out in
  cwd, read any file; never edit; one finding per line, severity first,
  blast radius on majors)
- handback is a FILE, never pane scrollback: launch with output redirected
  to `$WORK/findings-<agent>.md`; poll the file or process - never `tail`
  (it buffers until exit)
- codex: `codex exec` per `~/pafin/skills/shared/docs/codex.md`, but the
  sandbox flag is environment-specific: worker pods must bypass codex's
  sandbox (the doc explains why); LOCALLY use `--sandbox read-only` - it
  works and enforces the read-only contract for free. close stdin
  (`< /dev/null`); wrap in a timeout (macOS has no `timeout` - gtimeout,
  or skip the wrapper and poll). prefer the canonical reviewer prompt at
  `~/pafin/skills/cryptact/prompts/codex-review.md` when present
  (substitute the real $WORK paths)
- lifecycle via herdlet works for codex exec workers as-is: launch with
  `HERDLET_ID=$PROJ/rev-codex`, the wired codex hooks register the worker,
  track working/done, and record the SESSION id - verified empirically
- step 4 re-enters that session: if the pane closed when exec exited,
  spawn a fresh pane and `herdlet resume --id $PROJ/rev-codex --pane %N`
  (types `codex resume <session>`), then `herdlet send` the rebuttal;
  plain `tmux split-window` + file polling is the fallback when hooks
  aren't wired (`herdlet setup` wires them)

## step 3 - synthesize (this is the value-add)

do NOT concatenate the findings files:

1. merge the same issue across reviewers and TAG every survivor with its
   contributing models, short form: `[fable5]`, `[gpt5.6]`,
   `[fable5+gpt5.6]` (resolve the real model names at runtime, never
   hardcode). consensus across MODEL FAMILIES is the strongest
   confirmation, and the tags carry provenance into the findings file -
   and, if the human posts them, into the PR
2. fact-check every claim against the real code; drop or correct anything
   that doesn't hold (reviewers hallucinate line numbers and invent issues)
3. scrutinize lone findings hardest - a single-reviewer finding is either
   the best catch or a false positive. note which family keeps catching
   what the other misses; that map says where each model is blind
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

## step 4 - cross-family rebuttal (the panes earn their keep)

before writing the findings file, hand each surviving major/blocker to the
OTHER family for refutation: the codex pane gets the Claude-lens survivors,
a fresh in-session subagent gets codex's - each prompted to REFUTE, not
confirm. a finding that survives cross-examination by a different model
family is as confirmed as a local review gets; one that dies here was
plausible-but-wrong and would have wasted the implementer's time. the
persistent pane makes this a follow-up message, not a fresh context build.

write the survivors to `plans/<milestone>-review-findings.md` with stable
ids (F1, F2, ...) and their model tags, and `herdlet send` the implementer
worker the path. kill the reviewer panes only now; a re-review after fixes
gets fresh reviewers.

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

- never run the built-in /code-review from a herd session
- Claude reviewers never run in panes - lenses are in-session subagents
  (subagent-review mechanics); panes host non-Claude agents only
- reviewers are read-only on the codebase; only `$WORK` files are written
- never commit, push, or open a PR off the back of a review; findings go
  to the implementer, the human owns the PR
- GitHub is read-only: `gh` only to view/fetch (pr view, api GET). never
  post comments, reviews, approvals, or tickets - every outbound word on
  the PR is written by the human. findings live in local $WORK/plans
  files only.
