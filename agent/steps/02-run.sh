#!/bin/bash
#
# Step 2: Run QA for a single module
# Invokes Claude to execute the QA steps from QA.md
#
# Usage: 02-run.sh MODULE_NAME QA_FILE OUTPUT_FILE
# Output: Markdown report written to OUTPUT_FILE
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
  cat > "$OUTPUT_FILE" << EOF
## $MODULE_NAME: ERROR

Missing QA file: $QA_FILE
EOF
  exit 1
fi

MODULE_DIR=$(dirname "$QA_FILE")

# Load prompt template and substitute variables
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROMPT_TEMPLATE="$SCRIPT_DIR/../prompts/qa-runner.md"

if [[ ! -f "$PROMPT_TEMPLATE" ]]; then
  echo "Error: Prompt template not found: $PROMPT_TEMPLATE" >&2
  exit 1
fi

PROMPT=$(cat "$PROMPT_TEMPLATE" | \
  sed "s|{{MODULE_NAME}}|$MODULE_NAME|g" | \
  sed "s|{{QA_FILE}}|$QA_FILE|g" | \
  sed "s|{{MODULE_DIR}}|$MODULE_DIR|g")

# Extract allowed tools from QA.md (if present)
# Format: <!-- tools: Bash,Read,... -->
ALLOWED_TOOLS="Bash,Read"
if tools_line=$(grep -o '<!-- tools: [^>]*-->' "$QA_FILE" | head -1); then
  ALLOWED_TOOLS=$(echo "$tools_line" | sed 's/<!-- tools: \(.*\) -->/\1/')
fi

# Run via Claude Agent SDK (avoids nested Claude Code session issues)
RUN_QUERY="$SCRIPT_DIR/../claude-runner.mjs"

result=$(node "$RUN_QUERY" "$PROMPT" "$MODULE_DIR" 15 "$ALLOWED_TOOLS" 2>&1) || true

# Write output directly - it should be markdown
if [[ -n "$result" ]]; then
  echo "$result" > "$OUTPUT_FILE"
else
  cat > "$OUTPUT_FILE" << EOF
## $MODULE_NAME: ERROR

No output received from Claude session.
EOF
fi
