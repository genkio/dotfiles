---
name: comments
description: Code comment policy - default to none, write self-explanatory code instead. Use when writing, editing, or reviewing comments, docstrings, or JSDoc; when deciding whether a comment is warranted; or when stripping comment noise from generated or inherited code. Explains WHY not WHAT, in terse caveman style, and bans banner blocks, decorative dividers, end-of-block markers, label comments, and commented-out code.
license: MIT
---

# Comments

Default to none. Prefer self-explanatory code (good names, clear structure) over comments.

A comment is a cost: it goes stale, it adds noise, and it usually exists because the code is unclear. Fix the code first.

## Before writing one

Climb until a rung holds, then stop:

1. **Better name?** Rename the variable, function, or type. Most comments are a naming failure.
2. **Clearer structure?** Extract the confusing block into a named function. The name is the comment.
3. **Restates the code?** Delete it.
4. **Only then:** write it, and say WHY.

## What earns one

Non-obvious context the code cannot carry:

- **Intent** - what this is for, when the call site doesn't make it obvious.
- **Tradeoff** - why this way and not the obvious way.
- **Gotcha** - the surprising behavior that will bite the next reader.
- **Workaround** - the upstream bug or platform quirk being dodged, with issue ref or link.
- **Constraint** - the external limit driving the code (rate limit, protocol, legal rule).

```js
sleep(2) // back off, API caps at 30 req/s
```

## Style

Caveman: short, fragments fine, no fluff.

Match the surrounding comment density and language. A heavily commented legacy file is not an invitation to strip it; a bare file is not an invitation to start.

## Never

| Bad | Why |
| --- | --- |
| `i++ // increment i` | restates the code |
| `// loop over users` | narrates the obvious |
| `// ===== HELPERS =====` | banner block |
| `// ------------------` | decorative divider |
| `} // end if` | end-of-block marker |
| `// constructor`, `// imports`, `// state` | label comment |
| `// changed from foo to bar`, `// added for TICKET-123` | diff narration, git remembers |
| `// const old = ...` | commented-out code, delete it |

## Doc comments

Follow the project's existing convention. Where there is none, don't start one. Where there is, keep it WHY-heavy: param and return types already live in the signature.

## Reviewing a diff

Flag comments that restate the code or narrate the change. A diff whose new comments explain *what* the new code does is a signal the code needs better names, not more prose.
