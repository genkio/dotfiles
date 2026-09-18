---
name: code-discipline
description: "Write, review, and refactor code with minimal, verified changes. Use to understand the problem before implementing, reuse existing solutions, keep changes within scope, define success criteria, and fix type errors without bypassing the checker."
---

# Code Discipline

Understand the problem before changing code. Prefer an existing solution, limit changes to the task, and verify the result. For trivial tasks, keep the investigation and planning brief.

## Understand the task

Read the relevant code and trace its behavior from input to result. Check callers before changing a shared function so the fix covers more than the reported case.

State assumptions that affect the solution. If the request has multiple plausible meanings, explain them rather than silently choosing one. If uncertainty blocks a correct implementation, ask before proceeding.

Point out a simpler approach when one exists. Explain any tradeoff that changes the scope or behavior the user requested.

## Use the simplest suitable solution

Before writing new code, check these options in order. Stop at the first one that meets the requirements:

1. Confirm that the behavior is needed now. Skip speculative features and explain why.
2. Look for an existing helper, type, or pattern in the codebase.
3. Check the standard library.
4. Check native platform features. Prefer a browser date input to a picker library, CSS to JavaScript, or a database constraint to application logic.
5. Check dependencies already installed. Do not add a dependency for something a few clear lines can do.
6. If one clear line solves the problem, use it.
7. Otherwise, write only the code the task requires.

Do not add abstractions for single-use code, unrequested configuration, or error handling for impossible cases. If a shorter implementation is equally clear and correct, use it.

## Keep changes within scope

Match the existing style. Do not reformat adjacent code, rewrite unrelated comments, or refactor working code outside the task.

Remove imports, variables, and functions that your changes make unused. If you find unrelated dead code, mention it instead of deleting it.

Before finishing, check that every changed line serves the user's request.

## Define how to verify the result

Turn the request into checks you can run:

- For validation, write tests for invalid inputs and make them pass.
- For a bug, write a test that reproduces it and make it pass.
- For a refactor, check that tests pass before and after the change.

For a multi-step task, give a brief plan with a check for each step:

```text
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Use those checks to guide the work. Continue until they pass, or explain what prevents verification.

## Fix the cause rather than hide the problem

Prefer a correct solution over a faster patch that leaves the underlying problem in place. Fix a shared cause where appropriate instead of adding the same workaround at each call site.

Do not leave temporary hacks or cleanup TODOs in committed code. Do not suppress errors, silence warnings, or bypass types to make a build pass.

If the only available solution adds technical debt, stop before implementing it. Explain the tradeoff and ask for approval. State any deferred work explicitly.

## Keep types accurate

In typed languages, fix the mismatch between the types and the intended behavior. Do not widen a return type, loosen a parameter, or make a field optional just to remove an error.

Do not use `any`, casts through `unknown`, `@ts-ignore`, or `// @ts-expect-error` to bypass the checker. Prefer inference and type guards over `as` assertions.

Use an assertion only when you have information the compiler cannot infer, such as a validated `unknown`, a literal type, or an untyped library boundary. Understand the error before deciding that an assertion is necessary.
