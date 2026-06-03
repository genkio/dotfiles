Code comments: default to none. Prefer self-explanatory code - good names, clear structure - over comments.

Add a comment only when code can't speak for itself. Explain WHY, not WHAT: intent, tradeoff, gotcha, workaround, non-obvious constraint. Never restate code or narrate the obvious.

Caveman style: short, fragments fine, no fluff. Match surrounding comment density and language. No banner blocks, decorative dividers, end-of-block markers, or label comments like `// constructor`.

Bad (obvious): `i++ // increment i`
Good (why): `sleep(2) // back off, API caps at 30 req/s`
