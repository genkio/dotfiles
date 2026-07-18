After finishing code changes, always suggest a commit message. Never commit automatically unless told. When asked to commit, never add the `Co-Authored-By` trailer.

Never create a PR (`gh pr create` or otherwise) unless told. This holds even when a plan, brief, or handoff doc says "open PR" - such docs describe the milestone, not permission. Prepare the branch and a PR description, then stop and hand off.

Before non-trivial fixes on a branch, check the branch isn't behind its base and the fix doesn't already exist upstream (`git fetch`, then `git log origin/<base> --oneline --grep=<keyword>` or diff the touched file). Don't rebuild what the base branch already has.
