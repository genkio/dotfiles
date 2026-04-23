#!/bin/bash
# Claude Code Statusline
# Uses built-in rate_limits from Claude Code v2.1.80+

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
elif [[ "$cwd_display" == "/Users/neo"* ]]; then
    cwd_display="~${cwd_display#/Users/neo}"
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

# === Parse built-in rate_limits from stdin ===

# Format reset time as absolute time (e.g., "7pm" or "tmr 10pm")
format_reset_time() {
    local reset_epoch="$1"
    [[ -z "$reset_epoch" || "$reset_epoch" == "null" || "$reset_epoch" == "0" ]] && { echo "?"; return; }

    local now today_start
    now=$(date +%s)
    today_start=$(date -j -f "%Y-%m-%d %H:%M:%S" "$(date +%Y-%m-%d) 00:00:00" +%s)

    local reset_day_start days_diff
    reset_day_start=$(date -j -r "$reset_epoch" +%Y-%m-%d 2>/dev/null)
    reset_day_start=$(date -j -f "%Y-%m-%d %H:%M:%S" "$reset_day_start 00:00:00" +%s 2>/dev/null || echo "$today_start")
    days_diff=$(( (reset_day_start - today_start) / 86400 ))

    # Round to nearest hour
    local minutes time_str
    minutes=$(date -j -r "$reset_epoch" "+%M" 2>/dev/null)
    if (( 10#$minutes >= 30 )); then
        reset_epoch=$((reset_epoch + 3600 - (10#$minutes * 60)))
    fi
    time_str=$(date -j -r "$reset_epoch" "+%-I%p" 2>/dev/null | tr '[:upper:]' '[:lower:]')

    if (( days_diff == 0 )); then
        echo "$time_str"
    elif (( days_diff == 1 )); then
        echo "tmr $time_str"
    elif (( days_diff < 7 )); then
        local day_name
        day_name=$(date -j -r "$reset_epoch" "+%a" 2>/dev/null)
        echo "$day_name $time_str"
    else
        local date_str
        date_str=$(date -j -r "$reset_epoch" "+%b%-d" 2>/dev/null)
        echo "$date_str $time_str"
    fi
}

get_usage_info() {
    local s_pct s_reset w_pct w_reset

    s_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
    s_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
    w_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
    w_reset=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

    # Bail if no rate limit data available
    [[ -z "$s_pct" && -z "$w_pct" ]] && return 1

    s_pct=$(awk "BEGIN {printf \"%.0f\", ${s_pct:-0}}" 2>/dev/null || echo "?")
    w_pct=$(awk "BEGIN {printf \"%.0f\", ${w_pct:-0}}" 2>/dev/null || echo "?")

    local s_time w_time
    s_time=$(format_reset_time "$s_reset")
    w_time=$(format_reset_time "$w_reset")

    echo "${s_time} (${s_pct}%) · ${w_time} (${w_pct}%)"
}

# === Build Output ===

usage_info=$(get_usage_info 2>/dev/null || echo "")

# First line: model/tokens plus local repo context
printf "%s · %dk/%s (%s%%) · %s" \
    "$model_id" "$total_k" "$context_display" "$used_percent" "$cwd_display"

if [[ -n "$git_branch" ]]; then
    if [[ -n "$git_changes" ]]; then
        printf " · %s · (%s)" "$git_branch" "$git_changes"
    else
        printf " · %s" "$git_branch"
    fi
fi

# Second line: usage info from built-in rate_limits
# if [[ -n "$usage_info" ]]; then
#     printf "\n%s" "$usage_info"
# fi
