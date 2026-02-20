#!/bin/bash
#
# QA Orchestrator
# Discovers QA.md files in a project, runs them via Claude, and generates a report.
#
# Usage: qa.sh [OPTIONS] [PROJECT_ROOT]
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STEPS_DIR="$SCRIPT_DIR/steps"
REPORTS_DIR="$SCRIPT_DIR/.reports"

# Defaults
STRICT=false
MODULE=""
PROJECT_ROOT=""

# Parse args
while [[ $# -gt 0 ]]; do
  case $1 in
    --strict)
      STRICT=true
      shift
      ;;
    --module=*)
      MODULE="${1#*=}"
      shift
      ;;
    --help|-h)
      cat << EOF
QA Orchestrator — Run QA across all modules in a project

Usage: qa.sh [OPTIONS] [PROJECT_ROOT]

Arguments:
  PROJECT_ROOT           Path to the project to QA (default: current directory)

Options:
  --strict               Fail if any modules are missing QA.md
  --module=PATH          QA a specific module by path
  --help                 Show this help

Examples:
  ./qa.sh /path/to/project            # Run QA on all modules
  ./qa.sh --strict .                   # Strict mode in current dir
  ./qa.sh --module=apps/web .          # QA only apps/web

Output:
  Reports are written to: $REPORTS_DIR/
EOF
      exit 0
      ;;
    -*)
      echo "Unknown option: $1" >&2
      echo "Use --help for usage" >&2
      exit 1
      ;;
    *)
      if [[ -z "$PROJECT_ROOT" ]]; then
        PROJECT_ROOT="$1"
      else
        # Treat as module if project root already set
        MODULE="$1"
      fi
      shift
      ;;
  esac
done

# Default to current directory
if [[ -z "$PROJECT_ROOT" ]]; then
  PROJECT_ROOT="$(pwd)"
fi

PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"

# Generate identifiers
TIMESTAMP=$(date +%Y-%m-%d-%H%M%S)
BRANCH=$(git -C "$PROJECT_ROOT" branch --show-current 2>/dev/null || echo "unknown")
BRANCH_SAFE=$(echo "$BRANCH" | tr '/' '-')
REPORT_ID="$TIMESTAMP-$BRANCH_SAFE"

# Create temp directory for intermediate files
WORK_DIR=$(mktemp -d)
trap "rm -rf $WORK_DIR" EXIT

mkdir -p "$REPORTS_DIR"

echo "═══════════════════════════════════════════════════════════"
echo "  QA Orchestrator"
echo "  Project: $PROJECT_ROOT"
echo "  Report ID: $REPORT_ID"
echo "═══════════════════════════════════════════════════════════"
echo ""

# ─────────────────────────────────────────────────────────────────
# Step 1: Discovery
# ─────────────────────────────────────────────────────────────────

echo "Step 1: Discovery"
echo "─────────────────"

DISCOVERY_FILE="$WORK_DIR/discovery.json"

if [[ -n "$MODULE" ]]; then
  # Single module mode
  MODULE_PATH="$PROJECT_ROOT/$MODULE"
  if [[ -d "$MODULE" ]]; then
    MODULE_PATH="$(cd "$MODULE" && pwd)"
  fi
  MODULE_NAME="$MODULE"

  if [[ ! -d "$MODULE_PATH" ]]; then
    echo "  Module not found: $MODULE" >&2
    exit 1
  fi

  QA_FILE="$MODULE_PATH/QA.md"
  if [[ -f "$QA_FILE" ]]; then
    cat > "$DISCOVERY_FILE" << EOF
{
  "project_root": "$PROJECT_ROOT",
  "single_module": true,
  "with_qa": [{"name": "$MODULE_NAME", "path": "$MODULE_PATH", "qa_file": "$QA_FILE"}],
  "without_qa": []
}
EOF
  else
    cat > "$DISCOVERY_FILE" << EOF
{
  "project_root": "$PROJECT_ROOT",
  "single_module": true,
  "with_qa": [],
  "without_qa": [{"name": "$MODULE_NAME", "path": "$MODULE_PATH"}]
}
EOF
  fi
else
  bash "$STEPS_DIR/01-discover.sh" "$PROJECT_ROOT" > "$DISCOVERY_FILE"
