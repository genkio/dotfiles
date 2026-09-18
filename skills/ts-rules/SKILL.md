---
name: ts-rules
description: "Write, review, and refactor TypeScript with accurate types and consistent patterns. Use for rules on assertions, suppression comments, equality, object types, discriminated unions, exhaustive switches, and promises."
---

# TypeScript Rules

Fix type errors in the code or its types rather than bypassing the checker.

## Handle type errors without suppressing them

Prefer inference and type guards. Use `as` only to narrow a validated `unknown` or assert a literal type, such as `as const`.

Do not use:

- Non-null assertions (`!`). Use a type guard, or optional chaining when an absent value is acceptable.
- `any`. Define the type, or use `unknown` and narrow it.
- `@ts-ignore` or `@ts-expect-error`. Fix the type error.
- `eslint-disable` comments. Fix the code that violates the rule.

Understand why the checker reports an error before changing the code.

## Use strict equality and prefer constants

Use `===` and `!==`, not `==` or `!=` (`eqeqeq: always`). Use `const` for variables that are never reassigned (`prefer-const`).

## Choose consistent object types

Use index signatures or mapped types instead of `Record<K, V>`:

- For string keys, use a meaningful key name: `{ [userId: string]: User }`.
- For union keys, use a mapped type: `{ [k in Status]: Handler }`.

Use `as const` arrays and derived union types instead of `enum`:

```ts
const STATUSES = ['idle', 'loading', 'done'] as const;
type Status = typeof STATUSES[number];
```

Use either `interface` or `type` consistently within a file or project. Mix them only when extension semantics require it.

## Represent distinct states explicitly

When fields depend on the current state, use a discriminated union rather than optional fields. This prevents combinations the application cannot handle.

```ts
// Bad: invalid combinations representable.
type Result = { data?: User; error?: Error };

// Good: invariant enforced by the type.
type Result =
  | { status: 'ok'; data: User }
  | { status: 'err'; error: Error };
```

Make switches on unions exhaustive. Use `assertNever` in the default branch so an unhandled variant fails the build:

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

## Handle every promise

Do not leave floating promises. Use `await` or attach a `.catch()` handler. An unhandled rejection can terminate the process.
