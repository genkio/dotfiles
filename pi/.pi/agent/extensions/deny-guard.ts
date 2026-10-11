import { realpathSync } from "node:fs";
import { homedir } from "node:os";
import { basename, dirname, isAbsolute, join, resolve } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

type BashRule = {
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
    label: "Bash(gh pr create *)",
    reason: "opening a PR is the user's call",
    matches: (segment) => {
      const words = tokens(segment);
      return words[0] === "gh" && words[1] === "pr" && words[2] === "create";
    },
  },
  {
    label: "Bash(git reset --hard*)",
    reason: "hard reset discards uncommitted work",
    matches: (segment) => {
      const sub = gitSubcommand(tokens(segment));
      return sub?.name === "reset" && sub.rest.some((word) => isLongOption(word, "--hard"));
    },
  },
  {
    label: "Bash(git clean -*f*)",
    reason: "git clean deletes untracked files for good",
    matches: (segment) => {
      const sub = gitSubcommand(tokens(segment));
      if (sub?.name !== "clean") return false;
      const dryRun = sub.rest.some((word) => isLongOption(word, "--dry-run") || /^-[A-Za-z]*n/.test(word));
      return !dryRun && sub.rest.some((word) => isLongOption(word, "--force") || /^-[A-Za-z]*f/.test(word));
    },
  },
  {
    label: "Bash(aws <variable or substitution>)",
    reason: "the service or operation is only known at run time, so the guard can't check it",
    matches: (segment) => awsPositionals(segment)?.positional.some((word) => /[$`]/.test(word)) ?? false,
  },
  {
    label: "Bash(aws * delete-*)",
    reason: "AWS deletes can't be undone (databases, buckets, snapshots, keys)",
    matches: (segment) => /(?:^|-)delete-/.test(awsCommand(segment)?.operation ?? ""),
  },
  {
    label: "Bash(aws * terminate-*)",
    reason: "terminated instances can't be brought back",
    matches: (segment) => awsCommand(segment)?.operation.startsWith("terminate-") ?? false,
  },
  {
    label: "Bash(aws * purge-*)",
    reason: "purged messages are gone",
    matches: (segment) => awsCommand(segment)?.operation.startsWith("purge-") ?? false,
  },
  {
    label: "Bash(aws * schedule-key-deletion*)",
    reason: "deleting a KMS key makes everything it encrypted unreadable",
    matches: (segment) => awsCommand(segment)?.operation === "schedule-key-deletion",
  },
  {
    label: "Bash(aws * put-bucket-lifecycle*)",
    reason: "lifecycle rules can expire objects in bulk",
    matches: (segment) => awsCommand(segment)?.operation.startsWith("put-bucket-lifecycle") ?? false,
  },
  {
    label: "Bash(aws s3 rm *)",
    reason: "S3 deletes are permanent on unversioned buckets",
    matches: (segment) => isAws(segment, "s3", (operation) => operation === "rm"),
  },
  {
    label: "Bash(aws s3 rb *)",
    reason: "removing a bucket deletes it and frees the name",
    matches: (segment) => isAws(segment, "s3", (operation) => operation === "rb"),
  },
  {
    label: "Bash(aws s3 sync *--delete*)",
    reason: "sync --delete removes objects that are missing locally",
    matches: (segment) =>
      isAws(segment, "s3", (operation, rest) => operation === "sync" && awsOption(rest, "--delete") !== undefined),
  },
  {
    label: "Bash(aws rds modify-db-*--backup-retention-period 0*)",
    reason: "retention 0 deletes every automated backup",
    matches: (segment) =>
      isAws(segment, "rds", (operation, rest) => {
        const value = awsOption(rest, "--backup-retention-period");
        return operation.startsWith("modify-db-") && value !== undefined && (Number(value) === 0 || /[$`]/.test(value));
      }),
  },
  {
    label: "Bash(aws rds modify-db-*--no-deletion-protection*)",
    reason: "turning off deletion protection is the step before losing the database",
    matches: (segment) =>
      isAws(segment, "rds", (operation, rest) =>
        operation.startsWith("modify-db-") && awsOption(rest, "--no-deletion-protection") !== undefined),
  },
  {
    label: "Bash(aws rds modify-db-*--cli-input-*)",
    reason: "parameters passed as JSON or YAML input can't be checked for backup or deletion-protection changes",
    matches: (segment) =>
      isAws(segment, "rds", (operation, rest) =>
        operation.startsWith("modify-db-") &&
        (awsOption(rest, "--cli-input-json") !== undefined || awsOption(rest, "--cli-input-yaml") !== undefined)),
  },
];

