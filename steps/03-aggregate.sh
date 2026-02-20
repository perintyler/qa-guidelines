#!/bin/bash
#
# Step 3: Aggregate results
# Combines individual module results into a summary
#
# Usage: 03-aggregate.sh RESULTS_DIR DISCOVERY_JSON
# Output: JSON summary to stdout
#

set -euo pipefail

RESULTS_DIR="${1:-}"
DISCOVERY_JSON="${2:-}"

if [[ -z "$RESULTS_DIR" ]] || [[ -z "$DISCOVERY_JSON" ]]; then
  echo "Usage: 03-aggregate.sh RESULTS_DIR DISCOVERY_JSON" >&2
  exit 1
fi

MODULES_WITH_QA=$(jq -r '.with_qa | length' "$DISCOVERY_JSON")
MODULES_WITHOUT_QA=$(jq -r '.without_qa | length' "$DISCOVERY_JSON")

TOTAL_CHECKPOINTS=0
PASSED_CHECKPOINTS=0
FAILED_CHECKPOINTS=0
MODULES_PASSED=0
MODULES_FAILED=0
MODULES_ERROR=0

RESULTS_JSON="["
first=true

for result_file in "$RESULTS_DIR"/*.json; do
  [[ -f "$result_file" ]] || continue

  name=$(jq -r '.module' "$result_file" 2>/dev/null || basename "$result_file" .json)
  overall=$(jq -r '.overall // "ERROR"' "$result_file" 2>/dev/null || echo "ERROR")
  checkpoints=$(jq -r '.checkpoints | length' "$result_file" 2>/dev/null || echo "0")
  passed=$(jq -r '[.checkpoints[] | select(.pass == true)] | length' "$result_file" 2>/dev/null || echo "0")
  failed=$((checkpoints - passed))

  TOTAL_CHECKPOINTS=$((TOTAL_CHECKPOINTS + checkpoints))
  PASSED_CHECKPOINTS=$((PASSED_CHECKPOINTS + passed))
  FAILED_CHECKPOINTS=$((FAILED_CHECKPOINTS + failed))

  case "$overall" in
    PASS) MODULES_PASSED=$((MODULES_PASSED + 1)) ;;
    FAIL) MODULES_FAILED=$((MODULES_FAILED + 1)) ;;
    *)    MODULES_ERROR=$((MODULES_ERROR + 1)) ;;
  esac

  if [[ "$first" == "true" ]]; then
    first=false
  else
    RESULTS_JSON+=","
  fi

  RESULTS_JSON+=$(cat "$result_file")
done

RESULTS_JSON+="]"

# Determine verdict
if [[ $MODULES_ERROR -gt 0 ]]; then
  VERDICT="ERROR"
  VERDICT_REASON="$MODULES_ERROR module(s) failed to run QA"
elif [[ $FAILED_CHECKPOINTS -gt 0 ]]; then
  VERDICT="FAIL"
  VERDICT_REASON="$FAILED_CHECKPOINTS checkpoint(s) failed across $MODULES_FAILED module(s)"
else
  VERDICT="PASS"
  VERDICT_REASON="All $PASSED_CHECKPOINTS checkpoints passed across $MODULES_WITH_QA modules"
fi

cat << EOF
{
  "verdict": "$VERDICT",
  "verdict_reason": "$VERDICT_REASON",
  "stats": {
    "modules_with_qa": $MODULES_WITH_QA,
    "modules_without_qa": $MODULES_WITHOUT_QA,
    "modules_passed": $MODULES_PASSED,
    "modules_failed": $MODULES_FAILED,
    "modules_error": $MODULES_ERROR,
    "total_checkpoints": $TOTAL_CHECKPOINTS,
    "passed_checkpoints": $PASSED_CHECKPOINTS,
    "failed_checkpoints": $FAILED_CHECKPOINTS
  },
  "results": $RESULTS_JSON,
  "missing_qa": $(jq '.without_qa' "$DISCOVERY_JSON")
}
EOF