fi

# Print summary
WITH_QA=$(jq -r '.with_qa | length' "$DISCOVERY_FILE")
WITHOUT_QA=$(jq -r '.without_qa | length' "$DISCOVERY_FILE")

echo "  Modules with QA.md:"
jq -r '.with_qa[] | "    \(.name)"' "$DISCOVERY_FILE"

if [[ "$WITHOUT_QA" -gt 0 ]]; then
  echo "  Modules without QA.md:"
  jq -r '.without_qa[] | "    \(.name)"' "$DISCOVERY_FILE"
fi

echo ""
echo "  Total: $WITH_QA with QA, $WITHOUT_QA without"
echo ""

if [[ "$WITH_QA" -eq 0 ]]; then
  echo "No modules with QA.md found."
  if [[ "$STRICT" == "true" ]] && [[ "$WITHOUT_QA" -gt 0 ]]; then
    echo "FAIL: Strict mode - $WITHOUT_QA modules missing QA.md"
    exit 1
  fi
  exit 0
fi

# ─────────────────────────────────────────────────────────────────
# Step 2: Run QA (parallel)
# ─────────────────────────────────────────────────────────────────

echo "Step 2: Running QA"
echo "──────────────────"

RESULTS_DIR="$WORK_DIR/results"
mkdir -p "$RESULTS_DIR"

pids=()
while IFS='|' read -r name qa_file; do
  echo "  Starting: $name"
  safe_name=$(echo "$name" | tr '/' '-')
  bash "$STEPS_DIR/02-run.sh" "$name" "$qa_file" "$RESULTS_DIR/$safe_name.json" &
  pids+=($!)
done < <(jq -r '.with_qa[] | "\(.name)|\(.qa_file)"' "$DISCOVERY_FILE")

for pid in "${pids[@]}"; do
  wait "$pid" || true
done

echo "  All modules completed"
echo ""

# ─────────────────────────────────────────────────────────────────
# Step 3: Aggregate
# ─────────────────────────────────────────────────────────────────

echo "Step 3: Aggregating Results"
echo "───────────────────────────"

SUMMARY_FILE="$WORK_DIR/summary.json"
bash "$STEPS_DIR/03-aggregate.sh" "$RESULTS_DIR" "$DISCOVERY_FILE" > "$SUMMARY_FILE"

jq -r '.results[] | "\(.overall)|\(.module)|\(.checkpoints | length)|\([.checkpoints[] | select(.pass == true)] | length)"' "$SUMMARY_FILE" | while IFS='|' read -r overall name total passed; do
  case "$overall" in
    PASS) echo "  PASS $name: $passed/$total checkpoints passed" ;;
    FAIL) echo "  FAIL $name: $passed/$total checkpoints passed" ;;
    *)    echo "  ERROR $name: error running QA" ;;
  esac
done

echo ""

# ─────────────────────────────────────────────────────────────────
# Step 4: Generate Report
# ─────────────────────────────────────────────────────────────────

echo "Step 4: Generating Report"
echo "─────────────────────────"

REPORT_FILE="$REPORTS_DIR/report-$REPORT_ID.md"
bash "$STEPS_DIR/04-report.sh" "$SUMMARY_FILE" "$REPORT_ID" "$REPORT_FILE"

echo ""

# ─────────────────────────────────────────────────────────────────
# Final Verdict
# ─────────────────────────────────────────────────────────────────

VERDICT=$(jq -r '.verdict' "$SUMMARY_FILE")
VERDICT_REASON=$(jq -r '.verdict_reason' "$SUMMARY_FILE")

if [[ "$STRICT" == "true" ]] && [[ "$WITHOUT_QA" -gt 0 ]] && [[ "$VERDICT" == "PASS" ]]; then
  VERDICT="FAIL"
  VERDICT_REASON="$WITHOUT_QA module(s) missing QA.md (strict mode)"
fi

echo "═══════════════════════════════════════════════════════════"
echo "  Verdict: $VERDICT"
echo "  $VERDICT_REASON"
echo ""
echo "  Report: $REPORT_FILE"
echo "═══════════════════════════════════════════════════════════"

[[ "$VERDICT" == "PASS" ]] && exit 0 || exit 1
