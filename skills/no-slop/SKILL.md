---
name: no-slop
description: Behavioral guidelines to reduce common LLM coding mistakes. Use when writing, reviewing, or refactoring code to avoid overcomplication, reach for existing/stdlib/native solutions before writing new code, make surgical changes, surface assumptions, define verifiable success criteria, prevent shortcuts that create technical debt, and respect the type system in typed languages.
license: MIT
---

# No-Slop Coding Guidelines

Behavioral guidelines to reduce common LLM coding mistakes, derived from [Andrej Karpathy's observations](https://x.com/karpathy/status/2015883857489522876) on LLM coding pitfalls.

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

### The ladder

Before writing new code, climb until a rung holds, then stop:

1. **Needs to exist?** Speculative need: skip it, say so. (YAGNI)
2. **Already in this codebase?** Reuse the helper, util, type, or pattern that already lives here. Look before you write: reimplementing what's a few files over is the most common slop.
3. **Stdlib does it?** Use it.
4. **Native platform feature covers it?** `<input type="date">` over a picker lib, CSS over JS, a DB constraint over app code.
5. **Already-installed dependency solves it?** Use it. Never add a new dependency for what a few lines do.
6. **One line?** One line.
7. **Only then:** the minimum code that works.

The ladder runs *after* you understand the problem, not instead of it. Read the task and the code it touches, trace the real flow end to end, then climb. Two rungs work: take the higher one and move on.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

## 5. Depth Over Speed

**Think deeply. Take the time. No shortcuts that mortgage the future.**

Before reaching for a fix:
- Understand the root cause before patching the symptom. Grep the callers of what you're about to change: one guard in the shared function beats a patch at every call site, and fixing only the reported path leaves sibling callers broken.
- Don't optimize for finishing fast. Optimize for finishing right.
- If a clean solution takes longer, take longer. Time is not the constraint — correctness is.

Reject technical debt by default:
- No workarounds, hacks, or "we'll fix it later" patches in committed code.
- No `// TODO: clean this up` left behind to solve the immediate problem.
- No suppressing errors, silencing warnings, or bypassing types to make something compile.
- If the only path forward is a hack, stop and surface it — explain the tradeoff and ask before writing it.

Ask yourself: "Am I solving this, or am I deferring it?" If deferring, say so explicitly rather than hiding it in code.

## 6. Respect The Type System

**In typed languages, types are the contract. Don't lie to the compiler.**

When working in TypeScript, Rust, Python with type hints, or similar:
- Don't reach for `as` assertions to silence type errors. Fix the types instead.
- Don't use `any`, `unknown` casts, `@ts-ignore`, or `// @ts-expect-error` to bypass the checker.
- Don't widen a return type, loosen a parameter, or make a field optional just to make red squiggles go away.
- If the compiler is complaining, it's usually right. Understand why before overriding it.

Type assertions are legitimate when the compiler genuinely cannot infer something the developer knows — narrowing `unknown` after validation, asserting a literal type, interop with untyped libraries. They are not a tool for making errors disappear.

Ask yourself: "Am I telling the compiler the truth, or telling it to shut up?" If the latter, fix the types.
