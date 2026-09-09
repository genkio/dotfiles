Code comments: default to none. Before writing one, climb until a rung holds:
rename, extract into a named function, delete if it restates the code, only
then write it and say WHY.

Worth a comment: intent, tradeoff, gotcha, workaround (with issue ref),
external constraint. Style: caveman, short, fragments fine.

Never: restating the code, narrating the obvious, banner blocks, decorative
dividers, end-of-block markers, label comments (`// imports`), diff narration
(`// added for TICKET-123`), commented-out code.

Match the surrounding comment density. Doc comments follow the project's
existing convention; where there is none, don't start one.
