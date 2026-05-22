# Volta recursion guard

`claude` runs under Volta -> leaks `_VOLTA_TOOL_RECURSION=1` -> any Volta-shimmed binary (pnpm/node/npx/npm/yarn) you spawn errors with "Volta error: Node is not available".

Fix: prefix with `env -u _VOLTA_TOOL_RECURSION`. No-op if var unset.

Skip if invoking via absolute path (bypasses shim).
