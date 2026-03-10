#!/bin/bash
# Claude Code Statusline
# Combines context info with usage API data

set -euo pipefail

# === Configuration ===
# Change to "basic" to disable usage API fetches.
# Modes:
#   basic    = only local/statusline data, no network usage fetch
#   advanced = current behavior, including cached/API usage stats
STATUSLINE_MODE="${CLAUDE_STATUSLINE_MODE:-basic}"

CREDENTIALS_FILE="$HOME/.claude/.credentials.json"
KEYCHAIN_SERVICE="Claude Code-credentials"
API_URL="https://api.anthropic.com/api/oauth/usage"
BETA_HEADER="oauth-2025-04-20"
CACHE_FILE="/tmp/claude_usage_cache.json"
LOCK_FILE="/tmp/claude_usage_lock"
CACHE_TTL=180   # 3 minutes - cache valid time
LOCK_TTL=30     # 30 seconds - rate limit between API calls

case "$STATUSLINE_MODE" in
    basic|advanced) ;;
    *) STATUSLINE_MODE="advanced" ;;
esac

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
    # Get both staged and unstaged changes
    local stats
    stats=$(git diff --shortstat HEAD 2>/dev/null || git diff --shortstat 2>/dev/null || true)
    [[ -z "$stats" ]] && return

    # Parse: "X files changed, Y insertions(+), Z deletions(-)"
    local files adds dels
    files=$(echo "$stats" | grep -oE '[0-9]+ file' | grep -oE '[0-9]+' || echo "0")
    adds=$(echo "$stats" | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+' || echo "0")
    dels=$(echo "$stats" | grep -oE '[0-9]+ deletion' | grep -oE '[0-9]+' || echo "0")

    # Only show if there are actual changes
    if [[ "$files" != "0" ]]; then
        echo "${files:-0},+${adds:-0},-${dels:-0}"
    fi
}

git_changes=$(get_git_changes 2>/dev/null || true)

# === Fetch Usage from API ===