const READ_DENY = [
  "**/*.pem",
  "**/*.key",
  "**/.ssh/**",
  "**/secrets/**",
  "**/credentials/**",
  "**/.aws/**",
];

const WRITE_DENY = ["**/.ssh/**", "**/.aws/**"];

const READ_TOOLS = new Set(["read", "ls", "grep", "find"]);
const WRITE_TOOLS = new Set(["write", "edit"]);

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

export function shellWords(text: string): string[] {
  const words: string[] = [];
  let current = "";
  let inWord = false;
  for (let index = 0; index < text.length; index++) {
    const char = text[index];
    if (/\s/.test(char)) {
      if (inWord) words.push(current);
      current = "";
      inWord = false;
      continue;
    }
    if (char === "\\" && text[index + 1] === "\n") {
      index++;
      continue;
    }
    inWord = true;
    if (char === "\\") {
      current += text[++index] ?? "";
    } else if (char === "$" && text[index + 1] === "'") {
      index += 2;
      while (index < text.length && text[index] !== "'") {
        if (text[index] === "\\") {
          const [decoded, length] = ansiCEscape(text, index + 1);
          current += decoded;
          index += 1 + length;
        } else {
          current += text[index++];
        }
      }
    } else if (char === "'") {
      const end = text.indexOf("'", index + 1);
      const stop = end < 0 ? text.length : end;
      current += text.slice(index + 1, stop);
      index = stop;
    } else if (char === '"') {
      index++;
      while (index < text.length && text[index] !== '"') {
        if (text[index] === "\\" && text[index + 1] === "\n") {
          index += 2;
          continue;
        }
        if (text[index] === "\\" && '"\\$`'.includes(text[index + 1] ?? "")) index++;
        current += text[index++];
      }
    } else {
      current += char;
    }
  }
  if (inWord) words.push(current);
  return words;
}

function ansiCEscape(text: string, start: number): [string, number] {
  const rest = text.slice(start);
  const hex = /^x([0-9A-Fa-f]{1,2})/.exec(rest) ?? /^u([0-9A-Fa-f]{1,4})/.exec(rest) ?? /^U([0-9A-Fa-f]{1,8})/.exec(rest);
  if (hex) return [String.fromCodePoint(parseInt(hex[1], 16)), hex[0].length];
  const octal = /^[0-7]{1,3}/.exec(rest);
  if (octal) return [String.fromCharCode(parseInt(octal[0], 8)), octal[0].length];
  const simple: Record<string, string> = { n: "\n", t: "\t", r: "\r", e: "\x1b", E: "\x1b" };
  const char = rest[0] ?? "";
  return [simple[char] ?? char, char.length];
}

const RESERVED_WORDS = new Set(["if", "then", "else", "elif", "while", "until", "do", "{", "!"]);
const SHELL = /^(?:ba|z|da|k)?sh$/;
const RUNS_STDIN = new Set(["eval", "source", "."]);

const WRAPPERS = new Map<string, Set<string>>([
  ["env", new Set(["-u", "--unset", "-C", "--chdir"])],
  ["command", new Set()],
  ["builtin", new Set()],
  ["exec", new Set(["-a"])],
  ["nohup", new Set()],
  ["time", new Set(["-f", "-o"])],
  ["nice", new Set(["-n"])],
  ["timeout", new Set(["-s", "-k", "--signal", "--kill-after"])],
  ["xargs", new Set(["-I", "-n", "-P", "-L", "-s", "-d", "-E", "-a"])],
]);

function tokens(segment: string): string[] {
  const words = shellWords(segment);
  let index = 0;
  while (index < words.length) {
    if (RESERVED_WORDS.has(words[index]) || /^[A-Za-z_][A-Za-z0-9_]*=/.test(words[index])) {
      index++;
      continue;
    }
    const name = basename(words[index]);
    const valued = WRAPPERS.get(name);
    if (valued === undefined) break;
    if (name === "command" && /^-[A-Za-z]*[vV]/.test(words[index + 1] ?? "")) return [];
    index++;
    while (index < words.length && words[index].startsWith("-")) {
      const option = words[index];
      if (name === "env" && (option === "-S" || option === "--split-string")) {
        words.splice(index, 2, ...shellWords(words[index + 1] ?? ""));
        break;
      }
      index += valued.has(option) ? 2 : 1;
    }
    if (name === "timeout") index++;
  }
  const command = words.slice(index);
  if (command.length > 0) command[0] = basename(command[0]);
  return command;
}

