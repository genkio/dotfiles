// Deny-only permission gate.
//
// Mirrors the `permissions.deny` block of ~/.claude/settings.json: the listed
// commands and paths are blocked, everything else runs untouched. There is no
// allow list, no ask rule, no mode, and no prompt — a blocked call returns a
// reason the model reads in the tool result, so it can choose another approach
// or hand the action back to the user.
//
// Coverage:
//   - bash: every command in a chain (&&, ||, ;, |, newline, subshell) is
//     matched on its own, and shell wrappers are unwrapped and re-scanned, so
//     `cd x && rm -rf y`, `env FOO=1 sudo rm -rf /`, and
//     `bash -c 'rm -rf x'` are all caught.
//   - file tools: read/ls/grep/find are the read side, write/edit the write
//     side. A path matches in both the absolute form and its symlink-resolved
//     form, so an aliased shortcut to a protected file still fails.
//
// Not covered, same as the Claude rules this mirrors: a protected path named
// inside a bash command (`cat ~/.ssh/id_rsa`), commands assembled from a file
// or heredoc, and wrapper forms the unwrapper does not know. This is a guard
// against accidents, not a sandbox.

import { realpathSync } from "node:fs";
import { homedir } from "node:os";
import { basename, dirname, isAbsolute, join, resolve } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

// --- rules, ported from the Claude config ------------------------------------

type BashRule = {
  /** The Claude rule this implements, quoted back in the block reason. */
  label: string;
  reason: string;
  matches: (segment: string) => boolean;
};

const BASH_RULES: BashRule[] = [
  {
    label: "Bash(sudo *)",
    reason: "sudo runs as root and is the user's call",
    matches: (segment) => commandWord(segment) === "sudo",
  },
  {
    label: "Bash(mkfs *)",
    reason: "mkfs formats a device",
    matches: (segment) => commandWord(segment).startsWith("mkfs"),
  },
  {
    label: "Bash(rm -rf *)",
    reason: "recursive force delete",
    matches: isRecursiveForceRm,
  },
  {
    label: "Bash(git push --force*)",
    reason: "force push rewrites published history",
    matches: isForcePush,
  },
  {
    label: "Bash(git reset --hard*)",
    reason: "hard reset discards uncommitted work",
    matches: (segment) => {
      const words = tokens(segment);
      return words[0] === "git" && words[1] === "reset" && words.includes("--hard");
    },
  },
];

/** Read side, from Read(**) rules. `*` crosses directory separators. */
const READ_DENY = [
  "**/*.pem",
  "**/*.key",
  "**/.ssh/**",
  "**/secrets/**",
  "**/credentials/**",
  "**/.aws/**",
];

/** Write side, from the single Edit(~/.ssh/**) rule. */
const WRITE_DENY = ["**/.ssh/**"];

const READ_TOOLS = new Set(["read", "ls", "grep", "find"]);
const WRITE_TOOLS = new Set(["write", "edit"]);

// --- bash matching -----------------------------------------------------------

/** Split a command line into individual commands, respecting quotes. */
export function splitCommands(command: string): string[] {
  const segments: string[] = [];
  let current = "";
  let quote: string | undefined;
  for (let index = 0; index < command.length; index++) {
    const char = command[index];
    if (quote !== undefined) {
      current += char;
      if (char === "\\" && quote === '"') current += command[++index] ?? "";
      else if (char === quote) quote = undefined;
      continue;
    }
    if (char === "'" || char === '"') {
      quote = char;
      current += char;
      continue;
    }
    if (char === "\\") {
      current += char + (command[++index] ?? "");
      continue;
    }
    if ("\n;|&()".includes(char)) {
      segments.push(current);
      current = "";
      continue;
    }
    current += char;
  }
  return [...segments, current].map((s) => s.trim()).filter((s) => s.length > 0);
}

/**
 * Unwrap what hides a command from a prefix match: leading `VAR=value` and
 * `env` assignments, and a shell invoked with `-c`. Returns the innermost
 * command text, or the input when there is nothing to unwrap.
 */
export function unwrap(segment: string, depth = 3): string {
  if (depth <= 0) return segment;
  const words = segment.split(/\s+/).filter((word) => word.length > 0);
  let index = 0;
  while (
    index < words.length &&
    (words[index] === "env" || /^[A-Za-z_][A-Za-z0-9_]*=/.test(words[index]))
  ) {
    index++;
  }
  const shell = words[index] === undefined ? undefined : stripQuotes(words[index]);
  if (shell !== undefined && /^(?:ba|z|da|k)?sh$/.test(shell)) {
    const rest = words.slice(index + 1);
    const commandFlag = rest.findIndex((word) => word === "-c" || word === "--command");
    if (commandFlag >= 0) {
      const payload = stripOuterQuotes(rest.slice(commandFlag + 1).join(" "));
      return unwrap(payload, depth - 1);
    }
  }
  return words.slice(index).join(" ");
}

