// Unit tests for the deny-guard pi extension.
//
// Drives the real tool_call handler with a stub ExtensionAPI, so a change to
// the rule list is checked against the allow/deny table below instead of
// against a live session. Run with: make test-deny-guard
//
// The cases mirror the Claude `permissions.deny` block the extension ports:
// both the blocks and the *non*-blocks matter, because a guard that also
// blocks ordinary work is worse than no guard.

import { mkdtempSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const repoRoot = resolve(fileURLToPath(import.meta.url), "../..");
const extensionPath = join(repoRoot, "pi/.pi/agent/extensions/deny-guard.ts");

const { default: denyGuard } = await import(extensionPath);

let toolCallHandler;
denyGuard({
  on(event, handler) {
    if (event === "tool_call") toolCallHandler = handler;
  },
});
if (!toolCallHandler) throw new Error("deny-guard registered no tool_call handler");

const ctx = { cwd: repoRoot };
const bash = (command) => toolCallHandler({ toolName: "bash", input: { command } }, ctx);
const file = (toolName, path) => toolCallHandler({ toolName, input: { path } }, ctx);

const cases = [];
const blocked = (name, result) => cases.push({ name, want: true, got: result?.block === true, reason: result?.reason });
const allowed = (name, result) => cases.push({ name, want: false, got: result?.block === true });

const fixtures = mkdtempSync(join(tmpdir(), "deny-guard-test-"));
try {
  writeFileSync(join(fixtures, "secret.pem"), "SECRET");
  symlinkSync(join(fixtures, "secret.pem"), join(fixtures, "alias.txt"));

  // Blocked bash
  blocked("rm -rf", bash("rm -rf /tmp/x"));
  blocked("rm -fr", bash("rm -fr /tmp/x"));
  blocked("rm --recursive --force", bash("rm --recursive --force /tmp/x"));
  blocked("rm -rfv", bash("rm -rfv build"));
  blocked("chained rm -rf", bash("cd /tmp && rm -rf build"));
  blocked("subshell rm -rf", bash("(rm -rf /tmp/x)"));
  blocked("sudo", bash("sudo ls"));
  blocked("sudo after env assignments", bash("env FOO=1 BAR=2 sudo rm -rf /"));
  blocked("bash -c wrapper", bash("bash -c 'rm -rf /tmp/x'"));
  blocked("sh -c wrapper with sudo", bash('sh -c "sudo true"'));
  blocked("nested wrapper", bash("env X=1 bash -c 'sh -c \"sudo ls\"'"));
  blocked("mkfs", bash("mkfs.ext4 /dev/disk2"));
  blocked("force push", bash("git push --force origin main"));
  blocked("force push shorthand", bash("git push -f"));
  blocked("force push with lease", bash("git push origin main --force-with-lease"));
  blocked("hard reset", bash("git reset --hard HEAD~1"));
  blocked("chained hard reset", bash("git fetch && git reset --hard origin/main"));

  // Allowed bash
  allowed("plain ls", bash("ls -la"));
  allowed("git status", bash("git status --short"));
  allowed("rm force only", bash("rm -f /tmp/x"));
  allowed("rm recursive only", bash("rm -r /tmp/build"));
  allowed("normal push", bash("git push origin main"));
  allowed("soft reset", bash("git reset HEAD~1"));
  allowed("quoted rm -rf", bash('echo "rm -rf /"'));
  allowed("grep for sudo", bash('grep -rn "sudo" src/'));
  allowed("commit message mentions rm -rf", bash('git commit -m "rm -rf cleanup"'));
  allowed("sudo-looking filename", bash("ls sudo-file.txt"));

  // Blocked paths (read side, then write side)
  blocked("read .pem", file("read", join(fixtures, "secret.pem")));
  blocked("read .key", file("read", "~/.config/app/private.key"));
  blocked("read ~/.ssh", file("read", "~/.ssh/id_rsa"));
  blocked("read relative path", file("read", "secrets/db.txt"));
  blocked("read .aws credentials", file("read", "~/.aws/credentials"));
  blocked("grep in .ssh", file("grep", "~/.ssh"));
  blocked("ls credentials dir", file("ls", "/srv/app/credentials"));
  blocked("write into .ssh", file("write", "~/.ssh/authorized_keys"));
  blocked("edit .ssh config", file("edit", "~/.ssh/config"));
  blocked("symlink alias to .pem", file("read", join(fixtures, "alias.txt")));

  // Allowed paths
  allowed("read normal file", file("read", "~/dotfiles/README.md"));
  allowed("write normal file", file("write", "~/dotfiles/notes.md"));
  allowed("edit normal file", file("edit", "~/dotfiles/AGENTS.md"));
  allowed("read .env.example", file("read", "~/proj/.env.example"));
  allowed("ls project", file("ls", "~/dotfiles"));
  allowed("write pem-shaped name", file("write", "~/proj/key.pem.bak"));
  allowed("unrelated tool passthrough", toolCallHandler({ toolName: "web_search", input: { query: "sudo" } }, ctx));

  const failures = cases.filter((testCase) => testCase.got !== testCase.want);
  for (const testCase of cases) {
    const mark = testCase.got === testCase.want ? "ok  " : "FAIL";
    const expectation = testCase.want ? "block" : "allow";
    console.log(`${mark} ${expectation}  ${testCase.name}${testCase.reason ? `  ->  ${testCase.reason}` : ""}`);
  }
  console.log(`\n${cases.length - failures.length}/${cases.length} passed`);
  process.exitCode = failures.length === 0 ? 0 : 1;
} finally {
  rmSync(fixtures, { recursive: true, force: true });
}
