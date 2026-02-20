#!/usr/bin/env bash
#
# Installs the QA sub-agent globally for Claude Code.
#
# Usage:
#   npx qa-guidelines install
#   # or after global install:
#   qa install
#

set -euo pipefail

QA_GUIDELINES_REPO_PATH="$(cd "$(dirname "$0")" && pwd)"
AGENTS_DIR="$HOME/.claude/agents"
AGENT_FILE="$AGENTS_DIR/qa.md"

mkdir -p "$AGENTS_DIR"
cp "$QA_GUIDELINES_REPO_PATH/agent/AGENT.md" "$AGENT_FILE"

# Add permission rules to ~/.claude/settings.json
SETTINGS_FILE="$HOME/.claude/settings.json"

if [[ -f "$SETTINGS_FILE" ]]; then
  # Check if permissions already include our rules
  if ! grep -q "Bash(npx qa" "$SETTINGS_FILE" 2>/dev/null; then
    # Use jq to merge permissions if available, otherwise inform user
    if command -v jq &>/dev/null; then
      tmp=$(mktemp)
      jq '.permissions.allow = ((.permissions.allow // []) + ["Bash(npx qa *)", "Bash(*/bin/qa *)"] | unique)' "$SETTINGS_FILE" > "$tmp" && mv "$tmp" "$SETTINGS_FILE"
      echo "Added QA permission rules to $SETTINGS_FILE"
    else
      echo "Note: Please add these to $SETTINGS_FILE manually:"
      echo '  "permissions": { "allow": ["Bash(npx qa *)", "Bash(*/bin/qa *)"] }'
    fi
  fi
else
  # Create new settings file
  mkdir -p "$(dirname "$SETTINGS_FILE")"
  cat > "$SETTINGS_FILE" << 'EOF'
{
  "permissions": {
    "allow": [
      "Bash(npx qa *)",
      "Bash(*/bin/qa *)"
    ]
  }
}
EOF
  echo "Created $SETTINGS_FILE with QA permission rules"
fi

echo "Installed QA sub-agent to $AGENT_FILE"
echo "You can now use /qa in Claude Code from any project."
