#!/bin/bash
#
# Step 2: Run QA for a single module
# Invokes Claude to execute the QA steps from QA.md
#
# Usage: 02-run.sh MODULE_NAME QA_FILE OUTPUT_FILE
# Output: JSON result written to OUTPUT_FILE
#

set -euo pipefail

MODULE_NAME="${1:-}"
QA_FILE="${2:-}"
OUTPUT_FILE="${3:-}"

if [[ -z "$MODULE_NAME" ]] || [[ -z "$QA_FILE" ]] || [[ -z "$OUTPUT_FILE" ]]; then
  echo "Usage: 02-run.sh MODULE_NAME QA_FILE OUTPUT_FILE" >&2
  exit 1
fi

if [[ ! -f "$QA_FILE" ]]; then
  echo "{\"module\": \"$MODULE_NAME\", \"checkpoints\": [], \"overall\": \"ERROR\", \"error\": \"Missing QA file: $QA_FILE\"}" > "$OUTPUT_FILE"
  exit 1
fi

MODULE_DIR=$(dirname "$QA_FILE")

# Build the prompt
PROMPT="You are a QA runner. Execute the QA checklist for $MODULE_NAME.

QA file: $QA_FILE
Module directory: $MODULE_DIR

Instructions:
1. Read QA.md
2. Note the setup/requirements section (don't run setup, just note requirements)
3. Execute each numbered test step
4. For each step, run the exact command in the code block
5. Compare output to the Expected description
6. Record PASS or FAIL with brief details

CRITICAL: Your final response must be ONLY valid JSON, nothing else:
{
  \"module\": \"$MODULE_NAME\",
  \"checkpoints\": [
    {\"name\": \"Step name\", \"pass\": true, \"details\": \"Brief result\"},
    ...
  ],
  \"overall\": \"PASS\" or \"FAIL\"
}

Set overall to PASS only if ALL checkpoints pass."

# Extract allowed tools from QA.md (if present)
# Format: <!-- tools: Bash,Read,... -->
ALLOWED_TOOLS="Bash,Read"
if tools_line=$(grep -o '<!-- tools: [^>]*-->' "$QA_FILE" | head -1); then
  ALLOWED_TOOLS=$(echo "$tools_line" | sed 's/<!-- tools: \(.*\) -->/\1/')
fi

# Run via Claude CLI
result=$(claude --print --allowedTools "$ALLOWED_TOOLS" --max-turns 15 "$PROMPT" 2>&1) || true

# Try to extract JSON from result
if json_part=$(echo "$result" | sed -n 's/.*\({[^{}]*"module"[^{}]*"checkpoints"[^{}]*}\).*/\1/p' | head -1) && [[ -n "$json_part" ]]; then
  echo "$json_part" > "$OUTPUT_FILE"
elif json_part=$(echo "$result" | sed -n '/```json/,/```/p' | grep -v '```' | tr -d '\n') && echo "$json_part" | jq -e . >/dev/null 2>&1; then
  echo "$json_part" > "$OUTPUT_FILE"
elif echo "$result" | jq -e '.module' >/dev/null 2>&1; then
  echo "$result" > "$OUTPUT_FILE"
else
  cat > "$OUTPUT_FILE" << EOF
{
  "module": "$MODULE_NAME",
  "checkpoints": [],
  "overall": "ERROR",
  "error": "Failed to parse Claude output",
  "raw_output": $(echo "$result" | jq -Rs .)
}
EOF
fi
