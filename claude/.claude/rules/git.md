After finishing code changes, always suggest a commit message. Never commit automatically unless told. When asked to commit, never add attribution trailers such as `Co-Authored-By` or `Claude-Session`.

Before non-trivial fixes on a branch, check the branch isn't behind its base.

In commit message bodies, do not hard-wrap lines. Write each paragraph as one long line and separate paragraphs with a blank line. Viewers such as GitHub soft-wrap at their own width, and a manual wrap that is wider than the viewer leaves a stray word on its own line.

Never create a new branch unless asked. Stay on the current branch, even when it is the default branch.

Never create a git worktree unless asked. This covers `EnterWorktree`, `git worktree add`, and subagent worktree isolation. Working inside an existing worktree is fine.
