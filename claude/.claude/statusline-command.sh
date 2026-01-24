#!/bin/bash

# Read JSON input from Claude Code
input=$(cat)

# Extract model ID
model_id=$(echo "$input" | jq -r '.model.id // "unknown"')

# Extract token usage
total_input=$(echo "$input" | jq -r '.context_window.total_input_tokens // 0')
total_output=$(echo "$input" | jq -r '.context_window.total_output_tokens // 0')
context_size=$(echo "$input" | jq -r '.context_window.context_window_size // 0')
used_percent=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)

# Calculate total tokens in k
total_tokens=$((total_input + total_output))
total_k=$((total_tokens / 1000))
context_k=$((context_size / 1000))

# Output: model · tokens (percentage)
printf "%s · %dk/%dk tokens (%s%%)" "$model_id" "$total_k" "$context_k" "$used_percent"