function stripQuotes(word: string): string {
  return word.replace(/^["']+|["']+$/g, "");
}

/** Remove one layer of matching surrounding quotes. */
function stripOuterQuotes(text: string): string {
  const quote = text[0];
  return (quote === "'" || quote === '"') && text.length > 1 && text.endsWith(quote)
    ? text.slice(1, -1)
    : text;
}

function tokens(segment: string): string[] {
  return unwrap(segment)
    .replace(/^["']|["']$/g, "")
    .split(/\s+/)
    .filter((word) => word.length > 0);
}

/** First word after stripping assignments and wrappers, unquoted. */
function commandWord(segment: string): string {
  const [word = ""] = tokens(segment);
  return word.replace(/^["']+|["']+$/g, "");
}

function isRecursiveForceRm(segment: string): boolean {
  const words = tokens(segment);
  if (words[0] !== "rm") return false;
  let recursive = false;
  let force = false;
  for (const word of words.slice(1)) {
    if (word === "--") break;
    if (!word.startsWith("-")) continue;
    if (word === "--recursive") recursive = true;
    else if (word === "--force") force = true;
    else if (/^-[A-Za-z]+$/.test(word)) {
      if (word.includes("r") || word.includes("R")) recursive = true;
      if (word.includes("f")) force = true;
    }
  }
  return recursive && force;
}

function isForcePush(segment: string): boolean {
  const words = tokens(segment);
  if (words[0] !== "git" || words[1] !== "push") return false;
  return words.slice(2).some(
    (word) =>
      word.startsWith("--force") ||
      word === "-f" ||
      (/^-[A-Za-z]+$/.test(word) && word.includes("f")),
  );
}

/** Match a command string, including nested shell wrappers. */
export function scanBash(command: string, depth = 3): string | undefined {
  for (const segment of splitCommands(command)) {
    const rule = BASH_RULES.find((candidate) => candidate.matches(segment));
    if (rule) {
      return `Denied by deny-guard: ${rule.label} — ${rule.reason}. Hand this to the user instead.`;
    }
    if (depth > 0) {
      const inner = unwrap(segment);
      if (inner !== segment) {
        const nested = scanBash(inner, depth - 1);
        if (nested) return nested;
      }
    }
  }
  return undefined;
}

// --- path matching -----------------------------------------------------------

function globToRegExp(pattern: string): RegExp {
  const expanded = pattern.startsWith("~") ? join(homedir(), pattern.slice(1)) : pattern;
  let source = "^";
  for (let index = 0; index < expanded.length; index++) {
    const char = expanded[index];
    if (char === "*") {
      if (expanded[index + 1] === "*") {
        if (expanded[index + 2] === "/") {
          source += "(?:.*/)?";
          index += 2;
        } else {
          source += ".*";
          index += 1;
        }
      } else {
        source += "[^/]*";
      }
    } else if (char === "?") {
      source += "[^/]";
    } else {
      source += char.replace(/[.+^${}()|[\]\\]/g, "\\$&");
    }
  }
  return new RegExp(`${source}$`);
}

const READ_PATTERNS = compilePatterns(READ_DENY);
const WRITE_PATTERNS = compilePatterns(WRITE_DENY);

/**
 * A `dir/**` rule also covers the directory itself, so `grep -r x ~/.ssh` is
 * blocked when the agent passes the directory rather than a file inside it.
 */
function compilePatterns(patterns: readonly string[]): (readonly [string, RegExp])[] {
  const compiled: (readonly [string, RegExp])[] = [];
  for (const pattern of patterns) {
    compiled.push([pattern, globToRegExp(pattern)] as const);
    if (pattern.endsWith("/**")) {
      compiled.push([pattern, globToRegExp(pattern.slice(0, -3))] as const);
    }
  }
  return compiled;
}

/** Symlink-resolved form; for a path that does not exist yet, its parent's. */
function resolvedPath(path: string): string | undefined {
  try {
    return realpathSync.native(path);
  } catch {
    const parent = dirname(path);
    if (parent === path) return undefined;
    const resolvedParent = resolvedPath(parent);
    return resolvedParent === undefined ? undefined : join(resolvedParent, basename(path));
  }
}

/** Absolute form plus the symlink-resolved one, so aliases cannot hide a match. */
export function pathCandidates(path: string, cwd: string): string[] {
  const expanded = path.startsWith("~") ? join(homedir(), path.slice(1)) : path;
  const absolute = isAbsolute(expanded) ? expanded : resolve(cwd, expanded);
  const resolved = resolvedPath(absolute);
  return resolved === undefined || resolved === absolute ? [absolute] : [absolute, resolved];
}

export function scanPath(path: string, cwd: string, patterns: readonly (readonly [string, RegExp])[]): string | undefined {
  for (const candidate of pathCandidates(path, cwd)) {
    for (const [pattern, expression] of patterns) {
      if (expression.test(candidate)) return pattern;
    }
  }
  return undefined;
}

// --- wiring ------------------------------------------------------------------

function stringField(input: unknown, key: string): string | undefined {
  if (typeof input !== "object" || input === null) return undefined;
  const value: unknown = Reflect.get(input, key);
  return typeof value === "string" ? value : undefined;
}

export default function (pi: ExtensionAPI): void {
  pi.on("tool_call", (event, ctx) => {
    if (event.toolName === "bash") {
      const command = stringField(event.input, "command");
      if (command === undefined) return undefined;
      const denial = scanBash(command);
      return denial === undefined ? undefined : { block: true, reason: denial };
    }

    const path = stringField(event.input, "path");
    if (path === undefined) return undefined;

    const patterns = READ_TOOLS.has(event.toolName)
      ? READ_PATTERNS
      : WRITE_TOOLS.has(event.toolName)
        ? WRITE_PATTERNS
        : undefined;
    if (patterns === undefined) return undefined;

    const denial = scanPath(path, ctx.cwd, patterns);
    if (denial === undefined) return undefined;
    const nextStep = WRITE_TOOLS.has(event.toolName)
      ? "Ask the user to make this change."
      : "If you really need the contents, ask the user for them.";
    return {
      block: true,
      reason: `Denied by deny-guard: '${path}' matches ${denial}, a protected path. ${nextStep}`,
    };
  });
}
