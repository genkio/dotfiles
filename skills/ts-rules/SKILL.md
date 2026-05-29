---
name: ts-rules
description: TypeScript style and safety rules. Use when writing, reviewing, or refactoring TypeScript code. Bans type-system escape hatches (as, !, any, @ts-ignore, eslint-disable), enforces consistent patterns (discriminated unions, exhaustive switches, prefer-const, eqeqeq), and prescribes structural choices (no enum, no Record, pick interface or type).
license: MIT
---

# TS Rules

Don't lie to the compiler. Fix types, never silence them.

## Type System Integrity

- **No `as` type assertions.** Prefer type guards and inference. `as` is legitimate only for narrowing `unknown` after validation or asserting a literal type.
- **No `!` non-null assertion.** Use optional chaining (`?.`) or a type guard.
- **No `any`.** Use `unknown` and narrow, or define a proper type.
- **No `@ts-ignore` / `@ts-expect-error`.** Fix the types.
- **No `eslint-disable` comments.** Fix the code, not the linter.

If the compiler complains, it's usually right. Understand why before overriding.

## Equality and Mutability

- **`eqeqeq: always`.** No `==` / `!=`. Use `===` / `!==`.
- **`prefer-const`.** Use `const` when never reassigned.

## Object Shapes

- **No `Record<K, V>`.** Use index signatures and mapped types:
  - String-keyed: `{ [userId: string]: User }` with a semantic key name, not just `key`.
  - Union-keyed: `{ [k in Status]: Handler }`.
- **No `enum`.** Use `as const` arrays plus derived union types:

  ```ts
  const STATUSES = ['idle', 'loading', 'done'] as const;
  type Status = typeof STATUSES[number];
  ```

- **Pick `interface` OR `type` consistently** per file or project. Don't mix unless extension semantics require it.

## State Modeling

- **Discriminated unions over optional fields when state shape varies.**

  ```ts
  // Bad: invalid combinations representable.
  type Result = { data?: User; error?: Error };

  // Good: invariant enforced by the type.
  type Result =
    | { status: 'ok'; data: User }
    | { status: 'err'; error: Error };
  ```

- **Exhaustive switch on unions.** Use `assertNever` as the default branch so adding a new variant fails the build:

  ```ts
  function assertNever(x: never): never {
    throw new Error(`Unhandled case: ${JSON.stringify(x)}`);
  }

  switch (r.status) {
    case 'ok': return r.data;
    case 'err': throw r.error;
    default: return assertNever(r);
  }
  ```

## Async

- **No floating promises.** `await` them or attach a `.catch()` handler. Unhandled rejections crash the process.