export function unwrap(segment: string): string {
  const words = tokens(segment);
  if (SHELL.test(words[0] ?? "")) {
    const flag = words.findIndex((word, index) => index > 0 && (word === "--command" || /^-[A-Za-z]*c[A-Za-z]*$/.test(word)));
    const payload = words[flag + 1] === "--" ? flag + 2 : flag + 1;
    if (flag >= 0 && words[payload] !== undefined) return words[payload];
    const herestring = words.findIndex((word) => word.startsWith("<<<"));
    if (herestring > 0) return words[herestring].length > 3 ? words[herestring].slice(3) : (words[herestring + 1] ?? segment);
  }
  if (words[0] === "eval") return words.slice(1).join(" ");
  return segment;
}

// A heredoc body only runs as commands when a shell reads it, but an unquoted delimiter
// still expands `$(…)` in the body whoever reads it.
function heredocs(command: string): { commands: string; expanded: string } {
  let commands = "";
  let expanded = "";
  let line = "";
  let quote: string | undefined;
  const pending: { delimiter: string; quoted: boolean; stripTabs: boolean }[] = [];
  let index = 0;
  while (index < command.length) {
    const char = command[index];
    if (quote === undefined && command.startsWith("<<", index) && command[index + 2] !== "<") {
      const match = /^<<(-?)[ \t]*((?:'[^']*'|"[^"]*"|\\.|[^\s;|&()<>'"\\])+)/.exec(command.slice(index));
      if (match) {
        pending.push({ delimiter: shellWords(match[2])[0] ?? "", quoted: /['"\\]/.test(match[2]), stripTabs: match[1] === "-" });
        line += match[0];
        index += match[0].length;
        continue;
      }
    }
    if (char === "\\" && quote !== "'") {
      line += char + (command[index + 1] ?? "");
      index += 2;
      continue;
    }
    if (quote !== undefined) {
      if (char === quote) quote = undefined;
    } else if (char === "'" || char === '"') {
      quote = char;
    }
    line += char;
    index++;
    if (char !== "\n" || quote !== undefined) continue;
    commands += line;
    expanded += line;
    if (pending.length > 0) {
      const runs = splitCommands(line).some((segment) => {
        const word = tokens(segment)[0] ?? "";
        return SHELL.test(word) || RUNS_STDIN.has(word);
      });
      for (const doc of pending) {
        let body = "";
        let closed = false;
        while (index < command.length) {
          const end = command.indexOf("\n", index);
          const stop = end < 0 ? command.length : end + 1;
          const text = command.slice(index, stop);
          index = stop;
          const bare = text.endsWith("\n") ? text.slice(0, -1) : text;
          closed = (doc.stripTabs ? bare.replace(/^\t+/, "") : bare) === doc.delimiter;
          if (closed) break;
          body += text;
        }
        // Without a closing line it may not be a heredoc at all (`$((1<<2))`), so scan it.
        if (runs || !closed) commands += body;
        if (!doc.quoted || !closed) expanded += body;
      }
      pending.length = 0;
    }
    line = "";
  }
  return { commands: commands + line, expanded: expanded + line };
}

// Substitutions run even inside double quotes, so they get scanned on their own.
function substitutions(command: string): string[] {
  const bodies: string[] = [];
  let single = false;
  let double = false;
  for (let index = 0; index < command.length; index++) {
    const char = command[index];
    if (char === "\\" && !single) {
      index++;
    } else if (char === "'" && !double) {
      single = !single;
    } else if (char === '"' && !single) {
      double = !double;
    } else if (single) {
      continue;
    } else if (char === "$" && command[index + 1] === "(") {
      let depth = 1;
      let end = index + 2;
      let quote: string | undefined;
      while (end < command.length && depth > 0) {
        const inner = command[end];
        if (quote !== undefined) {
          if (inner === "\\" && quote === '"') end++;
          else if (inner === quote) quote = undefined;
        } else if (inner === "'" || inner === '"') {
          quote = inner;
        } else if (inner === "\\") {
          end++;
        } else if (inner === "(") {
          depth++;
        } else if (inner === ")") {
          depth--;
        }
        end++;
      }
      bodies.push(command.slice(index + 2, depth === 0 ? end - 1 : end));
      index = end - 1;
    } else if (char === "`") {
      const end = command.indexOf("`", index + 1);
      const stop = end < 0 ? command.length : end;
      bodies.push(command.slice(index + 1, stop));
      index = stop;
    }
  }
  return bodies;
}

function isLongOption(word: string, name: string): boolean {
  const key = word.split("=")[0];
  return key.startsWith("--") && key.length >= 3 && name.startsWith(key);
}

function commandWord(segment: string): string {
  return tokens(segment)[0] ?? "";
}

function isRecursiveForceRm(segment: string): boolean {
  const words = tokens(segment);
  if (words[0] !== "rm") return false;
  let recursive = false;
  let force = false;
  for (const word of words.slice(1)) {
    if (word === "--") break;
    if (!word.startsWith("-")) continue;
    if (isLongOption(word, "--recursive")) recursive = true;
    else if (isLongOption(word, "--force")) force = true;
    else if (/^-[A-Za-z]+$/.test(word)) {
      if (word.includes("r") || word.includes("R")) recursive = true;
      if (word.includes("f")) force = true;
    }
  }
  return recursive && force;
}

function gitSubcommand(words: string[]): { name: string; rest: string[] } | undefined {
  if (words[0] !== "git") return undefined;
  const takesValue = new Set(["-C", "-c", "--git-dir", "--work-tree", "--namespace", "--exec-path"]);
  let index = 1;
  while (index < words.length) {
    const word = words[index];
    if (takesValue.has(word)) {
      index += 2;
      continue;
    }
    if (word.startsWith("-")) {
      index += 1;
      continue;
    }
    return { name: word, rest: words.slice(index + 1) };
  }
  return undefined;
}

// The CLI accepts any unambiguous prefix of an option, so `--reg` is `--region` and `--del` is `--delete`.
const AWS_GLOBALS_WITH_VALUE = [
  "--region", "--profile", "--output", "--endpoint-url", "--query", "--color", "--ca-bundle",
  "--cli-read-timeout", "--cli-connect-timeout", "--cli-binary-format",
];

function awsPositionals(segment: string): { positional: string[]; rest: string[] } | undefined {
  const words = tokens(segment);
  if (words[0] !== "aws") return undefined;
  const positional: string[] = [];
  let index = 1;
  for (; index < words.length && positional.length < 2; index++) {
    const word = words[index];
    if (AWS_GLOBALS_WITH_VALUE.some((name) => isLongOption(word, name) && !word.includes("="))) index += 1;
    else if (!word.startsWith("-")) positional.push(word);
  }
  return { positional, rest: words.slice(index) };
}

function awsCommand(segment: string): { service: string; operation: string; rest: string[] } | undefined {
  const parsed = awsPositionals(segment);
  if (parsed === undefined || parsed.positional.length < 2) return undefined;
  const [service, operation] = parsed.positional;
  if (parsed.rest[0] === "help") return undefined;
  return { service, operation, rest: parsed.rest };
}

function awsOption(rest: string[], name: string): string | undefined {
  for (let index = 0; index < rest.length; index++) {
    if (!isLongOption(rest[index], name)) continue;
    const equals = rest[index].indexOf("=");
    return equals >= 0 ? rest[index].slice(equals + 1) : (rest[index + 1] ?? "");
  }
  return undefined;
}

function isAws(segment: string, service: string, matches: (operation: string, rest: string[]) => boolean): boolean {
  const aws = awsCommand(segment);
  return aws?.service === service && matches(aws.operation, aws.rest);
}

function isForcePush(segment: string): boolean {
  const sub = gitSubcommand(tokens(segment));
  if (sub === undefined || sub.name !== "push") return false;
  return sub.rest.some(
    (word) =>
      word.startsWith("--force") ||
      isLongOption(word, "--force") ||
      (/^-[A-Za-z]+$/.test(word) && word.includes("f")) ||
      word.startsWith("+"),
  );
}

export function scanBash(command: string, depth = 3): string | undefined {
  const { commands, expanded } = heredocs(command);
  for (const segment of splitCommands(commands)) {
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
  if (depth > 0) {
    for (const body of substitutions(expanded)) {
      const nested = scanBash(body, depth - 1);
      if (nested) return nested;
    }
  }
  return undefined;
}

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
