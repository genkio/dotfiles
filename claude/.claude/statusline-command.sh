#!/bin/bash
# Claude Code Statusline

set -euo pipefail

# === Read context from Claude Code (stdin) ===
input=$(cat)

# Extract model ID (strip 'claude-' prefix for brevity)
model_id=$(echo "$input" | jq -r '.model.id // "unknown"')
model_id=${model_id#claude-}

# Extract effort level from settings
SETTINGS_FILE="$HOME/.claude/settings.json"
effort=$(jq -r '.effortLevel // empty' "$SETTINGS_FILE" 2>/dev/null)
if [[ -n "$effort" ]]; then
    model_id="$model_id ($effort)"
fi

# Extract token usage
total_input=$(echo "$input" | jq -r '.context_window.total_input_tokens // 0')
total_output=$(echo "$input" | jq -r '.context_window.total_output_tokens // 0')
context_size=$(echo "$input" | jq -r '.context_window.context_window_size // 0')
used_percent=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)

# Calculate total tokens in k
total_tokens=$((total_input + total_output))
total_k=$((total_tokens / 1000))
context_k=$((context_size / 1000))

# Format context size: use 'm' for multiples of 1000k
if (( context_k >= 1000 && context_k % 1000 == 0 )); then
    context_display="$((context_k / 1000))m"
else
    context_display="${context_k}k"
fi

# Current working directory (shorten home path to ~)
cwd=$(pwd)
cwd_display=$cwd
if [ -n "$HOME" ] && [[ "$cwd_display" == "$HOME"* ]]; then
    cwd_display="~${cwd_display#"$HOME"}"
fi

# Git branch
git_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)

# Git change stats (files, +additions, -deletions)
get_git_changes() {
    local stats
    stats=$(git diff --shortstat HEAD 2>/dev/null || git diff --shortstat 2>/dev/null || true)
    [[ -z "$stats" ]] && return

    local files adds dels
    files=$(echo "$stats" | grep -oE '[0-9]+ file' | grep -oE '[0-9]+' || echo "0")
    adds=$(echo "$stats" | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+' || echo "0")
    dels=$(echo "$stats" | grep -oE '[0-9]+ deletion' | grep -oE '[0-9]+' || echo "0")

    if [[ "$files" != "0" ]]; then
        echo "${files:-0},+${adds:-0},-${dels:-0}"
    fi
}

git_changes=$(get_git_changes 2>/dev/null || true)

# Build the status line: model/tokens plus local repo context
printf "%s · %dk/%s (%s%%) · %s" \
    "$model_id" "$total_k" "$context_display" "$used_percent" "$cwd_display"

if [[ -n "$git_branch" ]]; then
    if [[ -n "$git_changes" ]]; then
        printf " · %s · (%s)" "$git_branch" "$git_changes"
    else
        printf " · %s" "$git_branch"
    fi
fi
