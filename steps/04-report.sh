#!/bin/bash
#
# Step 4: Generate markdown report
# Converts aggregated JSON into a readable module report
#
# Usage: 04-report.sh SUMMARY_JSON REPORT_ID OUTPUT_FILE
# Output: Markdown report written to OUTPUT_FILE
#

set -euo pipefail

SUMMARY_JSON="${1:-}"
REPORT_ID="${2:-}"
OUTPUT_FILE="${3:-}"

if [[ -z "$SUMMARY_JSON" ]] || [[ -z "$REPORT_ID" ]] || [[ -z "$OUTPUT_FILE" ]]; then
  echo "Usage: 04-report.sh SUMMARY_JSON REPORT_ID OUTPUT_FILE" >&2
  exit 1
fi

BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
TIMESTAMP=$(date -u +"%Y-%m-%d %H:%M:%S UTC")

VERDICT=$(jq -r '.verdict' "$SUMMARY_JSON")
VERDICT_REASON=$(jq -r '.verdict_reason' "$SUMMARY_JSON")

cat > "$OUTPUT_FILE" << EOF
# QA Report: $REPORT_ID

**Generated:** $TIMESTAMP
**Branch:** $BRANCH
**Commit:** $COMMIT

## Summary

| Metric | Value |
|--------|-------|
| Modules QA'd | $(jq -r '.stats.modules_with_qa' "$SUMMARY_JSON") |
| Modules Missing QA | $(jq -r '.stats.modules_without_qa' "$SUMMARY_JSON") |
| Total Checkpoints | $(jq -r '.stats.total_checkpoints' "$SUMMARY_JSON") |
| Passed | $(jq -r '.stats.passed_checkpoints' "$SUMMARY_JSON") |
| Failed | $(jq -r '.stats.failed_checkpoints' "$SUMMARY_JSON") |
| **Verdict** | $VERDICT |

**$VERDICT**: $VERDICT_REASON

---

## Results by Module

EOF

jq -r '.results[] | @base64' "$SUMMARY_JSON" | while read -r encoded; do
  result=$(echo "$encoded" | base64 -d)
  name=$(echo "$result" | jq -r '.module')
  overall=$(echo "$result" | jq -r '.overall')

  echo "### $name ($overall)" >> "$OUTPUT_FILE"
  echo "" >> "$OUTPUT_FILE"
  echo "| Checkpoint | Status | Details |" >> "$OUTPUT_FILE"
  echo "|------------|--------|---------|" >> "$OUTPUT_FILE"

  checkpoint_count=$(echo "$result" | jq '.checkpoints | length')
  if [[ "$checkpoint_count" -gt 0 ]]; then
    echo "$result" | jq -r '.checkpoints[] | "| \(.name // "Unknown") | \(if .pass then "PASS" else "FAIL" end) | \(.details // "-" | gsub("\n"; " ")) |"' >> "$OUTPUT_FILE"
  else
    error=$(echo "$result" | jq -r '.error // "No checkpoints found"')
    echo "| - | ERROR | $error |" >> "$OUTPUT_FILE"
  fi

  echo "" >> "$OUTPUT_FILE"
done

MISSING_COUNT=$(jq -r '.missing_qa | length' "$SUMMARY_JSON")
if [[ "$MISSING_COUNT" -gt 0 ]]; then
  cat >> "$OUTPUT_FILE" << EOF
---

## Missing QA Files

The following modules do not have QA.md files:

| Module |
|-----------|
EOF

  jq -r '.missing_qa[] | "| \(.name) |"' "$SUMMARY_JSON" >> "$OUTPUT_FILE"
  echo "" >> "$OUTPUT_FILE"
fi

cat >> "$OUTPUT_FILE" << 'EOF'

---

## Raw Data

<details>
<summary>Click to expand raw JSON results</summary>

```json
EOF

jq '.' "$SUMMARY_JSON" >> "$OUTPUT_FILE"

cat >> "$OUTPUT_FILE" << 'EOF'
```

</details>
EOF

echo "Report written to: $OUTPUT_FILE" >&2