get_token() {
    # On macOS, prefer keychain (where Claude Code stores the active token)
    if [[ "$(uname)" == "Darwin" ]]; then
        local keychain_data
        keychain_data=$(security find-generic-password -s "$KEYCHAIN_SERVICE" -w 2>/dev/null) || true
        if [[ -n "$keychain_data" ]]; then
            local token
            token=$(echo "$keychain_data" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
            if [[ -n "$token" ]]; then
                echo "$token"
                return 0
            fi
        fi
    fi

    # Fallback to credentials file (used on Linux, or if keychain fails)
    if [[ -f "$CREDENTIALS_FILE" ]]; then
        local token
        token=$(jq -r '.claudeAiOauth.accessToken // empty' "$CREDENTIALS_FILE" 2>/dev/null)
        if [[ -n "$token" ]]; then
            echo "$token"
            return 0
        fi
    fi

    return 1
}

is_cache_valid() {
    [[ -f "$CACHE_FILE" ]] || return 1
    local cache_age
    cache_age=$(($(date +%s) - $(stat -f %m "$CACHE_FILE" 2>/dev/null || echo 0)))
    (( cache_age < CACHE_TTL ))
}

# Rate limit: only try API once per LOCK_TTL seconds
is_rate_limited() {
    [[ -f "$LOCK_FILE" ]] || return 1
    local lock_age
    lock_age=$(($(date +%s) - $(stat -f %m "$LOCK_FILE" 2>/dev/null || echo 0)))
    (( lock_age < LOCK_TTL ))
}

touch_lock() {
    touch "$LOCK_FILE" 2>/dev/null || true
}

fetch_usage() {
    local token="$1"
    local response http_code body

    response=$(curl -s -w "\n%{http_code}" \
        -H "Authorization: Bearer $token" \
        -H "anthropic-beta: $BETA_HEADER" \
        -H "Accept: application/json" \
        "$API_URL" 2>/dev/null)

    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')

    if [[ "$http_code" == "200" ]]; then
        echo "$body" > "$CACHE_FILE"
        echo "$body"
        return 0
    fi
    return 1
}

# Format reset time as absolute time (e.g., "7pm" or "Sun 10pm")
format_reset_time() {
    local iso_date="$1"
    [[ -z "$iso_date" || "$iso_date" == "null" ]] && { echo "?"; return; }

    # Parse ISO8601 with timezone using Python for accuracy
    local reset_epoch
    reset_epoch=$(python3 -c "
from datetime import datetime
import sys
try:
    dt = datetime.fromisoformat('$iso_date'.replace('Z', '+00:00'))
    print(int(dt.timestamp()))
except:
    print(0)
" 2>/dev/null)

    [[ "$reset_epoch" == "0" || -z "$reset_epoch" ]] && { echo "?"; return; }

    local now today_start
    now=$(date +%s)
    today_start=$(date -j -f "%Y-%m-%d %H:%M:%S" "$(date +%Y-%m-%d) 00:00:00" +%s)

    # Calculate days difference
    local reset_day_start days_diff
    reset_day_start=$(date -j -r "$reset_epoch" +%Y-%m-%d 2>/dev/null)
    reset_day_start=$(date -j -f "%Y-%m-%d %H:%M:%S" "$reset_day_start 00:00:00" +%s 2>/dev/null || echo "$today_start")
    days_diff=$(( (reset_day_start - today_start) / 86400 ))

    # Format the time part (e.g., "7pm" or "10am")
    # Round to nearest hour (if minutes >= 30, round up)
    local minutes hour time_str
    minutes=$(date -j -r "$reset_epoch" "+%M" 2>/dev/null)
    if (( 10#$minutes >= 30 )); then
        # Round up: add 1 hour
        reset_epoch=$((reset_epoch + 3600 - (10#$minutes * 60)))
    fi
    time_str=$(date -j -r "$reset_epoch" "+%-I%p" 2>/dev/null | tr '[:upper:]' '[:lower:]')

    if (( days_diff == 0 )); then
        # Today: just show time
        echo "$time_str"
    elif (( days_diff == 1 )); then
        # Tomorrow
        echo "tmr $time_str"
    elif (( days_diff < 7 )); then
        # This week: show day name
        local day_name
        day_name=$(date -j -r "$reset_epoch" "+%a" 2>/dev/null)
        echo "$day_name $time_str"
    else
        # Further out: show date
        local date_str
        date_str=$(date -j -r "$reset_epoch" "+%b%-d" 2>/dev/null)
        echo "$date_str $time_str"
    fi
}

get_usage_info() {
    local usage_json=""

    # Fast path: return cached data if still valid
    if is_cache_valid; then
        usage_json=$(cat "$CACHE_FILE")
    else
        # Cache expired - check rate limit before calling API
        if is_rate_limited; then
            # Rate limited: use stale cache if available
            [[ -f "$CACHE_FILE" ]] && usage_json=$(cat "$CACHE_FILE")
        else
            # Not rate limited: try to fetch fresh data
            touch_lock
            local token
            token=$(get_token 2>/dev/null) || true
            if [[ -n "$token" ]]; then
                usage_json=$(fetch_usage "$token" 2>/dev/null) || true
            fi
            # Fallback to stale cache if fetch failed
            if [[ -z "$usage_json" && -f "$CACHE_FILE" ]]; then
                usage_json=$(cat "$CACHE_FILE")
            fi
        fi
    fi

    [[ -z "$usage_json" ]] && return 1

    # Parse usage
    local session_util session_reset weekly_util weekly_reset
    session_util=$(echo "$usage_json" | jq -r '.five_hour.utilization // empty')
    session_reset=$(echo "$usage_json" | jq -r '.five_hour.resets_at // empty')
    weekly_util=$(echo "$usage_json" | jq -r '.seven_day.utilization // empty')
    weekly_reset=$(echo "$usage_json" | jq -r '.seven_day.resets_at // empty')

    # Format percentages (no % sign for compactness)
    local s_pct w_pct
    s_pct=$(awk "BEGIN {printf \"%.0f\", ${session_util:-0}}" 2>/dev/null || echo "?")
    w_pct=$(awk "BEGIN {printf \"%.0f\", ${weekly_util:-0}}" 2>/dev/null || echo "?")

    # Format reset times
    local s_reset w_reset
    s_reset=$(format_reset_time "$session_reset")
    w_reset=$(format_reset_time "$weekly_reset")

    # Output: session_reset (pct%)/weekly_reset (pct%)
    echo "${s_reset} (${s_pct}%)/${w_reset} (${w_pct}%)"
}

# === Build Output ===

# Get usage info in advanced mode only (may fail silently)
usage_info=""
if [[ "$STATUSLINE_MODE" == "advanced" ]]; then
    usage_info=$(get_usage_info 2>/dev/null || echo "")
fi

# First line: model/tokens plus local repo context
printf "%s · %dk/%dk (%s%%) · %s" \
    "$model_id" "$total_k" "$context_k" "$used_percent" "$cwd_display"

if [[ -n "$git_branch" ]]; then
    if [[ -n "$git_changes" ]]; then
        printf " · %s · (%s)" "$git_branch" "$git_changes"
    else
        printf " · %s" "$git_branch"
    fi
fi

# Second line: usage info only when available in advanced mode
if [[ -n "$usage_info" ]]; then
    printf "\n%s" "$usage_info"
fi
