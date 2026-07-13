Subagents (Agent tool): always pass an explicit `model`. Research, search, review, and other read-mostly fan-out: sonnet (haiku for trivial lookups). Reserve the session's own model for subagents doing genuinely hard reasoning, and note why when you do.

Never poll background agents or tasks with sleep loops: end the turn instead - the completion notification resumes you automatically. A sleeping turn costs a full model call with thinking; the notification is free.
